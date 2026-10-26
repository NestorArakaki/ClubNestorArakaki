# Guía para comprender y defender ClubNestorArakaki

Esta guía explica el código que está en el repositorio. La consigna oficial es
la fuente de requisitos; Figma es referencia de navegación. Antes de exponer,
ejecutá el flujo con tus propias cuentas y comprobá los resultados. Entender
estas decisiones no reemplaza practicar la demostración.

## 1. Objetivo general

Una persona se identifica, elige una sede y un espacio deportivo, consulta turnos
por fecha y reserva horas completas. Después puede consultar su historial,
cancelar un turno que no terminó y recibir un recordatorio push antes de empezar.
El proyecto se llama `ClubNestorArakaki`, igual que el repositorio. Las sedes y
canchas se precargan: el profesor no pide una pantalla de administración.

## 2. Arquitectura y elección

Hay una app Flutter en Android y una sola API Flask. Flutter dibuja pantallas;
Flask aplica reglas y guarda información en PostgreSQL. Firebase Authentication
verifica la identidad y Firebase Cloud Messaging entrega mensajes al dispositivo.
Render aloja Flask y PostgreSQL. Un workflow de GitHub dispara los recordatorios.

Ejemplo completo: Flutter pide a Firebase un ID Token, lo adjunta al POST de
reserva y Flask verifica ese token. Si los datos y el horario son válidos,
PostgreSQL guarda la reserva y Flask devuelve JSON. Flutter muestra el resultado.
Ni la app ni quien envía JSON pueden elegir un propietario diferente.

Esta separación permite cambiar la interfaz sin mover las reglas al celular.
También permite que dos celulares compartan la misma disponibilidad. No hay
microservicios, una cola de tareas, Redis ni una base Firebase adicional. El
workflow sólo pide a Flask que revise próximos turnos; no lleva reglas de negocio.

## 3. Carpetas y piezas importantes

| Ruta | Qué buscar y para qué sirve |
| --- | --- |
| `lib/main.dart` | Inicialización Firebase y zonas horarias; `Bootstrap` muestra ayuda si falta configuración. |
| `lib/app.dart` | `ClubApp` escucha sesión; `HomeScreen` conecta sedes, reservas, perfil y cierre de sesión. |
| `lib/models/models.dart` | Convierte JSON a objetos Dart; `Availability.maxDuration` cuenta bloques libres consecutivos. |
| `lib/services/auth_service.dart` | `FirebaseAuthService` llama a Firebase real; traduce errores para el usuario. |
| `lib/services/api_client.dart` | Una URL base, peticiones HTTP, token, errores, paginación y métodos de cada recurso. |
| `lib/services/notification_service.dart` | Token FCM, permisos, avisos en primer plano y apertura de la reserva. |
| `lib/services/formatters.dart` | Horarios de la sede y validación de formularios. |
| `lib/screens/` | Formularios de auth/perfil, catálogo, disponibilidad, listado y detalle de reservas. |
| `lib/widgets/async_view.dart` | `AsyncView` reutiliza carga, error y reintento; también confirmaciones y mensajes. |
| `backend/app/models.py` | Las seis entidades PostgreSQL y sus restricciones. |
| `backend/app/routes.py` | Endpoints y permisos: catálogo público, operaciones privadas, scheduler separado. |
| `backend/app/schemas.py` | Campos JSON permitidos y validaciones de entrada/salida; documentan OpenAPI. |
| `backend/app/auth.py` | Verificación del ID Token y obtención del perfil local en `g.user`. |
| `backend/app/services.py` | Disponibilidad, creación, cancelación y apertura semanal. |
| `backend/app/notifications.py` | Envío FCM reutilizado y `send_upcoming_reminders`. |
| `backend/migrations/` | Evolución versionada del esquema; no se crea todo de nuevo al iniciar. |
| `backend/seed_data.json`, `seed.py` | Catálogo demo e importación idempotente. |
| `test/`, `backend/tests/` | Pruebas de los comportamientos y reglas que necesito defender. |
| `.github/workflows/` | Checks y reloj externo del recordatorio. |

`AuthService` es un contrato pequeño que hace posible sustituir Firebase sólo en
pruebas. No es un sistema alternativo de login. `ApiClient` evita repetir URL,
Bearer y parseo en cada pantalla. No agregamos una capa por cada clase del negocio.

