# Backend ClubNestorArakaki

API REST en Python 3.12, Flask y PostgreSQL 16. No requiere cambios en Flutter
para instalarse o probarse. No incluye administración ni pagos.

## Inicio local

Requisitos: Python 3.12, Docker con Compose y una cuenta/proyecto de Firebase con
Authentication habilitado. Alternativamente, usar PostgreSQL 16 instalado localmente.
Los comandos siguientes se ejecutan desde la raíz del repositorio:

```bash
cd backend
python3.12 -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt
cp .env.example .env
docker compose up -d --wait db
```

En PowerShell, activar con `.venv\Scripts\Activate.ps1` y copiar con
`Copy-Item .env.example .env`. Si el puerto 5432 ya está ocupado, cambiarlo tanto
en Compose como en `DATABASE_URL`.

Editar `.env` con el **ID del proyecto Firebase**, no la API key de Flutter, y la
ruta absoluta al archivo JSON de una cuenta de servicio de ese proyecto. Se
obtiene en Firebase Console → Configuración del proyecto → Cuentas de servicio.
La cuenta debe poder consultar usuarios de Firebase Authentication para comprobar
revocación/deshabilitación (`firebaseauth.users.get`, por ejemplo con el rol
Firebase Authentication Viewer). No subir el archivo a Git. También se admiten
Application Default Credentials configuradas con esos permisos.

```bash
flask --app wsgi db upgrade
flask --app wsgi seed
flask --app wsgi run --host 0.0.0.0 --port 8000
```

