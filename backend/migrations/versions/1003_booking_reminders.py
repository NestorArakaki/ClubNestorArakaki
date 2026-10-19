"""Marca persistente para recordatorios de reservas próximas.

Revision ID: 1003_booking_reminders
Revises: 1002_devices
"""

import sqlalchemy as sa
from alembic import op

revision = "1003_booking_reminders"
down_revision = "1002_devices"
branch_labels = None
depends_on = None


def upgrade():
    op.add_column("bookings", sa.Column("reminder_sent_at", sa.DateTime(timezone=True)))


def downgrade():
    op.drop_column("bookings", "reminder_sent_at")
