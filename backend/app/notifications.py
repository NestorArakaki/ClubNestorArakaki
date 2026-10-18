"""Envío best effort posterior al commit. Una falla push jamás deshace una reserva."""

import sqlalchemy as sa
from firebase_admin import messaging
from flask import current_app

from .auth import get_firebase_app
from .extensions import db
from .models import Device, User


def notify_booking(booking, event):
    if not current_app.config.get("FCM_ENABLED"):
        return
    try:
        # Capturar datos antes del SDK; no se envían nombres, email ni detalles privados.
        devices = db.session.scalars(
            sa.select(Device).where(Device.user_id == booking.user_id)
        ).all()
        if not devices:
            return
        uid = db.session.get(User, booking.user_id).firebase_uid
        data = {"type": event, "booking_id": str(booking.id), "recipient_uid": uid}
        title = "Reserva confirmada" if event == "booking_created" else "Reserva cancelada"
        firebase_app = get_firebase_app()
        for device in devices:
            try:
                messaging.send(
                    messaging.Message(
                        token=device.token,
                        notification=messaging.Notification(
                            title=title, body="Consultá Mis reservas en el club."
                        ),
                        data=data,
                        android=messaging.AndroidConfig(
                            notification=messaging.AndroidNotification(channel_id="bookings")
                        ),
                    ),
                    app=firebase_app,
                )
            except messaging.UnregisteredError:
                db.session.delete(device)
            except Exception as exc:
                current_app.logger.warning("FCM no disponible (%s)", type(exc).__name__)
        db.session.commit()
    except Exception as exc:
        db.session.rollback()
        current_app.logger.warning("Notificación omitida (%s)", type(exc).__name__)
