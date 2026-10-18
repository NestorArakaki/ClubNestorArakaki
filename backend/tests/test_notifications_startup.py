import os
import shutil
import subprocess
from pathlib import Path
from unittest.mock import Mock

import pytest
from firebase_admin import messaging

from app.auth import get_firebase_app
from app.extensions import db
from app.models import Device

TOKEN = "device-registration-token-for-tests-only"


def register(client, headers, token=TOKEN):
    return client.post("/api/v1/devices", json={"token": token}, headers=headers)


def test_device_requires_auth_and_validates(client, authenticated):
    assert register(client, {}).status_code == 401
    for data in (
        {},
        {"token": ""},
        {"token": "x" * 4097},
        {"token": "x " * 30},
        {"token": TOKEN, "user_id": 1},
    ):
        assert client.post("/api/v1/devices", json=data, headers=authenticated()).status_code == 422


def test_device_idempotence_transfer_and_owned_delete(app, client, authenticated):
    assert register(client, authenticated()).json == {"registered": True}
    assert register(client, authenticated()).status_code == 200
    # Un dispositivo compartido se reasocia al nuevo usuario al iniciar sesión.
    assert register(client, authenticated("bob")).status_code == 200
    assert client.delete(
        "/api/v1/devices", json={"token": TOKEN}, headers=authenticated()
    ).json == {"registered": False}
    with app.app_context():
        assert db.session.query(Device).count() == 1
    assert (
        client.delete(
            "/api/v1/devices", json={"token": TOKEN}, headers=authenticated("bob")
        ).status_code
        == 200
    )
    with app.app_context():
        assert db.session.query(Device).count() == 0


def test_long_token_does_not_exceed_postgres_index(client, authenticated):
    assert register(client, authenticated(), "x" * 4096).status_code == 200


def test_push_create_cancel_and_idempotence(app, client, authenticated, booking_data, monkeypatch):
    monkeypatch.setitem(app.config, "FCM_ENABLED", True)
    monkeypatch.setattr("app.notifications.get_firebase_app", lambda: object())
    sender = Mock(return_value="message-id")
    monkeypatch.setattr("app.notifications.messaging.send", sender)
    register(client, authenticated())
    register(client, authenticated("bob"), TOKEN + "-bob")
    response = client.post("/api/v1/bookings", json=booking_data, headers=authenticated())
    assert response.status_code == 201
    assert sender.call_count == 1
    message = sender.call_args.args[0]
    assert message.token == TOKEN
    assert message.data == {
        "type": "booking_created",
        "booking_id": str(response.json["id"]),
        "recipient_uid": "alice",
    }
    assert "alice" not in message.notification.body
    path = f"/api/v1/bookings/{response.json['id']}"
    assert client.delete(path, headers=authenticated()).status_code == 200
    assert sender.call_count == 2
    assert sender.call_args.args[0].data["type"] == "booking_cancelled"
    assert client.delete(path, headers=authenticated()).status_code == 200
    assert sender.call_count == 2


@pytest.mark.parametrize("failure", [RuntimeError("offline"), messaging.UnregisteredError("gone")])
def test_push_failure_does_not_fail_booking(
    app, client, authenticated, booking_data, monkeypatch, failure
):
    monkeypatch.setitem(app.config, "FCM_ENABLED", True)
    monkeypatch.setattr("app.notifications.get_firebase_app", lambda: object())
    monkeypatch.setattr("app.notifications.messaging.send", Mock(side_effect=failure))
    register(client, authenticated())
    response = client.post("/api/v1/bookings", json=booking_data, headers=authenticated())
    assert response.status_code == 201
    assert (
        client.get(f"/api/v1/bookings/{response.json['id']}", headers=authenticated()).json[
            "status"
        ]
        == "confirmed"
    )
    if isinstance(failure, messaging.UnregisteredError):
        with app.app_context():
            assert db.session.query(Device).count() == 0


def test_json_credentials_are_used_without_file(app, monkeypatch):
    monkeypatch.setitem(
        app.config, "FIREBASE_SERVICE_ACCOUNT_JSON", '{"project_id":"test-project"}'
    )
    monkeypatch.setattr("app.auth.firebase_admin.get_app", Mock(side_effect=ValueError()))
    certificate = Mock(return_value=object())
    initialize = Mock(return_value=object())
    monkeypatch.setattr("app.auth.credentials.Certificate", certificate)
    monkeypatch.setattr("app.auth.firebase_admin.initialize_app", initialize)
    with app.app_context():
        get_firebase_app()
    certificate.assert_called_once_with({"project_id": "test-project"})
    assert initialize.call_args.kwargs["name"] == "test-project"


@pytest.mark.parametrize(
    "migration_exit,seed_exit,seed,expected",
    [
        (0, 0, "false", ["flask --app wsgi db upgrade", "gunicorn"]),
        (1, 0, "false", ["flask --app wsgi db upgrade"]),
        (
            0,
            0,
            "true",
            [
                "flask --app wsgi db upgrade",
                "flask --app wsgi seed --file seed_data.json",
                "gunicorn",
            ],
        ),
        (
            0,
            1,
            "true",
            ["flask --app wsgi db upgrade", "flask --app wsgi seed --file seed_data.json"],
        ),
    ],
)
@pytest.mark.skipif(shutil.which("sh") is None, reason="Requiere sh (Render/Linux o Git Bash/WSL)")
def test_startup_gates_gunicorn(tmp_path, migration_exit, seed_exit, seed, expected):
    log = tmp_path / "commands"
    flask = tmp_path / "flask"
    flask.write_text(
        '#!/bin/sh\necho "flask $*" >> "$STARTUP_TEST_LOG"\n'
        'if [ "$3" = "db" ]; then exit "$MIGRATION_EXIT"; fi\nexit "$SEED_EXIT"\n'
    )
    gunicorn = tmp_path / "gunicorn"
    gunicorn.write_text('#!/bin/sh\necho gunicorn >> "$STARTUP_TEST_LOG"\n')
    flask.chmod(0o755)
    gunicorn.chmod(0o755)
    script = Path(__file__).resolve().parents[1] / "scripts/start.sh"
    result = subprocess.run(
        ["sh", str(script)],
        env={
            **os.environ,
            "PATH": f"{tmp_path}:{os.environ['PATH']}",
            "STARTUP_TEST_LOG": str(log),
            "MIGRATION_EXIT": str(migration_exit),
            "SEED_EXIT": str(seed_exit),
            "SEED_ON_START": seed,
        },
        capture_output=True,
    )
    assert log.read_text().splitlines() == expected
    assert (result.returncode == 0) == (migration_exit == 0 and (seed == "false" or seed_exit == 0))
