"""FCM compartido por avisos inmediatos y recordatorios. Sin workers ni cola adicional."""

from datetime import timedelta

import sqlalchemy as sa
from firebase_admin import messaging
from flask import current_app

from .auth import get_firebase_app
from .extensions import db
from .models import Booking, Device, User


def send_booking_notification(booking, event):
    """Devuelve si FCM aceptó al menos un envío. El llamador confirma la transacción."""
    devices = db.session.scalars(sa.select(Device).where(Device.user_id == booking.user_id)).all()
    if not devices:
        return False
    from .services import utcnow

    if event == "booking_reminder" and booking.starts_at <= utcnow():
        return False
    uid = db.session.get(User, booking.user_id).firebase_uid
    titles = {
        "booking_created": "Reserva confirmada",
        "booking_cancelled": "Reserva cancelada",
        "booking_reminder": "Tu reserva se aproxima",
    }
    try:
        firebase_app = get_firebase_app()
    except Exception as exc:
        current_app.logger.warning("FCM no disponible (%s)", type(exc).__name__)
        return False
    delivered = False
    for device in devices:
        try:
            messaging.send(
                messaging.Message(
                    token=device.token,
                    notification=messaging.Notification(
                        title=titles[event], body="Consultá el horario exacto en Mis reservas."
                    ),
                    data={"type": event, "booking_id": str(booking.id), "recipient_uid": uid},
                    android=messaging.AndroidConfig(
                        notification=messaging.AndroidNotification(channel_id="bookings"),
                        ttl=booking.starts_at - utcnow()
                        if event == "booking_reminder"
                        else timedelta(hours=1),
                    ),
                ),
                app=firebase_app,
            )
            delivered = True
        except messaging.UnregisteredError:
            db.session.delete(device)
        except Exception as exc:
            current_app.logger.warning("FCM no disponible (%s)", type(exc).__name__)
    return delivered


def notify_booking(booking, event):
    """Después del commit: una falla del aviso no revierte la reserva."""
    if not current_app.config.get("FCM_ENABLED"):
        return
    try:
        send_booking_notification(booking, event)
        db.session.commit()
    except Exception as exc:
        db.session.rollback()
        current_app.logger.warning("Notificación omitida (%s)", type(exc).__name__)


def send_upcoming_reminders():
    from .services import utcnow

    now = utcnow()
    # El lock permanece hasta registrar reminder_sent_at. Dos invocaciones no
    # envían simultáneamente la misma reserva; las canceladas/pasadas se excluyen.
    bookings = db.session.scalars(
        sa.select(Booking)
        .where(
            Booking.cancelled_at.is_(None),
            Booking.reminder_sent_at.is_(None),
            Booking.starts_at > now,
            Booking.starts_at <= now + timedelta(hours=1),
        )
        .order_by(Booking.starts_at, Booking.id)
        .with_for_update(skip_locked=True)
    ).all()
    sent = 0
    for booking in bookings:
        if send_booking_notification(booking, "booking_reminder"):
            booking.reminder_sent_at = now
            sent += 1
    db.session.commit()
    return {"checked": len(bookings), "sent": sent, "pending": len(bookings) - sent}