- Swagger interactivo: [http://localhost:8000/docs](http://localhost:8000/docs).
- OpenAPI 3.0.3: [http://localhost:8000/openapi.json](http://localhost:8000/openapi.json).
- Salud y conexión a PostgreSQL: [http://localhost:8000/api/v1/health](http://localhost:8000/api/v1/health).

Swagger sirve sus recursos JavaScript/CSS localmente; no necesita una CDN.
En **Authorize**, pegar el ID token sin el prefijo `Bearer`.
El catálogo y Swagger funcionan sin credenciales de Firebase. Las rutas privadas
responden 503 si Firebase no está configurado o disponible; nunca aceptan una
identidad inventada. No se admite `FIREBASE_AUTH_EMULATOR_HOST`.

Para ejecutar con el servidor de producción, en Linux/macOS:

```bash
gunicorn wsgi:app --bind 0.0.0.0:8000 --workers 2 --threads 4 --timeout 60 --access-logfile -
```

## Configuración

| Variable | Uso |
| --- | --- |
| `DATABASE_URL` | Obligatoria. PostgreSQL; se normalizan prefijos `postgres://` y `postgresql://` a psycopg 3. |
| `FIREBASE_PROJECT_ID` | Proyecto al que deben pertenecer los ID tokens. Sin valor, las rutas privadas responden 503. |
| `GOOGLE_APPLICATION_CREDENTIALS` | Ruta al JSON privado; Firebase Admin usa ADC. No es una API key. |
| `CORS_ORIGINS` | Orígenes web permitidos, separados por coma. Vacío: no se habilita CORS. Flutter móvil no requiere CORS. |
| `PORT` | Puerto utilizado por el comando de inicio de Render. En Flask CLI usar `--port`. |
| `TEST_DATABASE_URL` | Sólo pruebas; debe apuntar a una base descartable cuyo nombre termine en `_test`. |

Los valores existentes del entorno tienen prioridad sobre `.env`. No usar el
servidor de desarrollo ni debug en producción. Las dependencias y transitivas
están fijadas en `requirements.txt`; `requirements-dev.txt` incluye las de pruebas.
Para actualizarlas, instalar los `.in` en un entorno virtual limpio, ejecutar
las pruebas y regenerar cada lista con `pip freeze` desde el entorno correspondiente.

## Reservas y consistencia

- Cada sede tiene una zona IANA y un intervalo semanal por día. `weekday=0` es
  lunes y `6` domingo. Un día sin fila está cerrado. Los horarios son horas
  enteras locales y `close_hour=24` representa medianoche del día siguiente.
- Las reservas empiezan en una hora entera local, duran de 1 a 24 horas reales
  consecutivas y deben caber en un intervalo de apertura. No cruzan un cierre.
  Una reserva puede terminar exactamente al cierre. Para horarios nocturnos se
  pueden representar los intervalos de cada día, pero una reserva no cruza ambos.
- Se reciben timestamps con offset/zona y se guardan instantes `TIMESTAMPTZ`.
  La API responde timestamps ISO 8601 en UTC (`+00:00`). La fecha de disponibilidad
  corresponde al calendario **de la sede**, que puede diferir de la fecha UTC.
- No se aceptan comienzos pasados ni fechas de disponibilidad pasadas. Los slots
  de hoy cuyo inicio ya pasó aparecen con `available=false`.
- PostgreSQL tiene una exclusión GiST sobre `(court_id, tstzrange(inicio, fin, '[)'))`
  para reservas sin `cancelled_at`. Evita solapamientos incluso con procesos o
  solicitudes simultáneas; no depende de un bloqueo en memoria ni de consultar
  disponibilidad antes de insertar. Dos turnos adyacentes sí se permiten.
- La migración instala `btree_gist`. El usuario que migra necesita permiso
  `CREATE` en la base. No se admite SQLite como sustituto.
- Una cancelación marca `cancelled_at`, conserva historial y libera el intervalo
  al confirmar la transacción. Usa bloqueo de fila y es idempotente. Una reserva
  iniciada no se cancela. Reservas ajenas y ausentes responden 404.
- `GET /bookings` sólo devuelve las reservas de la identidad verificada. El
  propietario no puede especificarse en JSON. El email sólo se sincroniza desde
  los claims firmados de Firebase y no es editable mediante esta API.
- La disponibilidad es una lectura informativa. Entre esa lectura y la creación
  otro usuario puede reservar: Flutter debe manejar el 409 y volver a consultar.

Detalles de endpoints, ejemplos y conexión Flutter en [docs/API.md](docs/API.md).

## Precarga y migraciones

`seed_data.json` contiene **datos de demostración**, no sedes reales confirmadas.
Editar una copia para cargar los datos del club:

```bash
flask --app wsgi seed --file /ruta/sedes.json
```

Formato: lista de sedes con `name`, `address`, `timezone`, `opening_hours`
(`weekday`, `open_hour`, `close_hour`) y `courts` (`name`, `sport`, `active` opcional).
La operación es transaccional e idempotente: inserta faltantes, conserva los
valores existentes, no elimina reservas y no sustituye una administración.
Cada cancha es única por sede/nombre y cada sede por nombre.

No se usa `db.create_all()` en producción ni en las pruebas: el esquema se crea
con migraciones versionadas. Después de modificar modelos:

```bash
flask --app wsgi db migrate -m "Descripción del cambio"
# Revisar manualmente el archivo generado, especialmente restricciones PostgreSQL.
flask --app wsgi db upgrade
flask --app wsgi db check
```

`db downgrade` puede eliminar datos. La extensión compartida `btree_gist` no se
elimina al revertir la migración.

## Pruebas

```bash
pip install -r requirements-dev.txt
docker compose --profile test up -d --wait test-db
export TEST_DATABASE_URL='postgresql+psycopg://club:club_local@localhost:5433/club_test'
python -m pytest --cov=app --cov-report=term-missing
ruff check app tests migrations wsgi.py
ruff format --check app tests migrations wsgi.py
```

En PowerShell: `$env:TEST_DATABASE_URL = 'postgresql+psycopg://club:club_local@localhost:5433/club_test'`.
Las pruebas **truncan tablas** de esa base. Nunca usar una base con información
que deba conservarse. Si no hay URL, fallan con una instrucción de configuración;
no se saltean silenciosamente ni cambian a SQLite.

Se prueban conflictos parciales/totales, intervalos adyacentes, canchas distintas,
fechas/horarios inválidos, cancelación y liberación, historial, identidad propia,
perfil, errores de autenticación, seed y Swagger/OpenAPI. La prueba concurrente
usa conexiones PostgreSQL y clientes independientes, con una barrera antes del
INSERT para que las dos solicitudes intenten reservar simultáneamente. También
verifica solicitudes del mismo usuario y cancelaciones simultáneas.

Las pruebas de API reemplazan el verificador sólo con `monkeypatch` de pytest.
Las de autenticación ejercitan el adaptador al SDK y comprueban explícitamente
`check_revoked=True`; no equivalen a probar un proyecto Firebase real. No hay
bandera de autenticación falsa disponible en producción.

Ver [docs/VERIFICATION.md](docs/VERIFICATION.md) para los resultados y pendientes
de esta implementación. El flujo CI está en `.github/workflows/backend.yml`.

## Render Free y Flutter

La aplicación Flutter ya consume este contrato. Instrucciones completas para
Windows, Firebase y Android en [la guía de instalación](../docs/INSTALACION_WINDOWS.md).

El Blueprint [render.yaml](render.yaml) utiliza Web Service Free y PostgreSQL Free.
El comando `sh scripts/start.sh` ejecuta migraciones con lock transaccional,
precarga opcional idempotente (`SEED_ON_START=true`) y sólo después inicia Gunicorn.
No usa pre-deploy ni Render Shell. [Despliegue completo y límites](../docs/RENDER_FREE.md).

Además de ADC/`GOOGLE_APPLICATION_CREDENTIALS`, se admite
`FIREBASE_SERVICE_ACCOUNT_JSON` como variable privada con el JSON completo.
Tiene prioridad sobre ADC. No guardar ese valor en Git ni en Flutter.
`FCM_ENABLED=true` activa avisos best effort después del commit; los tokens se
registran por `/api/v1/devices` con identidad Firebase verificada. Consultar
[el contrato](docs/API.md) para registro, baja y payloads. Las credenciales de
servicio requieren permisos Auth de lectura y FCM de envío.
