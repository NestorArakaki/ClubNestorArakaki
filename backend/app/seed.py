import json
from pathlib import Path
from zoneinfo import ZoneInfo

import click
from flask.cli import with_appcontext
from sqlalchemy.dialects.postgresql import insert

from .extensions import db
from .models import Court, OpeningHour, Venue


def load_seed(path):
    """Idempotente, transaccional y sólo inserta faltantes; nunca borra reservas ni horarios."""
    entries = json.loads(Path(path).read_text(encoding="utf-8"))
    if not isinstance(entries, list) or not entries:
        raise ValueError("El archivo debe contener una lista de sedes.")
    for entry in entries:
        ZoneInfo(entry["timezone"])
        venue_id = db.session.scalar(
            insert(Venue)
            .values(name=entry["name"], address=entry["address"], timezone=entry["timezone"])
            .on_conflict_do_update(index_elements=[Venue.name], set_={"name": entry["name"]})
            .returning(Venue.id)
        )
        for schedule in entry["opening_hours"]:
            db.session.execute(
                insert(OpeningHour)
                .values(venue_id=venue_id, **schedule)
                .on_conflict_do_nothing(index_elements=["venue_id", "weekday"])
            )
        for court in entry["courts"]:
            db.session.execute(
                insert(Court)
                .values(venue_id=venue_id, **court)
                .on_conflict_do_nothing(index_elements=["venue_id", "name"])
            )
    db.session.commit()


@click.command("seed")
@click.option(
    "--file",
    "seed_file",
    type=click.Path(exists=True, dir_okay=False),
    default=str(Path(__file__).resolve().parent.parent / "seed_data.json"),
)
@with_appcontext
def seed_command(seed_file):
    """Precargar datos de demostración o un archivo propio con el mismo formato."""
    try:
        load_seed(seed_file)
    except Exception as exc:
        db.session.rollback()
        raise click.ClickException(
            f"No se pudo precargar ({type(exc).__name__}). Revisá el archivo."
        ) from exc
    click.echo("Sedes, horarios y canchas precargados; los datos existentes se conservaron.")
