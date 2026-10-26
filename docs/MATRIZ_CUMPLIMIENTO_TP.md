# Auditoría contra Trabajo Práctico 2026

Fuente principal: `Trabajo Práctico_2026.docx` adjunto por el alumno, leído completo
antes de modificar código. El texto del pedido del alumno orienta esta auditoría;
la consigna fija los requisitos académicos. Fecha: 18/10/2026.

**Código** indica implementación y pruebas locales; **externo** indica configuración
o demostración que exige las cuentas/dispositivo del alumno. No se declara una
aplicación desplegada o una notificación real entregada sin haberlo comprobado.

| Requisito de la consigna | Estado actual | Evidencia / ubicación |
| --- | --- | --- |
| Reservar desde el celular con Flutter | Código; demo externa pendiente | `lib/screens/availability_screen.dart`, cliente REST. |
| Registro por email/contraseña | Código; Firebase real pendiente | `auth_service.dart`, `auth_screen.dart`; sin autenticación ficticia en producción. |
| Login y Home Page posterior | Código | `app.dart` escucha sesión y muestra `HomeScreen` con sedes. |
| Recuperación segura de contraseña | Código; correo real pendiente | `FirebaseAuth.sendPasswordResetEmail`. |
| Nombre, apellido y nacimiento en perfil editable | Código | `profile_screen.dart`, GET/PATCH `/me`, pruebas de validación. |
| Email visible y no editable | Código | Campo readOnly y schema PATCH que rechaza email. |
| Cerrar sesión | Código | `HomeScreen._logout`; desvincula FCM e invalida navegación anterior. |
| Sedes con nombre, dirección y horarios | Código | `Venue`, `OpeningHour`, endpoints públicos y `VenueScreen`. Los horarios se ven al seleccionar la sede. |
| Listar sedes y consultar sus espacios/turnos | Código | `venues_screen.dart`, GET `/venues/{id}/courts`, disponibilidad. |
| Cada espacio asociado a una sede, con tipo | Código | FK `Court.venue_id`, `sport`; la lista muestra también la sede. |
| Nombre compuesto sede/dirección/tipo/número | Corregido | `Court.full_name` y `CourtSchema.name`; se deriva en backend, no en Flutter. |
| Filtrar espacios por tipo de deporte | Corregido | Dropdown dinámico en `VenueScreen`; sólo tipos recibidos de API, test de filtro. |
| Disponibilidad por sede, espacio y fecha | Código | Selección de sede → cancha → fecha, `services.availability`. |
| Inicio y fin, mínimo una hora, horas enteras | Código | Slots horarios y duración 1–24, Marshmallow y CHECK PostgreSQL. |
| Inicio futuro | Código | API valida contra reloj actual; slots pasados deshabilitados. |
| Encaje en apertura y fin no posterior al cierre | Código | `opening_window`, `create_booking`, pruebas de cierre exacto. |
| No superponer y validar desde backend | Código | Validación de reglas + exclusión GiST atómica, tests concurrentes 201/409. |
| Listar reservas propias con sede/espacio/fecha/hora | Código | GET `/bookings`, `bookingInfo` une referencias, `bookings_screen.dart`. |
| Historial con reservas finalizadas | Código | `period=past` usa fin; no depende de que la reserva se haya cancelado. |
| Cancelar y liberar horario | Corregido límite extra | Marca cancelación y libera exclusión; ahora permite también en curso, hasta su fin. |
| Push sobre reservas próximas | Corregido código; activar externo | Workflow cada 10 minutos, endpoint protegido, marca persistente, FCM y recepción `booking_reminder`. Ver `RECORDATORIOS.md`. |
| Errores de red/servidor/login/usuario existente | Código | ApiException, errores Firebase comprensibles, estados de carga/vacío/reintento. |
| Nombre Club + nombre y apellido | Código | `ClubNestorArakaki`, manifiesto, MaterialApp y README. Se usa la identidad indicada por el alumno. |
| Repositorio del mismo nombre y cuenta propia/commits | Repositorio y commits comprobados | `NestorArakaki/ClubNestorArakaki`; el alumno debe poder explicar el historial y la autoría de su entrega. |
| Diseño UX/UI y prototipo navegable en Figma | Referencia accesible; defensa manual | Archivo Figma del pedido: se observó la estructura de pantallas, sin modificarlo. No se certificó el cableado del prototipo ni su entrega en Blackboard. |
| API REST Swagger/OpenAPI | Código y pruebas | `/docs`, `/openapi.json`, validación de spec. Incluye seguridad de usuario y de scheduler separadas. |
| Base relacional | Código y pruebas PostgreSQL 16 | Se usa PostgreSQL real, no SQLite como reemplazo en tests. |
| API y base disponibles en la nube | Externo pendiente | Blueprint Free preparado; crear/configurar/desplegar con cuenta del alumno. |
| Usuario autenticado en operaciones privadas | Código | ID Token verificado, revocación y estado; propietario tomado del token. |
| README móvil y backend | Documentado | README raíz, `backend/README.md`, guías enlazadas de Windows y Render. |
| Ícono móvil | Corregido | Ícono propio de cancha vectorial y adaptativo, manifiesto `@mipmap/club_icon`. Revisar apariencia en Pixel 7. |
| Modelo con entidades, atributos y relaciones | Entregado | `MODELO_DATOS.md`, diagrama ER y explicación del esquema real. |
| Mostrar funcionando en emulador | Externo pendiente | Ejecutar checklist con Pixel 7/Android 16, Firebase y API reales. |
| Dos ZIP de código antes de exposición | Preparación automatizada | `tools/package_tp.py`; guía `ENTREGA_TP.md`. Blackboard y fecha los gestiona el alumno. |
| Entrega 1 grupal / Entrega 2 individual y defensa | Manual académico | Conservar Figma del grupo; estudiar `GUIA_DEFENSA_TP.md` y presentar individualmente. |

