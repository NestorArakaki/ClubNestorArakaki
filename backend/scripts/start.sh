#!/bin/sh
set -eu
# Una sola vez por proceso de arranque; Alembic toma un lock PostgreSQL.
flask --app wsgi db upgrade
if [ "${SEED_ON_START:-false}" = "true" ]; then
    flask --app wsgi seed --file "${SEED_FILE:-seed_data.json}"
fi
# set -e impide llegar a Gunicorn si falla la migración o la precarga solicitada.
exec gunicorn wsgi:app --bind "0.0.0.0:${PORT:-8000}" --workers 1 --threads 4 --timeout 120 --access-logfile -
