from flask import current_app, jsonify
from sqlalchemy.exc import SQLAlchemyError
from werkzeug.exceptions import HTTPException

from .extensions import db


class ApiError(Exception):
    def __init__(self, status, code, message, details=None):
        self.status = status
        self.code = code
        self.message = message
        self.details = details


def register_errors(app):
    def response(status, code, message, details=None):
        body = {"error": {"code": code, "message": message}}
        if details:
            body["error"]["details"] = details
        return jsonify(body), status

    @app.errorhandler(ApiError)
    def api_error(exc):
        db.session.rollback()
        return response(exc.status, exc.code, exc.message, exc.details)

    @app.errorhandler(HTTPException)
    def http_error(exc):
        data = getattr(exc, "data", None) or {}
        return response(
            exc.code,
            "validation_error" if exc.code in (400, 422) else exc.name.lower().replace(" ", "_"),
            data.get(
                "message",
                "La solicitud contiene datos inválidos."
                if exc.code in (400, 422)
                else exc.description,
            ),
            data.get("messages"),
        )

    @app.errorhandler(SQLAlchemyError)
    def database_error(exc):
        db.session.rollback()
        current_app.logger.error("Error de base de datos (%s)", type(exc).__name__)
        return response(503, "database_unavailable", "La base de datos no está disponible.")

    @app.errorhandler(Exception)
    def unexpected_error(exc):
        db.session.rollback()
        current_app.logger.error("Error inesperado (%s)", type(exc).__name__)
        return response(500, "internal_error", "Ocurrió un error interno.")
