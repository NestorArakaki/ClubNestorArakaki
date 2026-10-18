# Render Web Service Free + PostgreSQL Free

No se crearon servicios remotos en esta tarea. La configuración versionada usa
**Free en ambos recursos**, sin pre-deploy, workers de fondo ni tareas pagas.
No elegir Starter ni Basic. Revisar la pantalla de creación antes de confirmar.

## Opción A: Blueprint

1. En Render → New → Blueprint, conectar `NestorArakaki/ClubNestorArakaki`.
   Seleccionar la rama que contiene esta implementación. Antes de fusionar,
   es `feat/flutter-firebase-free-render`; después, seleccionar la rama integrada.
2. Blueprint Path: `backend/render.yaml`.
3. Comprobar que Web Service y Postgres dicen **Free**, en la misma región.
   La cuenta sólo admite una base PostgreSQL Free activa.
4. Completar `FIREBASE_PROJECT_ID`, `FIREBASE_SERVICE_ACCOUNT_JSON` y
   `CORS_ORIGINS` (vacío para Android). El JSON de servicio completo se pega
   únicamente en el campo privado de Render, nunca en YAML, Git ni Flutter.
   El `project_id` del JSON debe coincidir con el proyecto de Authentication.
5. Crear los servicios. Auto-deploy está desactivado. Desplegar manualmente
   cuando se quiera publicar una revisión del código.

## Opción B: creación manual desde cero

1. New → PostgreSQL → nombre `club-nestor-arakaki-db`, database `club`, user `club`,
   versión 16 y plan **Free**. Elegir una región y anotar su fecha de vencimiento.
2. Copiar la **Internal Database URL**, sin publicarla. No necesita acceso
   externo para que la use el Web Service de la misma región.
3. New → Web Service → conectar el repo y seleccionar la rama correcta.
   Runtime Python, Root Directory `backend`, plan **Free** y la misma región.
4. Build Command: `pip install -r requirements.txt`.
5. Start Command: `sh scripts/start.sh`.
6. Health Check Path: `/api/v1/health`.
7. Configurar las variables de la tabla siguiente. No configurar pre-deploy.
8. Crear/desplegar; revisar logs de Alembic y luego Gunicorn. Un error de
   migración impide que la API inicie: corregir la causa y redeploy, no omitirla.

## Variables de entorno

| Variable | Valor / finalidad |
| --- | --- |
| `PYTHON_VERSION` | `3.12.14` |
| `DATABASE_URL` | Internal Database URL de Render; Blueprint la vincula automáticamente |
| `FIREBASE_PROJECT_ID` | ID real del mismo proyecto usado en Android |
| `FIREBASE_SERVICE_ACCOUNT_JSON` | JSON privado completo de Firebase Admin, en una variable privada |
| `FCM_ENABLED` | `true` para activar los avisos; predeterminado `false` |
| `CORS_ORIGINS` | Vacío para Android; para Web, sólo orígenes explícitos separados por coma |
| `SEED_ON_START` | `true` si se quiere precargar antes de Gunicorn; `false` de forma predeterminada |
| `SEED_FILE` | Ruta al JSON de sedes, predeterminado `seed_data.json` (datos demo) |
| `PORT` | Lo asigna Render; no hace falta fijarlo |

La cuenta Firebase Admin necesita consultar usuarios para comprobar revocación y
estado (`firebaseauth.users.get`), y para push enviar FCM
(`cloudmessaging.messages.create`). Configurar los permisos mínimos adecuados en
IAM. Si hay autenticación pero no llegan avisos, comprobar API FCM v1, permisos,
`FCM_ENABLED`, token registrado y permisos Android.

### Secret Files y alternativa JSON

