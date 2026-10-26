from concurrent.futures import ThreadPoolExecutor
from threading import Barrier

import pytest
import sqlalchemy as sa
from sqlalchemy import event
from sqlalchemy.orm import Session

from app.extensions import db
from app.models import Booking


@pytest.mark.parametrize("users", [("alice", "bob"), ("alice", "alice")])
def test_simultaneous_overlapping_requests(app, authenticated, booking_data, users):
    barrier = Barrier(2)

    def synchronize_inserts(session, *_):
        if any(isinstance(item, Booking) for item in session.new):
            barrier.wait(timeout=10)

    def reserve(user):
        with app.test_client() as client:
            result = client.post("/api/v1/bookings", json=booking_data, headers=authenticated(user))
            return result.status_code, result.json

    # Las dos transacciones llegan al INSERT antes de que ninguna pueda confirmar.
    event.listen(Session, "before_flush", synchronize_inserts)
    try:
        with ThreadPoolExecutor(max_workers=2) as pool:
            futures = [pool.submit(reserve, user) for user in users]
            results = [future.result(timeout=20) for future in futures]
    finally:
        event.remove(Session, "before_flush", synchronize_inserts)
    assert sorted(code for code, _ in results) == [201, 409], results
    assert (
        next(body for code, body in results if code == 409)["error"]["code"] == "booking_conflict"
    )
    with app.app_context():
        assert db.session.scalar(sa.select(sa.func.count()).select_from(Booking)) == 1


def test_concurrent_cancellation_is_idempotent(app, client, authenticated, booking_data):
    booking_id = client.post("/api/v1/bookings", json=booking_data, headers=authenticated()).json[
        "id"
    ]
    barrier = Barrier(2)

    def cancel():
        with app.test_client() as worker:
            barrier.wait(timeout=10)
            response = worker.delete(f"/api/v1/bookings/{booking_id}", headers=authenticated())
            return response.status_code, response.json

    with ThreadPoolExecutor(max_workers=2) as pool:
        futures = [pool.submit(cancel) for _ in range(2)]
        results = [future.result(timeout=20) for future in futures]
    assert all(code == 200 and body["status"] == "cancelled" for code, body in results), results
    assert results[0][1]["cancelled_at"] == results[1][1]["cancelled_at"]
    assert (
        client.post("/api/v1/bookings", json=booking_data, headers=authenticated("bob")).status_code
        == 201
    )
