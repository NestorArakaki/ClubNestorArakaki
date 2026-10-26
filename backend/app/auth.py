from functools import wraps
from threading import Lock

import firebase_admin
from firebase_admin import auth, credentials, exceptions
from flask import current_app, g, request
from google.auth.exceptions import GoogleAuthError
from sqlalchemy.dialects.postgresql import insert

from .errors import ApiError
from .extensions import db
from .models import User

_firebase_lock = Lock()


def verify_token(token):
    """Siempre verifica firma, proyecto, expiración, revocación y usuario deshabilitado."""
    project_id = current_app.config["FIREBASE_PROJECT_ID"]
    if not project_id:
        raise ApiError(503, "auth_unavailable", "Firebase no está configurado.")
    try:
        with _firebase_lock:
            try:
                firebase_app = firebase_admin.get_app(project_id)
            except ValueError:
                firebase_app = firebase_admin.initialize_app(
                    credentials.ApplicationDefault(), {"projectId": project_id}, name=project_id
                )
        return auth.verify_id_token(token, app=firebase_app, check_revoked=True)
    except auth.CertificateFetchError as exc:
        raise ApiError(503, "auth_unavailable", "No se pudo consultar Firebase.") from exc
    except (
        auth.InvalidIdTokenError,
        auth.RevokedIdTokenError,
        auth.UserDisabledError,
        auth.UserNotFoundError,
    ) as exc:
        raise ApiError(401, "invalid_token", "Token inválido, expirado o revocado.") from exc
    except (GoogleAuthError, exceptions.FirebaseError, OSError, ValueError) as exc:
        current_app.logger.error("Firebase no disponible (%s)", type(exc).__name__)
        raise ApiError(503, "auth_unavailable", "No se pudo verificar la identidad.") from exc


def login_required(fn):
    @wraps(fn)
    def wrapped(*args, **kwargs):
        parts = request.headers.get("Authorization", "").split()
        if len(parts) != 2 or parts[0].lower() != "bearer":
            raise ApiError(
                401, "authentication_required", "Enviá Authorization: Bearer <ID_TOKEN>."
            )
        claims = verify_token(parts[1])
        # El email siempre proviene del token firmado, nunca del cuerpo de la solicitud.
        stmt = insert(User).values(firebase_uid=claims["uid"], email=claims.get("email"))
        stmt = stmt.on_conflict_do_update(
            index_elements=[User.firebase_uid], set_={"email": stmt.excluded.email}
        ).returning(User)
        g.user = db.session.execute(stmt.execution_options(populate_existing=True)).scalar_one()
        # Transacción breve: no mantener bloqueado el usuario durante la reserva.
        db.session.commit()
        return fn(*args, **kwargs)

    return wrapped
