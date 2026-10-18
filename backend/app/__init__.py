import os
from pathlib import Path

from dotenv import load_dotenv
from flask import Flask
from flask_cors import CORS
from flask_smorest import Api
from sqlalchemy.engine import make_url
from swagger_ui_bundle import swagger_ui_path

from .errors import register_errors
from .extensions import db, migrate
from .schemas import ErrorSchema


class ClubApi(Api):
    ERROR_SCHEMA = ErrorSchema


def create_app(test_config=None):
    load_dotenv(Path(__file__).resolve().parent.parent / ".env", override=False)
    if os.getenv("FIREBASE_AUTH_EMULATOR_HOST"):
        raise RuntimeError(
            "El backend requiere verificación real: desactivá FIREBASE_AUTH_EMULATOR_HOST."
        )
    app = Flask(__name__, static_folder=swagger_ui_path, static_url_path="/swagger-assets")
    database_url = os.getenv("DATABASE_URL", "")
    if database_url.startswith("postgres://"):
        database_url = database_url.replace("postgres://", "postgresql+psycopg://", 1)
    elif database_url.startswith("postgresql://"):
        database_url = database_url.replace("postgresql://", "postgresql+psycopg://", 1)
    app.config.from_mapping(
        SQLALCHEMY_DATABASE_URI=database_url,
        SQLALCHEMY_TRACK_MODIFICATIONS=False,
        SQLALCHEMY_ENGINE_OPTIONS={"pool_pre_ping": True, "pool_size": 5, "max_overflow": 5},
        FIREBASE_PROJECT_ID=os.getenv("FIREBASE_PROJECT_ID", ""),
        FIREBASE_SERVICE_ACCOUNT_JSON=os.getenv("FIREBASE_SERVICE_ACCOUNT_JSON", ""),
        FCM_ENABLED=os.getenv("FCM_ENABLED", "false").lower() == "true",
        API_TITLE="ClubNestorArakaki API",
        API_VERSION="1.0.0",
        OPENAPI_VERSION="3.0.3",
        OPENAPI_URL_PREFIX="/",
        OPENAPI_JSON_PATH="openapi.json",
        OPENAPI_SWAGGER_UI_PATH="/docs",
        OPENAPI_SWAGGER_UI_URL="/swagger-assets/",
        MAX_CONTENT_LENGTH=16384,
    )
    if test_config:
        app.config.update(test_config)
    if not app.config["SQLALCHEMY_DATABASE_URI"]:
        raise RuntimeError("Configurá DATABASE_URL con una base PostgreSQL.")
    if make_url(app.config["SQLALCHEMY_DATABASE_URI"]).get_backend_name() != "postgresql":
        raise RuntimeError(
            "Este backend requiere PostgreSQL; SQLite no garantiza las restricciones."
        )
    db.init_app(app)
    migrate.init_app(app, db, directory=str(Path(__file__).resolve().parent.parent / "migrations"))
    api = ClubApi(app)
    api.spec.components.security_scheme(
        "FirebaseAuth",
        {
            "type": "http",
            "scheme": "bearer",
            "bearerFormat": "Firebase ID token",
            "description": "ID token obtenido con Firebase Auth en Flutter; no custom tokens.",
        },
    )
    from .routes import blp

    api.register_blueprint(blp)
    # Registrar después de smorest para unificar errores de validación y HTTP.
    register_errors(app)
    origins = [item.strip() for item in os.getenv("CORS_ORIGINS", "").split(",") if item.strip()]
    if origins:
        CORS(
            app,
            resources={r"/api/*": {"origins": origins}},
            allow_headers=["Authorization", "Content-Type"],
            methods=["GET", "POST", "PATCH", "DELETE"],
        )
    from .seed import seed_command

    app.cli.add_command(seed_command)
    return app