## 4. Registro, login y recuperación

`AuthScreen` valida correo, longitud de contraseña y confirmación al registrarse.
Llama a `FirebaseAuthService.register/login`. La contraseña se envía al SDK de
Firebase Auth; no se almacena en Flutter ni en PostgreSQL.

Firebase conserva la sesión en el dispositivo. `ClubApp` escucha
`authStateChanges`: sin usuario muestra login; con usuario muestra Home. Al
cerrar sesión se descartan las rutas de la cuenta anterior. Recuperar contraseña
usa `sendPasswordResetEmail`; Firebase envía un enlace seguro. Hay que probar
ese correo de verdad, también revisando spam.

El primer GET `/me` crea el perfil local si no existía, usando `firebase_uid` y
email del token verificado. Nombre, apellido y nacimiento se completan en Perfil.
El correo no se edita ahí: está ligado a la identidad Firebase. El servidor
rechaza un PATCH que intente modificarlo, aunque alguien quite el readOnly en Flutter.

## 5. Comunicación Flutter–Flask

`ApiClient` recibe `API_BASE_URL`, que termina en `/api/v1`. Para un emulador
Android estándar, `10.0.2.2` permite llegar a Flask ejecutándose en Windows.
Para Render se usa su URL HTTPS. No se cambia una URL en cada pantalla.

Los GET de catálogo son públicos. En rutas privadas, `auth.token(false)` obtiene
un ID Token y el cliente adjunta `Authorization: Bearer ...`. El token es una
prueba firmada de identidad; no es el UID ni la clave API pública de Firebase.
El SDK lo renueva normalmente. Ante 401 el cliente fuerza una renovación una
sola vez y, si sigue fallando, pide iniciar sesión de nuevo.

Flask comprueba firma/proyecto/expiración/revocación y si el usuario está
habilitado. `login_required` pone el usuario verificado en `g.user`. Por eso
POST `/bookings` sólo necesita `court_id`, `starts_at` y `duration_hours`, nunca
`user_id`. Las páginas de sedes/canchas/reservas se recorren con `page/per_page`.

## 6. Flask y PostgreSQL

Flask recibe HTTP; los schemas comprueban datos; los servicios aplican reglas;
SQLAlchemy expresa consultas y cambios. PostgreSQL es quien persiste los datos
y protege las relaciones y superposiciones. Una transacción agrupa cambios:
`commit` los confirma; `rollback` descarta los no confirmados si algo falla.

Alembic lleva las migraciones. `scripts/start.sh` ejecuta `db upgrade`, precarga
si se pidió y recién entonces arranca Gunicorn. Si la migración falla, no inicia
una API con tablas incompletas. Un lock PostgreSQL evita migrar simultáneamente.
No se ejecuta `create_all()` en producción para esconder cambios del esquema.

## 7. Consulta de disponibilidad

Se elige sede → cancha → fecha. `GET /courts/{id}/availability?date=AAAA-MM-DD`
busca la zona de la sede, el horario semanal del día y las reservas confirmadas
que cruzan ese intervalo. Devuelve bloques de una hora con `available`.

Un bloque ocupado o cuyo inicio ya pasó aparece deshabilitado. Un día sin
apertura devuelve lista vacía. No se informa quién reservó otro turno. Para dos
horas, Flutter exige dos bloques consecutivos libres, no simplemente dos horarios
separados. Los horarios se muestran en la zona de la sede; `toLocal()` solo
usaría la del teléfono y podría mostrar una hora equivocada.

## 8. Creación y prevención de superposición

`create_booking` verifica que la cancha exista/esté activa, el comienzo tenga
zona horaria, sea futuro y corresponda a una hora entera. Calcula el fin con
la duración y comprueba que el intervalo entre dentro de la apertura. La duración
es entera, de al menos una hora. Puede terminar exactamente al cierre.

La consulta de disponibilidad es informativa: otro usuario puede reservar entre
el GET y el POST. Por eso la protección definitiva está en PostgreSQL:
`bookings_no_overlap`, una exclusión GiST de cancha e intervalo para filas no
canceladas. Dos solicitudes simultáneas que se cruzan no pueden confirmarse.
Una devuelve 201 y la otra 409; el cliente recarga los horarios.

