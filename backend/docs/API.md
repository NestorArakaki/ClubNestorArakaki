# Contrato REST y conexión Flutter

Base local: `http://localhost:8000/api/v1`. En producción, usar el dominio HTTPS
de Render seguido de `/api/v1`. JSON con `Content-Type: application/json`.
Contrato OpenAPI generado por las mismas rutas: `/openapi.json`; Swagger: `/docs`.

## Endpoints

| Método | Ruta relativa | Autenticación | Respuesta exitosa |
| --- | --- | --- | --- |
| GET | `/health` | Pública | 200 `{"status":"ok"}` |
| GET | `/venues` | Pública | 200 página de sedes |
| GET | `/venues/{id}` | Pública | 200 sede |
| GET | `/venues/{id}/courts` | Pública | 200 página de canchas activas |
| GET | `/courts/{id}` | Pública | 200 cancha |
| GET | `/venues/{id}/opening-hours` | Pública | 200 lista de horarios |
| GET | `/courts/{id}/availability?date=YYYY-MM-DD` | Pública | 200 disponibilidad |
| GET | `/me` | Bearer | 200 perfil propio |
| PATCH | `/me` | Bearer | 200 perfil actualizado |
| POST | `/bookings` | Bearer | 201 reserva confirmada |
| GET | `/bookings` | Bearer | 200 página de reservas propias |
| GET | `/bookings/{id}` | Bearer | 200 reserva propia |
| DELETE | `/bookings/{id}` | Bearer | 200 reserva cancelada |
| POST | `/devices` | Bearer | 200 dispositivo registrado |
| DELETE | `/devices` | Bearer | 200 dispositivo desvinculado |

Listados paginados: `page` (desde 1, predeterminado 1) y `per_page`
(1–100, predeterminado 20). Una página fuera de rango devuelve `items: []`.
Las sedes/canchas se ordenan por `id`; las reservas por inicio e `id` ascendentes.

## Sedes, canchas y horarios

`GET /venues`:

```json
{
  "items": [{
    "id": 1,
    "name": "Sede Central (demo)",
    "address": "Dirección de ejemplo: reemplazar antes de producción",
    "timezone": "America/Argentina/Buenos_Aires"
  }],
  "page": 1,
  "per_page": 20,
  "total": 1
}
```

`GET /venues/1` devuelve el objeto sede sin el envoltorio de página.
`GET /venues/1/courts` devuelve el mismo envoltorio, con objetos como:

```json
{"id": 1, "venue_id": 1, "name": "Fútbol 5 - 1", "sport": "football", "active": true}
```

`GET /courts/1` devuelve directamente ese objeto. Una cancha inactiva sigue
siendo consultable por ID para interpretar el historial, pero no puede reservarse.

`GET /venues/1/opening-hours` devuelve una lista, por ejemplo:

```json
[
  {"weekday": 0, "open_hour": 8, "close_hour": 23},
  {"weekday": 1, "open_hour": 8, "close_hour": 23}
]
```

Los valores pertenecen a la zona de la sede; 0=lunes, 6=domingo y día ausente=cerrado.
`close_hour=24` es medianoche. Se admite un intervalo por día y no hay feriados
ni excepciones por fecha en esta versión.

## Disponibilidad

`GET /courts/1/availability?date=2026-12-20`:

```json
{
  "court_id": 1,
  "date": "2026-12-20",
  "timezone": "America/Argentina/Buenos_Aires",
  "slots": [
    {"starts_at": "2026-12-20T12:00:00+00:00", "ends_at": "2026-12-20T13:00:00+00:00", "available": true},
    {"starts_at": "2026-12-20T13:00:00+00:00", "ends_at": "2026-12-20T14:00:00+00:00", "available": false}
  ]
}
```

La lista contiene **todos** los bloques horarios de apertura (el ejemplo está
abreviado). `available=false` significa ocupado o inicio ya pasado. Un día
cerrado o una cancha inactiva devuelve `slots: []`. No se exponen los datos de
otros usuarios. Para una reserva de dos horas, elegir dos bloques consecutivos
disponibles y enviar el inicio del primero con `duration_hours: 2`. La creación
confirma la disponibilidad de forma atómica.

## Autenticación y perfil

Las operaciones privadas requieren:

```http
Authorization: Bearer <FIREBASE_ID_TOKEN>
```

