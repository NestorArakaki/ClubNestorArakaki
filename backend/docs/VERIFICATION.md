# Verificación de la implementación

Los apartados iniciales registran la rama base del backend. Para los resultados
de la ampliación actual, ver la sección final y [la verificación integral](../../docs/VERIFICACION.md).

Comprobaciones ejecutadas en esta tarea con Python 3.12.14 y PostgreSQL 16 en un
contenedor local descartable. No se usó SQLite ni credenciales Firebase reales.

## Ejecutado

- Suite `pytest` sobre PostgreSQL: **69 pruebas aprobadas, 97% de cobertura**.
  Incluye superposiciones parciales/totales, inserción directa que viola la
  exclusión, reservas consecutivas y canchas distintas.
- Solicitudes concurrentes con clientes/conexiones independientes y una barrera
  antes de insertar: una responde 201 y la otra 409; queda una sola reserva.
  Se probó con usuarios diferentes y con el mismo usuario.
- Cancelación, liberación del turno, intento de cancelar reservas ajenas o
  iniciadas, y cancelaciones simultáneas idempotentes.
- Perfil propio, email de sólo lectura, fechas/horarios inválidos, autenticación
  ausente, token rechazado/expirado/revocado, usuario deshabilitado y falla del SDK.
- OpenAPI validado con `openapi-spec-validator`; Swagger y sus recursos locales
  responden correctamente. Los endpoints privados declaran autenticación Bearer.
- Migraciones: base vacía → `upgrade`; luego `downgrade base` → `upgrade`, usando
  exclusivamente la base de pruebas. `db check` no detectó cambios pendientes.
- Precarga idempotente; dos ejecuciones conservaron dos sedes y cinco canchas demo.
- Instalación de `requirements.txt` en un segundo entorno virtual limpio;
  `pip check` sin conflictos.
- Arranque HTTP real con Gunicorn, dos workers y cuatro threads, utilizando sólo
  dependencias de producción: salud, sedes, canchas, `/docs`, `/openapi.json` y
  recursos Swagger respondieron 200. El proceso de comprobación fue detenido.
- Ruff (análisis y formato) y comprobación de whitespace de Git.

## Pendiente de verificar con servicios del proyecto

1. **Firebase real**: configurar el ID del proyecto y la cuenta de servicio con
   permisos de lectura de usuarios. Obtener un ID token desde Flutter/Firebase
   Auth; comprobar `/me`, crear/cancelar una reserva, y verificar que un token de
   otro proyecto, revocado o de un usuario deshabilitado sea rechazado. Las pruebas
   locales sustituyen el límite del SDK; no prueban firma ni red contra Firebase.
2. **Render**: crear los servicios y montar el Secret File siguiendo el README.
   No se desplegó ni se crearon recursos pagos. Verificar permisos para
   `btree_gist`, la migración previa al deploy y salud/autenticación en HTTPS.
3. **Flutter**: la ampliación ya integra el cliente; queda probar Firebase real
   y el flujo completo en un emulador/dispositivo del usuario.
4. **GitHub Actions**: el workflow se incluye para repetir las pruebas en cada
   cambio del backend; su ejecución remota depende de GitHub y de las opciones
   habilitadas en el repositorio. Los resultados locales no afirman un CI remoto exitoso.

## Alcance funcional

Una franja de apertura por día de la semana, sin feriados ni excepciones por
fecha; reservas en bloques de horas enteras, sin pagos, precios, administración
visual o claves de idempotencia. Para un cambio de turno se cancela y se reserva
otro sujeto a disponibilidad. Una falla de red después de enviar un POST requiere
consultar las reservas propias antes de reintentar. Estos límites se documentan
también en el contrato para el cliente.

## Ampliación Flutter/FCM y Render Free

Esta ampliación parte de `origin/feat/backend-reservas` (`0711e9a`).
La suite actual sobre PostgreSQL 16 ejecutó **80 pruebas: 80 aprobadas**,
con **97% de cobertura**. Incluye registro idempotente y reasignación de dispositivos,
borrado restringido al propietario, validaciones y tokens largos, envío al
propietario, limpieza de tokens inválidos, cancelación sin avisos duplicados,
fallo push sin perder reserva, credenciales JSON y arranque bloqueado ante error
de migración/seed. El SDK Firebase se sustituye únicamente en pruebas.
Los resultados anteriores de 69 tests corresponden a la rama base.

El despliegue actual utiliza Free y `sh scripts/start.sh`; ya no usa pre-deploy
ni Render Shell. Consultar la guía raíz para los resultados completos y pasos externos.