La [documentación de secretos de Render](https://render.com/docs/configure-environment-variables#secret-files)
permite montar Secret Files y no establece una exclusión para Free; tampoco
aparece entre las limitaciones del [plan gratuito](https://render.com/docs/free).
Se puede usar esta vía: cargar `firebase.json` en Environment → Secret Files,
configurar `GOOGLE_APPLICATION_CREDENTIALS=/etc/secrets/firebase.json` y dejar
`FIREBASE_SERVICE_ACCOUNT_JSON` vacío o ausente.

El Blueprint usa la alternativa por variable privada para evitar depender de
un archivo montado. Acepta el JSON original completo; las secuencias `\n` de
`private_key` ya son parte del JSON. No reemplazarlas por texto escapado dos veces.
El servidor hace `json.loads` y `credentials.Certificate` en memoria; no imprime
el JSON ni escribe la clave al disco. Si la variable está presente, tiene
prioridad sobre ADC/Secret File. Configurar **una sola vía** para evitar confusiones.
Un JSON inválido causa 503 en rutas privadas; jamás habilita autenticación falsa.

## Migraciones y precarga sin Shell

Free no tiene Render Shell/SSH ni one-off jobs. El script de inicio:

1. Ejecuta `flask --app wsgi db upgrade`.
2. Alembic toma un advisory lock transaccional PostgreSQL para que dos arranques
   no migren simultáneamente. Si no puede obtenerlo dentro de 60 segundos, falla
   el arranque; no se continúa con un esquema incompleto.
3. Si `SEED_ON_START=true`, ejecuta `flask --app wsgi seed --file "$SEED_FILE"`.
4. Sólo si todo terminó correctamente hace `exec gunicorn`, con un worker y
   cuatro threads para ajustar memoria/conexiones al servicio Free.

Para precargar, primero revisar `backend/seed_data.json`: está rotulado como
**demostración**. Para datos reales, agregar un archivo de catálogo propio sin
información privada y configurar `SEED_FILE`. La operación inserta faltantes y
conserva los datos existentes; no borra reservas ni actualiza sedes existentes.
`SEED_ON_START=true` puede mantenerse: repetirla es idempotente. Si se desactiva
por configuración, no borra lo cargado. Un seed inválido también detiene el arranque.

El usuario PostgreSQL que migra necesita permiso CREATE para instalar
`btree_gist`, extensión que sostiene la protección contra superposiciones.
No sustituir PostgreSQL por SQLite ni eliminar esa restricción. Si Render
rechaza la extensión, guardar el error y revisar permisos de la base.

## Comprobación desde PowerShell

```powershell
$api = 'https://TU-SERVICIO.onrender.com'
Invoke-RestMethod "$api/api/v1/health"
Invoke-RestMethod "$api/api/v1/venues"
Start-Process "$api/docs"
```

La salud verifica conexión a PostgreSQL, no Firebase. Comprobar además un login
y acceso a Perfil desde Android, crear una reserva y cancelarla. Para apuntar
Flutter a Render sólo cambiar `API_BASE_URL` en `config/firebase.json`:

```powershell
flutter run --dart-define-from-file=config/firebase.json
```

No publicar ni copiar un ID token a capturas o repositorios. Swagger permite
probar rutas autenticadas pegando un ID token real de corta duración en Authorize.

## Límites del servicio gratuito

Según [Render Free](https://render.com/docs/free), consultado el 18/10/2026:

- El Web Service se suspende tras 15 minutos sin tráfico y puede tardar cerca
  de un minuto en despertar. El cliente tiene timeout de 90 segundos y reintento
  manual. Abrir `/api/v1/health` antes de la demostración.
- PostgreSQL Free vence 30 días después de crearse. Tiene un período de gracia
  de 14 días antes de eliminar los datos; la base vencida ya es inaccesible.
  No depende de este proyecto evitar ese vencimiento: exportar datos antes y
  planificar la demo dentro del período gratuito.
- Sin backups administrados ni disco persistente; el catálogo y las reservas
  viven en PostgreSQL. No guardar datos importantes en el disco del Web Service.
- Hay cuotas de uso. Para mantener costo cero, no agregar un método de pago ni
  aceptar upgrades o uso adicional con cargo. Si se agotan las cuotas sin método
  de pago, Render puede suspender servicios o nuevas compilaciones.

Se cambió únicamente la configuración y el arranque. No se verificó un deploy
real, porque requiere la cuenta Render y las credenciales del proyecto.
