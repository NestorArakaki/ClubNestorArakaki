"""Tokens FCM por usuario.

Revision ID: 1002_devices
Revises: db656990be05
"""

import sqlalchemy as sa
from alembic import op

revision = "1002_devices"
down_revision = "db656990be05"
branch_labels = None
depends_on = None


def upgrade():
    op.create_table(
        "devices",
        sa.Column("id", sa.Integer(), nullable=False),
        sa.Column("user_id", sa.Integer(), nullable=False),
        sa.Column("token", sa.String(4096), nullable=False),
        sa.Column("token_hash", sa.String(64), nullable=False),
        sa.Column(
            "updated_at", sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False
        ),
        sa.ForeignKeyConstraint(["user_id"], ["users.id"], name="fk_devices_user_id_users"),
        sa.PrimaryKeyConstraint("id", name="pk_devices"),
        sa.UniqueConstraint("token_hash", name="uq_devices_token_hash"),
    )
    op.create_index("ix_devices_user_id", "devices", ["user_id"])


def downgrade():
    op.drop_table("devices")