Se verifica firma, audiencia/proyecto, emisor, expiración, revocación y estado del
usuario con Firebase Admin. No enviar el UID como autenticación, un custom token,
la API key de Firebase ni un access token OAuth de Google.

`GET /me` crea automáticamente el perfil local si es el primer acceso. Respuesta:

```json
{
  "id": 1,
  "email": "usuario@example.com",
  "first_name": null,
  "last_name": null,
  "birth_date": null
}
```

El email puede ser `null` si la identidad Firebase no tiene ese claim. Se actualiza
desde el token firmado al acceder; si se cambió en Firebase, renovar el token.

`PATCH /me` acepta cualquiera de estos campos y devuelve el perfil completo:

```json
{"first_name": "Ana", "last_name": "Pérez", "birth_date": "2000-02-29"}
```

Nombres de 1 a 100 caracteres luego de validar longitud, sin valores compuestos
sólo por espacios; se guardan sin espacios externos. Fecha entre 1900-01-01 y
hoy. `birth_date: null` borra la fecha. Nombres `null` no se admiten.
Enviar `email`, `firebase_uid`, `id` o cualquier campo desconocido produce 422.
Un PATCH vacío conserva los valores.

## Crear una reserva

`POST /bookings`:

```json
{"court_id": 1, "starts_at": "2026-12-20T18:00:00-03:00", "duration_hours": 2}
```

`court_id` y `duration_hours` deben ser enteros JSON; no se aceptan booleanos,
fracciones ni strings numéricos. Duración 1–24. `starts_at` requiere offset o `Z`
y hora local exacta sin minutos/segundos/fracciones. Años admitidos 1900–9998,
pero los comienzos pasados se rechazan. El intervalo completo debe caber en la apertura.
El servidor obtiene al propietario del token; `user_id` es un campo desconocido.

Respuesta **201**:

```json
{
  "id": 42,
  "court_id": 1,
  "starts_at": "2026-12-20T21:00:00+00:00",
  "ends_at": "2026-12-20T23:00:00+00:00",
  "created_at": "2026-10-18T15:00:00+00:00",
  "cancelled_at": null,
  "status": "confirmed"
}
```

Las fechas de ejemplo son ilustrativas: reemplazarlas por una fecha futura al
probar. No hay duración o propietario editable después de crear; para cambiar
el horario, cancelar y crear otra reserva, sujeto a disponibilidad.

## Historial y cancelación

`GET /bookings?period=future&status=confirmed&page=1&per_page=20` devuelve el
envoltorio de página con objetos de reserva como el anterior.

- `period=future` (predeterminado): `ends_at > ahora`, incluye reservas en curso.
- `period=past`: `ends_at <= ahora`.
- `period=all`: sin filtro temporal.
- `status=all` (predeterminado), `confirmed` o `cancelled`.

La clasificación temporal depende del intervalo original, incluso para reservas
canceladas. Sólo se muestran las reservas de la identidad autenticada.

`GET /bookings/42` devuelve una reserva propia.
`DELETE /bookings/42` no lleva cuerpo y responde **200** con el objeto completo,
`status: "cancelled"` y `cancelled_at` en UTC. La disponibilidad se libera antes
de responder. Repetir la cancelación devuelve el mismo resultado. Una reserva
confirmada que ya empezó responde 409. Un ID ajeno o inexistente responde 404.

## Errores

Formato uniforme, incluidos errores de validación, rutas inexistentes y JSON mal formado:

```json
{
  "error": {
    "code": "booking_conflict",
    "message": "La cancha ya está reservada en ese horario."
  }
}
```

Una validación de cuerpo puede incluir campos por ubicación:

```json
{
  "error": {
    "code": "validation_error",
    "message": "La solicitud contiene datos inválidos.",
    "details": {"json": {"duration_hours": ["Must be greater than or equal to 1 and less than or equal to 24."]}}
  }
}
```

Los mensajes de la librería pueden estar en inglés; `code` es estable para Flutter.

