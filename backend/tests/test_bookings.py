from datetime import UTC, datetime, timedelta

import pytest
import sqlalchemy as sa
from sqlalchemy.exc import IntegrityError

from app.extensions import db
from app.models import Booking, Court, OpeningHour, User

API = "/api/v1"


def post(client, data, headers):
    return client.post(f"{API}/bookings", json=data, headers=headers)


@pytest.mark.parametrize("offset,duration", [(0, 2), (1, 2), (-1, 2), (-1, 4), (0, 1)])
def test_overlap_rejected(client, authenticated, booking_data, offset, duration):
    assert post(client, booking_data, authenticated()).status_code == 201
    start = datetime.fromisoformat(booking_data["starts_at"]) + timedelta(hours=offset)
    response = post(
        client,
        {**booking_data, "starts_at": start.isoformat(), "duration_hours": duration},
        authenticated("bob"),
    )
    assert response.status_code == 409
    assert response.json["error"]["code"] == "booking_conflict"


def test_adjacent_and_different_courts_allowed(client, authenticated, booking_data):
    assert post(client, booking_data, authenticated()).status_code == 201
    assert post(client, {**booking_data, "court_id": 2}, authenticated("bob")).status_code == 201
    start = datetime.fromisoformat(booking_data["starts_at"])
    for hour in (-1, 2):
        assert (
            post(
                client,
                {
                    **booking_data,
                    "starts_at": (start + timedelta(hours=hour)).isoformat(),
                    "duration_hours": 1,
                },
                authenticated("bob"),
            ).status_code
            == 201
        )


@pytest.mark.parametrize("duration", [0, -1, 25, 1.5, True, "2", None])
def test_duration_validation(client, authenticated, booking_data, duration):
    response = post(client, {**booking_data, "duration_hours": duration}, authenticated())
    assert response.status_code == 422
    assert response.json["error"]["details"]["json"]["duration_hours"]


@pytest.mark.parametrize(
    "replacement",
    [
        {"starts_at": "2000-01-01T12:00:00Z"},
        {"starts_at": "2030-02-10T12:30:00-03:00"},
        {"starts_at": "2030-02-10T12:00:01-03:00"},
        {"starts_at": "2030-02-10T12:00:00.001-03:00"},
        {"starts_at": "2030-02-10T12:00:00"},
        {"starts_at": "invalid"},
        {"starts_at": "9999-12-31T23:00:00-03:00"},
        {"starts_at": "0001-01-01T00:00:00+03:00"},
        {"starts_at": "2030-02-10T07:00:00-03:00"},
        {"starts_at": "2030-02-10T23:00:00-03:00"},
        {"court_id": True},
        {"court_id": 1.2},
        {"court_id": 0},
        {"user_id": 2},
        {"status": "cancelled"},
    ],
)
def test_invalid_requests(client, authenticated, booking_data, replacement):
    assert post(client, {**booking_data, **replacement}, authenticated()).status_code == 422


def test_missing_inactive_and_closed_court(app, client, authenticated, booking_data):
    assert post(client, {**booking_data, "court_id": 999}, authenticated()).status_code == 404
    with app.app_context():
        db.session.get(Court, 1).active = False
        db.session.commit()
    assert post(client, booking_data, authenticated()).status_code == 409
    with app.app_context():
        db.session.get(Court, 1).active = True
        db.session.execute(sa.delete(OpeningHour))
        db.session.commit()
    assert post(client, booking_data, authenticated()).status_code == 422


def test_can_end_exactly_at_midnight(client, authenticated, booking_data):
    start = datetime.fromisoformat(booking_data["starts_at"]).replace(hour=1) + timedelta(days=1)
    # 01:00 UTC equivale a 22:00 del día anterior en Argentina.
    assert (
        post(client, {**booking_data, "starts_at": start.isoformat()}, authenticated()).status_code
        == 201
    )


def test_cancellation_releases_slot_and_is_idempotent(client, authenticated, booking_data):
    booking = post(client, booking_data, authenticated()).json
    day = (datetime.fromisoformat(booking_data["starts_at"]) - timedelta(hours=3)).date()
    url = f"{API}/courts/1/availability?date={day}"
    before = client.get(url).json
    assert sum(not slot["available"] for slot in before["slots"]) == 2
    for _ in range(2):
        result = client.delete(f"{API}/bookings/{booking['id']}", headers=authenticated())
        assert result.status_code == 200
        assert result.json["status"] == "cancelled"
    assert all(slot["available"] for slot in client.get(url).json["slots"])
    assert post(client, booking_data, authenticated("bob")).status_code == 201
    cancelled = client.get(f"{API}/bookings?status=cancelled", headers=authenticated()).json
    assert cancelled["items"][0]["id"] == booking["id"]


def test_user_isolation(client, authenticated, booking_data):
    booking = post(client, booking_data, authenticated()).json
    other = authenticated("bob")
    assert client.get(f"{API}/bookings/{booking['id']}", headers=other).status_code == 404
    assert client.delete(f"{API}/bookings/{booking['id']}", headers=other).status_code == 404
    assert client.get(f"{API}/bookings?period=all", headers=other).json["total"] == 0
    assert post(client, booking_data, other).status_code == 409


def test_past_future_and_started_cancellation(app, client, authenticated, booking_data):
    booking = post(client, booking_data, authenticated()).json
    with app.app_context():
        user = db.session.scalar(sa.select(User).where(User.firebase_uid == "alice"))
        now = datetime.now(UTC)
        past = Booking(
            user_id=user.id,
            court_id=1,
            starts_at=now - timedelta(days=2),
            ends_at=now - timedelta(days=2) + timedelta(hours=1),
        )
        started = Booking(
            user_id=user.id,
            court_id=1,
            starts_at=now - timedelta(minutes=30),
            ends_at=now + timedelta(minutes=30),
        )
        db.session.add_all([past, started])
        db.session.commit()
        past_id, started_id = past.id, started.id
    future = client.get(f"{API}/bookings", headers=authenticated()).json
    assert {item["id"] for item in future["items"]} == {booking["id"], started_id}
    past = client.get(f"{API}/bookings?period=past", headers=authenticated()).json
    assert [item["id"] for item in past["items"]] == [past_id]
    for item_id in (past_id, started_id):
        result = client.delete(f"{API}/bookings/{item_id}", headers=authenticated())
        assert result.status_code == 409
        assert result.json["error"]["code"] == "booking_started"


def test_database_rejects_overlap_without_api(app, client, authenticated, booking_data):
    post(client, booking_data, authenticated())
    with app.app_context():
        booking = db.session.scalar(sa.select(Booking))
        db.session.add(
            Booking(
                user_id=booking.user_id,
                court_id=booking.court_id,
                starts_at=booking.starts_at,
                ends_at=booking.ends_at,
            )
        )
        with pytest.raises(IntegrityError) as error:
            db.session.commit()
        assert error.value.orig.diag.constraint_name == "bookings_no_overlap"
        db.session.rollback()


@pytest.mark.parametrize("duration", [timedelta(minutes=30), timedelta(0), timedelta(hours=25)])
def test_database_rejects_invalid_duration(app, client, authenticated, booking_data, duration):
    client.get(f"{API}/me", headers=authenticated())
    with app.app_context():
        user = db.session.scalar(sa.select(User))
        start = datetime.fromisoformat(booking_data["starts_at"])
        db.session.add(
            Booking(user_id=user.id, court_id=1, starts_at=start, ends_at=start + duration)
        )
        with pytest.raises(IntegrityError):
            db.session.commit()
        db.session.rollback()