Se usa `[inicio, fin)`: 18–19 y 19–20 son adyacentes, no se superponen. 18–20 y
19–21 sí. El test concurrente usa conexiones distintas para comprobar este caso;
no se confía en que un solo proceso Python atienda de a una petición.

## 9. Cancelación

`cancel_booking` busca una reserva cuyo `user_id` sea el de `g.user` y bloquea
esa fila. Si es ajena o no existe devuelve 404. Si ya estaba cancelada devuelve
el mismo resultado; eso es idempotencia. Si finalizó no se cancela, para conservar
el hecho histórico; puede cancelarse una propia futura o en curso.

Se completa `cancelled_at`, no se borra la fila. Al hacer commit deja de participar
en la exclusión, el turno se libera y el historial conserva la cancelación.
Flutter solicita confirmación y refresca. La regla anterior cortaba la cancelación
al inicio; se relajó al final porque la consigna no impone ese corte temprano.

## 10. Push y recordatorios próximos

FCM no sabe por sí solo cuándo es una reserva. El reloj externo de GitHub Actions
llama cada diez minutos a `/internal/booking-reminders` con una clave privada
que no pertenece al cliente. Se comprueba con comparación segura y no se acepta
un token de usuario como permiso de programador.

`send_upcoming_reminders` elige reservas sin cancelar, no iniciadas, dentro de la
próxima hora y con marca pendiente. Bloquea las filas, envía al token real del
propietario y guarda `reminder_sent_at` si FCM aceptó al menos un envío. Si no,
permanece pendiente para otro intento. El TTL vence al empezar el turno. Una
segunda ejecución normal no lo vuelve a enviar. La marca está en PostgreSQL y
sobrevive a una suspensión de Flask.

En Android se piden permisos, se registra el token con una ruta autenticada y
se sincroniza si cambia. En primer plano se muestra un aviso local; en segundo
plano Android presenta el push. Al tocarlo se comprueba `recipient_uid` y se
consulta la reserva propia; el servidor vuelve a controlar propiedad.

Los avisos de creación/cancelación existentes usan el mismo emisor, pero **el
recordatorio programado es el que satisface el requisito de reserva próxima**.
Nada de esto se probó con un proyecto Firebase inventado. Los tests sustituyen
el SDK; la configuración y entrega reales se verifican en el emulador del alumno.

No se promete entrega exactamente una vez: FCM puede aceptar y no entregar;
GitHub puede retrasarse; una caída entre envío y commit puede repetir un aviso.
No se agregó infraestructura extra para resolver una garantía que el TP no pide.
Activación y límites concretos en [RECORDATORIOS.md](RECORDATORIOS.md).

## 11. Errores y resultado incierto

Un error de red no es igual a un rechazo HTTP. `ApiClient` distingue conexión y
timeout de 400/401/404/409/422/500/503. Flask usa JSON uniforme con código y mensaje.
Los formularios validan y muestran mensajes comprensibles, pero el backend vuelve
a validar porque cualquier cliente podría enviar HTTP sin usar nuestros formularios.

Si se pierde Internet justo después del POST, la reserva podría haberse guardado.
No se repite el POST automáticamente: la pantalla pide revisar Mis reservas antes
de intentar de nuevo. Si llega 409, sí sabemos que el intervalo no se confirmó
en esa solicitud y recargamos disponibilidad. Un fallo push no revierte una
reserva que ya fue confirmada en la base.

## 12. Modelo entidad-relación

Leer [MODELO_DATOS.md](MODELO_DATOS.md): son seis tablas. Una sede tiene horarios y
canchas. Una cancha recibe muchas reservas; cada reserva pertenece a un usuario.
Un usuario tiene dispositivos FCM. Las FK mantienen esas relaciones. El email
viene de Firebase; no hay una contraseña local ni una tabla de administradores.

`Court.full_name` devuelve sede, dirección, deporte y número. Se calcula desde
las entidades relacionadas para no copiar la misma dirección en todas las filas.
La etiqueta interna corta `Court.name` conserva las precargas existentes. El
número es el ID estable de la cancha, sin renumerar reservas anteriores.

## 13. Ejecución y demostración

