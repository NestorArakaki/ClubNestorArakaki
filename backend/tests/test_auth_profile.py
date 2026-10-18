from unittest.mock import Mock

import pytest
from firebase_admin import auth as firebase_auth
from google.auth.exceptions import DefaultCredentialsError

from app import create_app
from app.extensions import db
from app.models import User


@pytest.mark.parametrize(
    "method,path",
    [
        ("get", "/me"),
        ("patch", "/me"),
        ("get", "/bookings"),
        ("post", "/bookings"),
        ("get", "/bookings/1"),
        ("delete", "/bookings/1"),
    ],
)
def test_private_routes_require_token(client, method, path):
    response = getattr(client, method)(f"/api/v1{path}")
    assert response.status_code == 401
    assert response.json["error"]["code"] == "authentication_required"


@pytest.mark.parametrize("header", ["", "Basic alice", "Bearer", "Bearer a b"])
def test_invalid_auth_header(client, header):
    assert client.get("/api/v1/me", headers={"Authorization": header}).status_code == 401


def test_sdk_called_with_revocation_check(client, monkeypatch):
    firebase_app = object()
    verifier = Mock(return_value={"uid": "real-sdk-uid", "email": "signed@example.test"})
    monkeypatch.setattr("app.auth.firebase_admin.get_app", lambda _: firebase_app)
    monkeypatch.setattr("app.auth.auth.verify_id_token", verifier)
    response = client.get("/api/v1/me", headers={"Authorization": "Bearer signed-id-token"})
    assert response.status_code == 200
    verifier.assert_called_once_with("signed-id-token", app=firebase_app, check_revoked=True)
    assert response.json["email"] == "signed@example.test"


@pytest.mark.parametrize(
    "exception",
    [
        firebase_auth.InvalidIdTokenError("bad signature"),
        firebase_auth.ExpiredIdTokenError("expired", cause=None),
        firebase_auth.RevokedIdTokenError("revoked"),
        firebase_auth.UserDisabledError("disabled"),
        firebase_auth.UserNotFoundError("missing"),
    ],
)
def test_rejected_tokens_do_not_create_users(app, client, monkeypatch, exception):
    monkeypatch.setattr("app.auth.firebase_admin.get_app", lambda _: object())
    monkeypatch.setattr("app.auth.auth.verify_id_token", Mock(side_effect=exception))
    response = client.get("/api/v1/me", headers={"Authorization": "Bearer invalid"})
    assert response.status_code == 401
    with app.app_context():
        assert db.session.query(User).count() == 0


@pytest.mark.parametrize(
    "exception",
    [
        DefaultCredentialsError("No credentials"),
        firebase_auth.CertificateFetchError("Unavailable", cause=None),
    ],
)
def test_firebase_outage_returns_503(client, monkeypatch, exception):
    monkeypatch.setattr("app.auth.firebase_admin.get_app", lambda _: object())
    monkeypatch.setattr("app.auth.auth.verify_id_token", Mock(side_effect=exception))
    response = client.get("/api/v1/me", headers={"Authorization": "Bearer token"})
    assert response.status_code == 503
    assert response.json["error"]["code"] == "auth_unavailable"


def test_profile_edit_and_email_read_only(client, authenticated):
    headers = authenticated()
    profile = client.get("/api/v1/me", headers=headers)
    assert profile.json["email"] == "alice@example.test"
    patch = {"first_name": " Ana ", "last_name": " Pérez ", "birth_date": "2000-02-29"}
    response = client.patch("/api/v1/me", json=patch, headers=headers)
    assert response.status_code == 200
    assert response.json["first_name"] == "Ana"
    assert response.json["last_name"] == "Pérez"
    assert response.json["birth_date"] == "2000-02-29"
    for body in (
        {"email": "other@example.test"},
        {"firebase_uid": "bob"},
        {"first_name": " "},
        {"last_name": "x" * 101},
        {"birth_date": "2999-01-01"},
        {"birth_date": "2001-02-29"},
        {"birth_date": "1899-01-01"},
        {"birth_date": "20000229"},
        {"first_name": None},
    ):
        assert client.patch("/api/v1/me", json=body, headers=headers).status_code == 422
    assert client.patch("/api/v1/me", json={"birth_date": None}, headers=headers).status_code == 200
    assert client.get("/api/v1/me", headers=authenticated("bob")).json["first_name"] is None
    assert client.get("/api/v1/me", headers=headers).json["email"] == "alice@example.test"


def test_missing_firebase_configuration(app, client, monkeypatch):
    monkeypatch.setitem(app.config, "FIREBASE_PROJECT_ID", "")
    response = client.get("/api/v1/me", headers={"Authorization": "Bearer token"})
    assert response.status_code == 503


def test_emulator_is_rejected(monkeypatch):
    monkeypatch.setenv("FIREBASE_AUTH_EMULATOR_HOST", "localhost:9099")
    with pytest.raises(RuntimeError, match="verificación real"):
        create_app()