| HTTP | Códigos habituales | Tratamiento |
| --- | --- | --- |
| 400 | `validation_error` | JSON mal formado; corregir solicitud. |
| 401 | `authentication_required`, `invalid_token` | Obtener/renovar token; si persiste, iniciar sesión otra vez. |
| 404 | `not_found` | Recurso inexistente o reserva ajena. |
| 409 | `booking_conflict`, `court_unavailable`, `booking_started` | Refrescar disponibilidad o mostrar restricción de cancelación. |
| 413 | `request_entity_too_large` | Cuerpo mayor a 16 KiB. |
| 422 | `validation_error`, `invalid_datetime`, `invalid_hour`, `past_booking`, `past_date`, `outside_opening_hours` | Corregir fecha, horario o campos. |
| 503 | `auth_unavailable`, `database_unavailable` | Servicio/configuración no disponible; reintentar más tarde. |
| 500 | `internal_error` | Error inesperado; no se exponen credenciales ni SQL. |

No reintentar automáticamente un POST después de un error de red ambiguo: puede
haberse confirmado. Primero consultar las reservas propias. La API no implementa
claves de idempotencia; un segundo intento superpuesto confirmado recibe 409.

## Flutter (cliente implementado)

El cliente [ApiClient](../../lib/services/api_client.dart) implementa este contrato
con `http`, `firebase_core` y `firebase_auth`. La URL base se configura mediante
`API_BASE_URL`. Ejemplo orientativo de la operación subyacente:

```dart
final user = FirebaseAuth.instance.currentUser;
if (user == null) throw StateError('Se requiere iniciar sesión');
final token = await user.getIdToken();
final response = await http.post(
  Uri.parse('$apiBase/bookings'), // apiBase incluye /api/v1
  headers: {
    'Content-Type': 'application/json',
    'Authorization': 'Bearer $token',
  },
  body: jsonEncode({
    'court_id': selectedCourtId,
    // Usar el starts_at del slot elegido evita confundir la zona del teléfono con la sede.
    'starts_at': selectedSlotStartsAt,
    'duration_hours': 2,
  }),
);
```

Firebase maneja la renovación normal de tokens con `getIdToken()`. Ante 401 se
puede forzar una sola renovación con `getIdToken(true)`; si persiste, solicitar
inicio de sesión. No guardar ni registrar tokens en logs del cliente.
Deshabilitar el botón mientras se envía y manejar 409 consultando de nuevo.

En emulador Android, el host local suele ser `http://10.0.2.2:8000/api/v1`;
en dispositivo físico, usar la IP LAN de la computadora con Flask escuchando
en `0.0.0.0`. Para HTTP de desarrollo puede requerirse configuración de plataforma.
En producción usar HTTPS de Render. En Flutter Web, configurar `CORS_ORIGINS`
con el origen real, incluido el puerto de desarrollo. Para mostrar la hora de
la sede cuando difiere de la del teléfono, usar su zona IANA con una librería
de zonas horarias; `DateTime.toLocal()` usa la zona del teléfono.

## Dispositivos y FCM

- `POST /devices`, Bearer, JSON `{"token":"<token FCM real del dispositivo>"}`:
  200 `{"registered":true}`. Es idempotente y reasocia un dispositivo compartido
  al usuario autenticado actual. No acepta UID ni user_id del cliente.
- `DELETE /devices`, Bearer, mismo JSON: 200 `{"registered":false}`. Elimina
  únicamente el registro propio, sin revelar si pertenece a otra identidad.
- Token de 20–4096 caracteres sin espacios. No se devuelve ni registra en logs.
  Una huella SHA-256 sirve de índice único para no exceder el límite B-tree.
- Con `FCM_ENABLED=true`, después del commit de creación/cancelación se intenta
  enviar al propietario `type=booking_created|booking_cancelled`, `booking_id`
  y `recipient_uid` (UID Firebase firmado). Android usa el canal `bookings`.
  El texto visible es genérico; la app comprueba el destinatario y consulta
  los detalles mediante la ruta autenticada de reservas propias.
- Una cancelación repetida no repite el aviso. Tokens inválidos que FCM informa
  como `UnregisteredError` se eliminan. Fallas de Firebase se registran sólo
  por tipo y no cambian el éxito de la reserva.
- Envío best effort, síncrono y sin cola persistente: una caída del proceso
  después del commit puede perder un aviso. Cada llamada al SDK tiene timeout
  HTTP de 5 segundos; varios dispositivos agregan latencia. No hay recordatorios
  programados ni garantía de entrega. Las reservas se consultan siempre por API.