Tu Flutter 3.47.7 / Dart 3.13.5, API 36 y NDK 28.2.13676358 ya son compatibles.
No reinstales herramientas por diferencias de rutas del entorno Cloud. Ver
[COMPATIBILIDAD.md](COMPATIBILIDAD.md). Configurar el mismo proyecto Firebase
para Android y Admin, el backend y el token FCM siguiendo las guías existentes.

Desde `C:\dev\ClubNestorArakaki`:

```powershell
flutter pub get
flutter analyze
flutter test
flutter devices
flutter run --dart-define-from-file=config/firebase.json
```

Practicá: registro → Home → perfil → sede/horarios → filtro → cancha/fecha →
reserva → Mis reservas → cancelación/liberación → historial. Para el recordatorio,
reservá dentro de la próxima hora y ejecutá el endpoint protegido o el workflow;
poner el celular en segundo plano y tocar el aviso. La hora de inicio sigue
siendo completa; elegir un día/hora que realmente entre en esa ventana.

Usá dos cuentas para mostrar que no se ven reservas ajenas y que un turno ocupado
no puede volver a reservarse. Mostrar un listado vacío no demuestra historial:
podés usar una reserva real que ya haya finalizado en la fecha de la exposición.
No modificar fechas directamente en una base real para fabricar esa evidencia.
Preparar los dos ZIP según [ENTREGA_TP.md](ENTREGA_TP.md) y completar [DEMO.md](DEMO.md).

## 14. Preguntas para practicar

| Pregunta del profesor | Respuesta que debo comprender |
| --- | --- |
| ¿Dónde están las contraseñas? | En Firebase Authentication. Mi API sólo verifica el ID Token y guarda perfil/reservas. |
| ¿Por qué no enviar user_id? | Porque cualquiera podría escribir otro ID; Flask obtiene la identidad del token firmado. |
| ¿Qué hace una API REST acá? | Expone recursos por HTTP, por ejemplo GET de sedes y POST de reservas, con JSON y estados HTTP. |
| ¿Qué ocurre si reservan a la vez? | PostgreSQL impide el cruce con una exclusión; una solicitud recibe 409 y refresca. |
| ¿Por qué no alcanza con consultar disponibilidad primero? | Entre consultar y guardar otro usuario puede reservar. La restricción protege el momento de guardar. |
| ¿Cómo se libera el turno? | Se marca la cancelación y se confirma la transacción; esa fila deja de bloquear el intervalo. |
| ¿Borrás la reserva cancelada? | No, conservo historial. Repetir la cancelación no altera el resultado. |
| ¿Cómo sabés que hay un próximo turno con la app cerrada? | El workflow llama al backend; el backend consulta PostgreSQL y envía FCM. No depende de un timer en la app. |
| ¿Cómo evitás que cualquiera dispare push? | La ruta del programador requiere una clave privada separada, no publicada ni incluida en Flutter. |
| ¿Por qué un token FCM y otro de Auth? | Auth identifica a la persona; FCM identifica una instalación a la que enviar un aviso. No son intercambiables. |
| ¿Qué pasa si cae Firebase o Render? | Muestro un error y permito reintentar lecturas. No invento datos ni confirmo una reserva que no pude comprobar. |
| ¿Qué diferencia hay entre migración y precarga? | La migración cambia tablas/restricciones; la precarga inserta catálogo sin duplicarlo. |
| ¿Qué entrega Swagger? | Documenta rutas, campos, respuestas y seguridad a partir de los schemas/rutas de Flask. |
| ¿Qué probaste realmente? | Ver VERIFICACION.md: pruebas automatizadas y compilación se distinguen de Firebase, scheduler y Render reales. |
| ¿Qué simplificaste? | Reutilicé cliente HTTP y envío FCM, filtré la lista ya descargada y derivé el nombre. No agregué servicios extra ni rehice módulos probados. |
| ¿Qué limitación tiene lo gratuito? | Render se suspende y su PostgreSQL vence; GitHub puede demorar el cron. Lo preparé y documenté, sin prometer continuidad garantizada. |

Para estudiar, elegí una ruta y seguí sus llamadas en el código; después explicala
sin leer esta tabla. Si no podés explicar una restricción o un test, reproducilo
en una base descartable y observá el resultado antes de la exposición.
