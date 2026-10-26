from concurrent.futures import ThreadPoolExecutor
from datetime import UTC, datetime, timedelta
from threading import Event
from unittest.mock import Mock

import pytest
import sqlalchemy as sa

from app.extensions import db
from app.models import Booking, Device, User

PATH = "/api/v1/internal/booking-reminders"
KEY = "test-scheduler-key-with-more-than-32-characters"


@pytest.fixture
def reminder(app, client, authenticated, booking_data, monkeypatch):
    # Crear por la API real; sólo el límite SDK se sustituye, como en la suite existente.
    booking = client.post("/api/v1/bookings", json=booking_data, headers=authenticated()).json
    start = datetime.fromisoformat(booking_data["starts_at"])
    monkeypatch.setattr("app.services.utcnow", lambda: start - timedelta(minutes=45))
    monkeypatch.setitem(app.config, "FCM_ENABLED", True)
    monkeypatch.setitem(app.config, "REMINDER_SCHEDULER_KEY", KEY)
    monkeypatch.setattr("app.notifications.get_firebase_app", lambda: object())
    sender = Mock(return_value="accepted-by-fcm")
    monkeypatch.setattr("app.notifications.messaging.send", sender)
    with app.app_context():
        user = db.session.scalar(sa.select(User))
        db.session.add(
            Device(user_id=user.id, token="real-token-replaced-in-test", token_hash="test-hash")
        )
        db.session.commit()
    return booking["id"], start, sender


def test_scheduler_requires_own_secret(app, client, authenticated, monkeypatch):
    monkeypatch.setitem(app.config, "REMINDER_SCHEDULER_KEY", "")
    assert client.post(PATH).status_code == 503
    monkeypatch.setitem(app.config, "REMINDER_SCHEDULER_KEY", KEY)
    for headers in ({}, authenticated(), {"X-Scheduler-Key": "wrong"}):
        assert client.post(PATH, headers=headers).status_code == 401
    monkeypatch.setitem(app.config, "FCM_ENABLED", False)
    assert client.post(PATH, headers={"X-Scheduler-Key": KEY}).status_code == 503


def test_reminder_is_future_once_and_skips_cancelled_or_distant(app, client, reminder):
    booking_id, start, sender = reminder
    with app.app_context():
        user = db.session.scalar(sa.select(User))
        for delta, cancelled in [(3, False), (-4, False), (0, True)]:
            db.session.add(
                Booking(
                    user_id=user.id,
                    court_id=2,
                    starts_at=start + timedelta(hours=delta),
                    ends_at=start + timedelta(hours=delta + 1),
                    cancelled_at=datetime.now(UTC) if cancelled else None,
                )
            )
        db.session.commit()
    headers = {"X-Scheduler-Key": KEY}
    assert client.post(PATH, headers=headers).json == {"checked": 1, "sent": 1, "pending": 0}
    assert client.post(PATH, headers=headers).json == {"checked": 0, "sent": 0, "pending": 0}
    assert sender.call_count == 1
    message = sender.call_args.args[0]
    assert message.data == {
        "type": "booking_reminder",
        "booking_id": str(booking_id),
        "recipient_uid": "alice",
    }
    assert message.android.ttl == timedelta(minutes=45)
    with app.app_context():
        assert db.session.get(Booking, booking_id).reminder_sent_at is not None


def test_failed_push_retries_on_next_scheduler_call(app, client, reminder):
    booking_id, _, sender = reminder
    sender.side_effect = RuntimeError("Firebase temporarily offline")
    assert client.post(PATH, headers={"X-Scheduler-Key": KEY}).json["pending"] == 1
    with app.app_context():
        assert db.session.get(Booking, booking_id).reminder_sent_at is None
    sender.side_effect = None
    assert client.post(PATH, headers={"X-Scheduler-Key": KEY}).json["sent"] == 1
    assert sender.call_count == 2


def test_concurrent_scheduler_calls_do_not_duplicate(app, reminder):
    _, _, sender = reminder
    entered, release = Event(), Event()

    def send(*args, **kwargs):
        entered.set()
        assert release.wait(10)
        return "accepted"

    sender.side_effect = send

    def call():
        with app.test_client() as client:
            result = client.post(PATH, headers={"X-Scheduler-Key": KEY})
            assert result.status_code == 200
            return result.json

    with ThreadPoolExecutor(max_workers=2) as pool:
        first = pool.submit(call)
        try:
            assert entered.wait(10)
            assert pool.submit(call).result(timeout=10)["checked"] == 0
        finally:
            release.set()
        assert first.result(timeout=10)["sent"] == 1
    assert sender.call_count == 1


def test_academic_court_name_uses_real_venue_address_type_and_number(client):
    court = client.get("/api/v1/courts/1").json
    assert court["name"] == "Sede_Test_Calle_Test_Futbol_1"
    assert client.get("/api/v1/venues/1/courts").json["items"][0]["name"] == court["name"]
