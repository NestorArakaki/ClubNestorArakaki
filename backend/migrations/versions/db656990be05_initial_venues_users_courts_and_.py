"""Initial venues users courts and exclusion-protected bookings

Revision ID: db656990be05
Revises:
Create Date: 2026-10-18 04:00:54.061582

"""

import sqlalchemy as sa
from alembic import op
from sqlalchemy.dialects import postgresql

# revision identifiers, used by Alembic.
revision = "db656990be05"
down_revision = None
branch_labels = None
depends_on = None


def upgrade():
    # Extensión confiable disponible en PostgreSQL/Render; requiere CREATE en la base.
    op.execute("CREATE EXTENSION IF NOT EXISTS btree_gist")
    op.create_table(
        "users",
        sa.Column("id", sa.Integer(), nullable=False),
        sa.Column("firebase_uid", sa.String(length=128), nullable=False),
        sa.Column("email", sa.String(length=320), nullable=True),
        sa.Column("first_name", sa.String(length=100), nullable=True),
        sa.Column("last_name", sa.String(length=100), nullable=True),
        sa.Column("birth_date", sa.Date(), nullable=True),
        sa.Column(
            "created_at",
            sa.DateTime(timezone=True),
            server_default=sa.text("now()"),
            nullable=False,
        ),
        sa.PrimaryKeyConstraint("id", name=op.f("pk_users")),
        sa.UniqueConstraint("firebase_uid", name=op.f("uq_users_firebase_uid")),
    )
    op.create_table(
        "venues",
        sa.Column("id", sa.Integer(), nullable=False),
        sa.Column("name", sa.String(length=120), nullable=False),
        sa.Column("address", sa.String(length=250), nullable=False),
        sa.Column("timezone", sa.String(length=64), nullable=False),
        sa.PrimaryKeyConstraint("id", name=op.f("pk_venues")),
        sa.UniqueConstraint("name", name=op.f("uq_venues_name")),
    )
    op.create_table(
        "courts",
        sa.Column("id", sa.Integer(), nullable=False),
        sa.Column("venue_id", sa.Integer(), nullable=False),
        sa.Column("name", sa.String(length=120), nullable=False),
        sa.Column("sport", sa.String(length=80), nullable=False),
        sa.Column("active", sa.Boolean(), server_default=sa.text("true"), nullable=False),
        sa.ForeignKeyConstraint(
            ["venue_id"], ["venues.id"], name=op.f("fk_courts_venue_id_venues")
        ),
        sa.PrimaryKeyConstraint("id", name=op.f("pk_courts")),
        sa.UniqueConstraint("venue_id", "name", name=op.f("uq_courts_venue_id")),
    )
    with op.batch_alter_table("courts", schema=None) as batch_op:
        batch_op.create_index(batch_op.f("ix_courts_venue_id"), ["venue_id"], unique=False)

    op.create_table(
        "opening_hours",
        sa.Column("id", sa.Integer(), nullable=False),
        sa.Column("venue_id", sa.Integer(), nullable=False),
        sa.Column("weekday", sa.SmallInteger(), nullable=False),
        sa.Column("open_hour", sa.SmallInteger(), nullable=False),
        sa.Column("close_hour", sa.SmallInteger(), nullable=False),
        sa.CheckConstraint(
            "open_hour >= 0 AND open_hour < close_hour AND close_hour <= 24",
            name=op.f("ck_opening_hours_hour_range"),
        ),
        sa.CheckConstraint("weekday BETWEEN 0 AND 6", name=op.f("ck_opening_hours_weekday_range")),
        sa.ForeignKeyConstraint(
            ["venue_id"], ["venues.id"], name=op.f("fk_opening_hours_venue_id_venues")
        ),
        sa.PrimaryKeyConstraint("id", name=op.f("pk_opening_hours")),
        sa.UniqueConstraint("venue_id", "weekday", name=op.f("uq_opening_hours_venue_id")),
    )
    op.create_table(
        "bookings",
        sa.Column("id", sa.Integer(), nullable=False),
        sa.Column("user_id", sa.Integer(), nullable=False),
        sa.Column("court_id", sa.Integer(), nullable=False),
        sa.Column("starts_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("ends_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("cancelled_at", sa.DateTime(timezone=True), nullable=True),
        sa.Column(
            "created_at",
            sa.DateTime(timezone=True),
            server_default=sa.text("now()"),
            nullable=False,
        ),
        postgresql.ExcludeConstraint(
            (sa.column("court_id"), "="),
            (sa.text("tstzrange(starts_at, ends_at, '[)')"), "&&"),
            where=sa.text("cancelled_at IS NULL"),
            using="gist",
            name="bookings_no_overlap",
        ),
        sa.CheckConstraint(
            "EXTRACT(EPOCH FROM (ends_at - starts_at)) BETWEEN 3600 AND 86400 "
            "AND MOD(EXTRACT(EPOCH FROM (ends_at - starts_at)), 3600) = 0",
            name=op.f("ck_bookings_whole_hours"),
        ),
        sa.CheckConstraint("ends_at > starts_at", name=op.f("ck_bookings_positive_duration")),
        sa.ForeignKeyConstraint(
            ["court_id"], ["courts.id"], name=op.f("fk_bookings_court_id_courts")
        ),
        sa.ForeignKeyConstraint(["user_id"], ["users.id"], name=op.f("fk_bookings_user_id_users")),
        sa.PrimaryKeyConstraint("id", name=op.f("pk_bookings")),
    )
    with op.batch_alter_table("bookings", schema=None) as batch_op:
        batch_op.create_index("ix_bookings_user_starts", ["user_id", "starts_at"], unique=False)

    # ### end Alembic commands ###


def downgrade():
    # ### commands auto generated by Alembic - please adjust! ###
    with op.batch_alter_table("bookings", schema=None) as batch_op:
        batch_op.drop_index("ix_bookings_user_starts")

    op.drop_table("bookings")
    op.drop_table("opening_hours")
    with op.batch_alter_table("courts", schema=None) as batch_op:
        batch_op.drop_index(batch_op.f("ix_courts_venue_id"))

    op.drop_table("courts")
    op.drop_table("venues")
    op.drop_table("users")
    # ### end Alembic commands ###
