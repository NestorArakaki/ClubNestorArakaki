# Verificación del backend ampliado

Base de trabajo: `origin/feat/backend-reservas` (`0711e9a`). Ver también la
[verificación integral](../../docs/VERIFICACION.md) y el
[despliegue actual en Render Free](../../docs/RENDER_FREE.md).

Se ejecutó en Linux Cloud con Python 3.12.14 y PostgreSQL 16 local descartable:

- **80 pruebas aprobadas, 97% de cobertura**, incluidas las pruebas originales
  de reservas y concurrencia. No se usó SQLite.
- Superposiciones parciales/totales, exclusión GiST, intervalos adyacentes y
  canchas distintas. Solicitudes simultáneas con clientes/conexiones independientes:
  una reserva se confirma y la otra responde 409.
- Cancelación, liberación de turnos, propiedad, reservas iniciadas e idempotencia.
- Perfil, email de sólo lectura, fechas/horas inválidas y autenticación:
  token ausente, inválido, expirado, revocado, usuario deshabilitado y SDK caído.
- Dispositivos FCM: registro idempotente, token largo con índice hash,
  reasignación al cambiar de cuenta y baja restringida al propietario.
- Push: envío únicamente al propietario, fallo que no revierte la reserva,
  eliminación de tokens no registrados y ausencia de avisos al repetir cancelación.
- Credenciales mediante JSON privado de entorno; el SDK se sustituye sólo en tests.
- Arranque: una migración o precarga fallida impide ejecutar Gunicorn.
- OpenAPI validado por `openapi-spec-validator`; Swagger y recursos locales.
- Migraciones: `downgrade base` → `upgrade`, exclusivamente en base de pruebas;
  `db check` sin cambios pendientes. Se agregó la revisión `1002_devices`.
- Dos ejecuciones de precarga idempotente conservaron dos sedes demo.
- Arranque HTTP real mediante `sh scripts/start.sh`: migraciones, seed opcional,
  Gunicorn; salud, sedes, canchas, Swagger y OpenAPI devolvieron 200.
- Ruff análisis/formato, `pip check` y comprobación de whitespace de Git.

## Comprobaciones externas pendientes

1. **Firebase real**: configurar proyecto y cuenta de servicio, verificar ID tokens
   reales con revocación y estado de usuario, y entrega de notificaciones FCM.
   Los tests ejercitan el adaptador y `check_revoked=True`; no prueban firma o red
   contra un proyecto Firebase real.
2. **Render Free**: crear ambos servicios Free, configurar variables, comprobar
   permiso CREATE/`btree_gist`, arranque con Alembic y salud HTTPS. No se crearon
   recursos remotos. El script reemplaza el pre-deploy y no necesita Render Shell.
3. **Android**: ejecutar la [checklist de demo](../../docs/DEMO.md) con Firebase
   configurado y comprobar el flujo completo en emulador/dispositivo.
Los workflows remotos de [Backend](https://github.com/NestorArakaki/ClubNestorArakaki/actions/runs/39132875111)
y [Flutter](https://github.com/NestorArakaki/ClubNestorArakaki/actions/runs/39132875080)
terminaron con éxito en `8cc3eab`; Flutter incluye compilación del APK debug sin credenciales.

Límites: una apertura por día, sin feriados, administración, pagos ni idempotency
keys. Los avisos se intentan después del commit, sin cola persistente y sin
garantía de entrega. El contrato explica cómo manejar respuestas de red ambiguas.
