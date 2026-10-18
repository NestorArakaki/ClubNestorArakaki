import json
from datetime import UTC, datetime, timedelta

import sqlalchemy as sa
from openapi_spec_validator import validate

from app.extensions import db
from app.models import Court, OpeningHour, Venue


def test_catalog_and_pagination(client):
    assert client.get("/api/v1/health").json == {"status": "ok"}
    assert client.get("/api/v1/venues").json["total"] == 1
    assert client.get("/api/v1/venues/1").json["timezone"] == "America/Argentina/Buenos_Aires"
    courts = client.get("/api/v1/venues/1/courts?per_page=1&page=2").json
    assert courts["total"] == 2
    assert courts["items"][0]["id"] == 2
    assert client.get("/api/v1/venues/1/courts?page=50").json["items"] == []
    assert client.get("/api/v1/courts/1").json["sport"] == "football"
    assert len(client.get("/api/v1/venues/1/opening-hours").json) == 7
    for path in (
        "/venues/999",
        "/venues/999/courts",
        "/venues/999/opening-hours",
        "/courts/999",
        "/courts/999/availability?date=2030-01-01",
    ):
        assert client.get(f"/api/v1{path}").status_code == 404
    for query in ("page=0", "page=x", "per_page=101", "per_page=-1"):
        assert client.get(f"/api/v1/venues?{query}").status_code == 422


def test_availability_rules(app, client, booking_data):
    day = datetime.fromisoformat(booking_data["starts_at"]).date()
    response = client.get(f"/api/v1/courts/1/availability?date={day}")
    assert response.status_code == 200
    assert len(response.json["slots"]) == 16
    assert all(slot["available"] for slot in response.json["slots"])
    assert all(
        set(slot) == {"starts_at", "ends_at", "available"} for slot in response.json["slots"]
    )
    for query in (
        "",
        "date=2000-01-01",
        "date=no",
        "date=2026-02-30",
        "date=20300101",
        "date=9999-12-31",
    ):
        assert client.get(f"/api/v1/courts/1/availability?{query}").status_code == 422
    with app.app_context():
        db.session.get(Court, 1).active = False
        db.session.commit()
    assert client.get(f"/api/v1/courts/1/availability?date={day}").json["slots"] == []
    assert len(client.get("/api/v1/venues/1/courts").json["items"]) == 1
    with app.app_context():
        db.session.get(Court, 1).active = True
        db.session.execute(sa.delete(OpeningHour))
        db.session.commit()
    assert client.get(f"/api/v1/courts/1/availability?date={day}").json["slots"] == []


def test_today_past_slots_unavailable(client, monkeypatch):
    # 15:30 UTC = 12:30 local.
    fixed = datetime.now(UTC).replace(hour=15, minute=30)
    monkeypatch.setattr("app.services.utcnow", lambda: fixed)
    response = client.get(f"/api/v1/courts/1/availability?date={fixed.date()}")
    for slot in response.json["slots"]:
        assert slot["available"] == (datetime.fromisoformat(slot["starts_at"]) > fixed)


def test_local_date_differs_from_utc(client, authenticated, booking_data):
    start = datetime.fromisoformat(booking_data["starts_at"]).replace(hour=1)
    result = client.post(
        "/api/v1/bookings",
        headers=authenticated(),
        json={
            **booking_data,
            "starts_at": start.isoformat(),
            "duration_hours": 1,
        },
    )
    assert result.status_code == 201
    local_day = (start - timedelta(hours=3)).date()
    slots = client.get(f"/api/v1/courts/1/availability?date={local_day}").json["slots"]
    assert sum(not slot["available"] for slot in slots) == 1


def test_swagger_and_openapi(client):
    response = client.get("/openapi.json")
    assert response.status_code == 200
    spec = response.json
    validate(spec)
    assert spec["components"]["securitySchemes"]["FirebaseAuth"]["scheme"] == "bearer"
    assert spec["paths"]["/api/v1/bookings"]["post"]["security"] == [{"FirebaseAuth": []}]
    assert "security" not in spec["paths"]["/api/v1/venues"]["get"]
    error = spec["components"]["schemas"]["Error"]
    assert "error" in error["properties"]
    assert client.get("/docs").status_code == 200
    assert client.get("/swagger-assets/swagger-ui-bundle.js").status_code == 200
    assert client.get("/swagger-assets/swagger-ui.css").status_code == 200


def test_malformed_and_large_json(client, authenticated):
    for data in ("{broken", "[]", "null"):
        response = client.post(
            "/api/v1/bookings", data=data, content_type="application/json", headers=authenticated()
        )
        assert response.status_code in (400, 422)
        assert "error" in response.json
    response = client.post(
        "/api/v1/bookings",
        data="x" * 17000,
        content_type="application/json",
        headers=authenticated(),
    )
    assert response.status_code == 413
    assert client.get("/does-not-exist").json["error"]["code"] == "not_found"


def test_seed_idempotent(app):
    runner = app.test_cli_runner()
    for _ in range(2):
        result = runner.invoke(args=["seed"])
        assert result.exit_code == 0, result.output
    with app.app_context():
        assert db.session.scalar(sa.select(sa.func.count()).select_from(Venue)) == 3
        assert db.session.scalar(sa.select(sa.func.count()).select_from(Court)) == 7


def test_seed_rolls_back_invalid_file(app, tmp_path):
    seed_file = tmp_path / "invalid-seed.json"
    seed_file.write_text(
        json.dumps(
            [
                {
                    "name": "Should roll back",
                    "address": "Test",
                    "timezone": "UTC",
                    "opening_hours": [{"weekday": 0, "open_hour": 23, "close_hour": 8}],
                    "courts": [],
                }
            ]
        )
    )
    result = app.test_cli_runner().invoke(args=["seed", "--file", str(seed_file)])
    assert result.exit_code != 0
    with app.app_context():
        assert db.session.scalar(sa.select(sa.func.count()).select_from(Venue)) == 1
