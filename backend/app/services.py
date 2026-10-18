from datetime import UTC, datetime, time, timedelta
from zoneinfo import ZoneInfo

import sqlalchemy as sa
from sqlalchemy.exc import IntegrityError

from .errors import ApiError
from .extensions import db
from .models import Booking, Court, OpeningHour, Venue


def utcnow():
    return datetime.now(UTC)


def get_or_404(model, item_id):
    item = db.session.get(model, item_id)
    if item is None:
        raise ApiError(404, "not_found", "El recurso solicitado no existe.")
    return item


def opening_window(venue, day):
    schedule = db.session.scalar(
        sa.select(OpeningHour).where(
            OpeningHour.venue_id == venue.id, OpeningHour.weekday == day.weekday()
        )
    )
    if not schedule:
        return None
    midnight = datetime.combine(day, time(), tzinfo=ZoneInfo(venue.timezone))
    return midnight + timedelta(hours=schedule.open_hour), midnight + timedelta(
        hours=schedule.close_hour
    )


def create_booking(user_id, data):
    court = get_or_404(Court, data["court_id"])
    if not court.active:
        raise ApiError(409, "court_unavailable", "La cancha está inactiva.")
    venue = get_or_404(Venue, court.venue_id)
    start = data["starts_at"]
    if start.tzinfo is None or start.utcoffset() is None:
        raise ApiError(422, "invalid_datetime", "starts_at debe incluir zona horaria u offset.")
    if not 1900 <= start.year < 9999:
        raise ApiError(422, "invalid_datetime", "El año debe estar entre 1900 y 9998.")
    start = start.astimezone(UTC)
    local_start = start.astimezone(ZoneInfo(venue.timezone))
    if local_start.minute or local_start.second or local_start.microsecond:
        raise ApiError(422, "invalid_hour", "La reserva debe comenzar en una hora entera local.")
    if start <= utcnow():
        raise ApiError(422, "past_booking", "La reserva debe comenzar en el futuro.")
    end = start + timedelta(hours=data["duration_hours"])
    window = opening_window(venue, local_start.date())
    if not window or start < window[0].astimezone(UTC) or end > window[1].astimezone(UTC):
        raise ApiError(
            422, "outside_opening_hours", "La reserva debe estar dentro del horario de apertura."
        )
    booking = Booking(user_id=user_id, court_id=court.id, starts_at=start, ends_at=end)
    db.session.add(booking)
    try:
        # La exclusión GiST también espera transacciones concurrentes y rechaza el solapamiento.
        db.session.commit()
    except IntegrityError as exc:
        db.session.rollback()
        if (
            getattr(getattr(exc.orig, "diag", None), "constraint_name", None)
            == "bookings_no_overlap"
        ):
            raise ApiError(
                409, "booking_conflict", "La cancha ya está reservada en ese horario."
            ) from exc
        raise
    from .notifications import notify_booking

    notify_booking(booking, "booking_created")
    return booking


def availability(court_id, day):
    court = get_or_404(Court, court_id)
    venue = get_or_404(Venue, court.venue_id)
    now = utcnow()
    if day < now.astimezone(ZoneInfo(venue.timezone)).date():
        raise ApiError(422, "past_date", "La fecha no puede estar en el pasado.")
    result = {"court_id": court_id, "date": day, "timezone": venue.timezone, "slots": []}
    window = opening_window(venue, day)
    if not window or not court.active:
        return result
    start, close = (dt.astimezone(UTC) for dt in window)
    occupied = db.session.scalars(
        sa.select(Booking).where(
            Booking.court_id == court_id,
            Booking.cancelled_at.is_(None),
            Booking.starts_at < close,
            Booking.ends_at > start,
        )
    ).all()
    while start + timedelta(hours=1) <= close:
        end = start + timedelta(hours=1)
        # Horas inexistentes/duplicadas por DST se evalúan como instantes UTC reales.
        local = start.astimezone(ZoneInfo(venue.timezone))
        if not (local.minute or local.second or local.microsecond):
            result["slots"].append(
                {
                    "starts_at": start,
                    "ends_at": end,
                    "available": start > now
                    and not any(
                        booking.starts_at < end and booking.ends_at > start for booking in occupied
                    ),
                }
            )
        start = end
    return result


def cancel_booking(user_id, booking_id):
    # Bloqueo para que cancelar dos veces en paralelo sea idempotente.
    booking = db.session.scalar(
        sa.select(Booking)
        .where(Booking.id == booking_id, Booking.user_id == user_id)
        .with_for_update()
    )
    if booking is None:
        raise ApiError(404, "not_found", "La reserva solicitada no existe.")
    changed = booking.cancelled_at is None
    if changed:
        if booking.starts_at <= utcnow():
            raise ApiError(409, "booking_started", "No se puede cancelar una reserva ya iniciada.")
        booking.cancelled_at = utcnow()
    db.session.commit()
    if changed:
        from .notifications import notify_booking

        notify_booking(booking, "booking_cancelled")
    return booking
