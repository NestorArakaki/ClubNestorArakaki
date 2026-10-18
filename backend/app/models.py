import re
import unicodedata
from datetime import date, datetime

import sqlalchemy as sa
from sqlalchemy.dialects.postgresql import ExcludeConstraint
from sqlalchemy.orm import Mapped, mapped_column

from .extensions import db


class Venue(db.Model):
    __tablename__ = "venues"
    id: Mapped[int] = mapped_column(primary_key=True)
    name: Mapped[str] = mapped_column(sa.String(120), unique=True)
    address: Mapped[str] = mapped_column(sa.String(250))
    timezone: Mapped[str] = mapped_column(sa.String(64), default="America/Argentina/Buenos_Aires")


class OpeningHour(db.Model):
    """Un intervalo por día, en hora local. weekday: lunes=0; close_hour admite 24."""

    __tablename__ = "opening_hours"
    id: Mapped[int] = mapped_column(primary_key=True)
    venue_id: Mapped[int] = mapped_column(sa.ForeignKey("venues.id"))
    weekday: Mapped[int] = mapped_column(sa.SmallInteger)
    open_hour: Mapped[int] = mapped_column(sa.SmallInteger)
    close_hour: Mapped[int] = mapped_column(sa.SmallInteger)
    __table_args__ = (
        sa.UniqueConstraint("venue_id", "weekday"),
        sa.CheckConstraint("weekday BETWEEN 0 AND 6", name="weekday_range"),
        sa.CheckConstraint(
            "open_hour >= 0 AND open_hour < close_hour AND close_hour <= 24", name="hour_range"
        ),
    )


class Court(db.Model):
    __tablename__ = "courts"
    id: Mapped[int] = mapped_column(primary_key=True)
    venue_id: Mapped[int] = mapped_column(sa.ForeignKey("venues.id"), index=True)
    name: Mapped[str] = mapped_column(sa.String(120))
    sport: Mapped[str] = mapped_column(sa.String(80))
    active: Mapped[bool] = mapped_column(default=True, server_default=sa.true())
    __table_args__ = (sa.UniqueConstraint("venue_id", "name"),)

    @property
    def full_name(self):
        # No duplicamos dirección/sede en la tabla: el nombre académico se deriva.
        venue = db.session.get(Venue, self.venue_id)
        sport = {
            "football": "Futbol",
            "tennis": "Tenis",
            "padel": "Paddle",
            "basketball": "Basquet",
            "multipurpose": "Multideporte",
        }.get(self.sport, self.sport)
        parts = [venue.name, venue.address, sport, str(self.id)]

        def clean(value):
            ascii_value = unicodedata.normalize("NFKD", value).encode("ascii", "ignore").decode()
            return re.sub(r"[^A-Za-z0-9]+", "_", ascii_value).strip("_")

        return "_".join(clean(value) for value in parts)


class User(db.Model):
    __tablename__ = "users"
    id: Mapped[int] = mapped_column(primary_key=True)
    firebase_uid: Mapped[str] = mapped_column(sa.String(128), unique=True)
    email: Mapped[str | None] = mapped_column(sa.String(320))
    first_name: Mapped[str | None] = mapped_column(sa.String(100))
    last_name: Mapped[str | None] = mapped_column(sa.String(100))
    birth_date: Mapped[date | None] = mapped_column(sa.Date)
    created_at: Mapped[datetime] = mapped_column(
        sa.DateTime(timezone=True), server_default=sa.func.now()
    )


class Booking(db.Model):
    __tablename__ = "bookings"
    id: Mapped[int] = mapped_column(primary_key=True)
    user_id: Mapped[int] = mapped_column(sa.ForeignKey("users.id"))
    court_id: Mapped[int] = mapped_column(sa.ForeignKey("courts.id"))
    starts_at: Mapped[datetime] = mapped_column(sa.DateTime(timezone=True))
    ends_at: Mapped[datetime] = mapped_column(sa.DateTime(timezone=True))
    reminder_sent_at: Mapped[datetime | None] = mapped_column(sa.DateTime(timezone=True))
    cancelled_at: Mapped[datetime | None] = mapped_column(sa.DateTime(timezone=True))
    created_at: Mapped[datetime] = mapped_column(
        sa.DateTime(timezone=True), server_default=sa.func.now()
    )
    __table_args__ = (
        sa.CheckConstraint("ends_at > starts_at", name="positive_duration"),
        sa.CheckConstraint(
            "EXTRACT(EPOCH FROM (ends_at - starts_at)) BETWEEN 3600 AND 86400 "
            "AND MOD(EXTRACT(EPOCH FROM (ends_at - starts_at)), 3600) = 0",
            name="whole_hours",
        ),
        ExcludeConstraint(
            ("court_id", "="),
            (sa.func.tstzrange(starts_at, ends_at, "[)"), "&&"),
            where=sa.text("cancelled_at IS NULL"),
            using="gist",
            name="bookings_no_overlap",
        ),
        sa.Index("ix_bookings_user_starts", "user_id", "starts_at"),
    )

    @property
    def status(self):
        return "cancelled" if self.cancelled_at else "confirmed"


class Device(db.Model):
    __tablename__ = "devices"
    id: Mapped[int] = mapped_column(primary_key=True)
    user_id: Mapped[int] = mapped_column(sa.ForeignKey("users.id"), index=True)
    token: Mapped[str] = mapped_column(sa.String(4096))
    token_hash: Mapped[str] = mapped_column(sa.String(64), unique=True)
    updated_at: Mapped[datetime] = mapped_column(
        sa.DateTime(timezone=True), server_default=sa.func.now()
    )
