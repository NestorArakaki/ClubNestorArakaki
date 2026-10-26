import os
from datetime import UTC, datetime, timedelta

import pytest
import sqlalchemy as sa
from flask_migrate import upgrade
from sqlalchemy.engine import make_url

from app import create_app
from app.errors import ApiError
from app.extensions import db
from app.models import Court, OpeningHour, Venue


@pytest.fixture(scope="session")
def app():
    url = os.getenv("TEST_DATABASE_URL")
    if not url:
        raise pytest.UsageError("Configurá TEST_DATABASE_URL con una base PostgreSQL descartable.")
    parsed = make_url(url)
    # Estas pruebas limpian datos: nunca aceptar una base cuyo nombre no sea explícitamente test.
    if parsed.get_backend_name() != "postgresql" or not parsed.database.endswith("_test"):
        raise pytest.UsageError(
            "TEST_DATABASE_URL debe usar PostgreSQL y una base terminada en _test."
        )
    application = create_app(
        {"TESTING": True, "SQLALCHEMY_DATABASE_URI": url, "FIREBASE_PROJECT_ID": "test-project"}
    )
    with application.app_context():
        upgrade()
    yield application
    with application.app_context():
        db.session.remove()
        db.engine.dispose()


@pytest.fixture(autouse=True)
def clean_database(app):
    with app.app_context():
        db.session.execute(
            sa.text(
                "TRUNCATE bookings, users, opening_hours, courts, venues RESTART IDENTITY CASCADE"
            )
        )
        db.session.commit()
        venue = Venue(
            name="Sede Test", address="Calle Test", timezone="America/Argentina/Buenos_Aires"
        )
        db.session.add(venue)
        db.session.flush()
        db.session.add_all(
            [
                OpeningHour(venue_id=venue.id, weekday=day, open_hour=8, close_hour=24)
                for day in range(7)
            ]
        )
        db.session.add_all(
            [
                Court(venue_id=venue.id, name="Fútbol", sport="football"),
                Court(venue_id=venue.id, name="Tenis", sport="tennis"),
            ]
        )
        db.session.commit()
    yield
    with app.app_context():
        db.session.remove()


@pytest.fixture
def client(app):
    return app.test_client()


@pytest.fixture
def authenticated(monkeypatch):
    # Única sustitución de identidad: acotada a pruebas, nunca configurable desde HTTP/env.
    def verify(token):
        if token not in ("alice", "bob"):
            raise ApiError(401, "invalid_token", "Token inválido.")
        return {"uid": token, "email": f"{token}@example.test"}

    monkeypatch.setattr("app.auth.verify_token", verify)
    return lambda user="alice": {"Authorization": f"Bearer {user}"}


@pytest.fixture
def booking_data():
    # 12:00 UTC = 09:00 Argentina; independiente de la fecha real de ejecución.
    start = (datetime.now(UTC) + timedelta(days=7)).replace(
        hour=12, minute=0, second=0, microsecond=0
    )
    return {"court_id": 1, "starts_at": start.isoformat(), "duration_hours": 2}