## Brechas y correcciones mínimas

Antes había avisos al crear/cancelar pero no un reloj externo que enviara avisos
antes del turno. Se agregó el workflow gratuito y una sola columna nullable;
no un segundo servidor. El filtro usa la lista ya descargada por sede, sin nuevo
endpoint ni dependencia. El nombre compuesto se deriva para conservar IDs,
reservas y precargas existentes. Se sustituyó la referencia al ícono Flutter de
plantilla por un recurso vectorial Android propio.

El límite anterior impedía cancelar al comenzar el turno, aunque el TP no impone
ese corte. Se cambió a `ends_at`: se permite cancelar una reserva propia futura
o en curso; las ya finalizadas siguen en historial. Se conservaron la propiedad,
la idempotencia, la exclusión y la validación de fechas.

## Simplificación y alcance

No se encontró motivo para reescribir la arquitectura. Es un cliente Flutter y
una API Flask con PostgreSQL; Firebase resuelve identidad y push. `AuthService`
permite probar login sin credenciales reales; `ApiClient` evita repetir HTTP en
pantallas; `AsyncView` concentra carga/error/reintento. Estas piezas tienen una
función concreta y se conservan.

Se reutilizó el envío FCM para el recordatorio y los avisos existentes, sin agregar
dependencias de ejecución. No se copiaron los precios, valoraciones ni variantes
visuales que aparecen en Figma porque no forman parte del TP. No hay módulos
administrativos. Los campos `active` y los índices existentes se conservaron:
retirarlos no simplifica un flujo y puede romper historial o consistencia.

Limitaciones que no se ocultan: apertura única por día, sin feriados; aviso best
effort sin garantía de lectura; scheduler con retrasos; PostgreSQL Free temporal.
La duración máxima 24 horas coincide con el máximo que cabe en una apertura diaria,
no limita un turno válido de este modelo. El nombre compuesto usa ID global como
número; la consigna no exige reiniciar numeración por sede/tipo.
