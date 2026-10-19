# Verificación integral y auditoría académica

La rama de trabajo sigue siendo `feat/flutter-firebase-free-render`, basada en
`origin/feat/backend-reservas` (`0711e9a`). Se leyó completa la consigna adjunta
antes de esta auditoría. Ver [matriz](MATRIZ_CUMPLIMIENTO_TP.md) y
[guía de defensa](GUIA_DEFENSA_TP.md) para el alcance académico.

## Resultado local actual

Linux Cloud, Flutter 3.47.7 / Dart 3.13.5, Python 3.12.14 y PostgreSQL 16 real
local descartable. No se usó SQLite ni credenciales Firebase reales.

| Comprobación ejecutada | Resultado |
| --- | --- |
| `flutter pub get` (implementación previa, dependencias sin cambios en auditoría) | Correcto, lockfile conservado |
| `flutter analyze` | Sin observaciones |
| `flutter test` | **27 pruebas aprobadas** |
| Formato Dart | Sin diferencias |
| `pytest --cov=app --cov-report=term-missing` | **85 pruebas aprobadas, 96% cobertura** |
| Ruff análisis/formato | Correcto |
| `flask --app wsgi db check` | Sin cambios pendientes |
| Migración 1003 | Upgrade real; downgrade a 1002 → upgrade correcto en base descartable |
| `pip check` (implementación previa, dependencias Python sin cambios) | Correcto |
| Git | Whitespace verificado |
| CI Backend actual (`4cadd6c`) | Éxito |
| CI Flutter actual (`4cadd6c`) | Éxito, incluido APK debug con ícono propio |

Las cinco pruebas backend nuevas comprueban la clave independiente del scheduler,
ventana temporal, exclusión de canceladas/pasadas/lejanas, repetición normal sin
duplicar, TTL, reintento ante fallo FCM, concurrencia real de dos peticiones y
nombre académico de cancha. La prueba existente de cancelación ahora exige que
una reserva en curso pueda cancelarse, conservando el rechazo a finalizadas.
Los nuevos casos Flutter comprueban filtro por deporte, destino de recordatorio
y cancelación en curso. Se conservaron los tests de auth, perfil, errores,
paginación, disponibilidad, creación, pérdida de respuesta y cancelación.

El SDK se sustituye **sólo en las pruebas**. Se emitieron ocho advertencias de
deprecación `Message.token` del Firebase Admin fijado, sin pruebas fallidas.
FCM aceptado por un doble no se presenta como un mensaje entregado a un teléfono.

## Evidencia de la implementación anterior

[Backend CI](https://github.com/NestorArakaki/ClubNestorArakaki/actions/runs/39132875111)
y [Flutter CI](https://github.com/NestorArakaki/ClubNestorArakaki/actions/runs/39132875080)
aprobaron el commit funcional anterior `8cc3eab`, incluido APK debug sin configuración
Firebase real. Para el commit actual de código `4cadd6c`, ambos workflows también terminaron
con éxito: [Backend](https://github.com/NestorArakaki/ClubNestorArakaki/actions/runs/39134442623)
y [Flutter](https://github.com/NestorArakaki/ClubNestorArakaki/actions/runs/39134442583).
El último incluye `flutter build apk --debug`, con el nuevo ícono y las
correcciones de la auditoría. No incluye activación de Firebase/Render reales.

En la implementación anterior también se ejecutaron migraciones desde base vacía,
precarga dos veces, arranque real con el script de Render/Gunicorn y salud,
sedes, canchas, Swagger/OpenAPI con HTTP 200. Los intentos locales de APK tuvieron
límites de memoria y espacio al instalar NDK; las herramientas Cloud se movieron
al disco de trabajo. Son independientes de las herramientas ya instaladas en Windows.

## Verificaciones personales pendientes

- Configurar Firebase del mismo proyecto en Android/Admin y probar registro,
  persistencia, recuperación de contraseña y verificación real de tokens.
- Desplegar API/PostgreSQL en Render **Free**, comprobar `btree_gist`, migración,
  seed, salud HTTPS y vigencia de la base.
- Registrar un token FCM real en Pixel 7/Android 16, conceder permisos y comprobar
  primer plano, segundo plano y apertura al tocar aviso.
- Configurar la clave y las variables del workflow; colocarlo en la rama
  predeterminada al integrar los PR. Mientras tanto, probar endpoint manualmente.
- Comprobar entrega real del recordatorio de una reserva dentro de la próxima
  hora, repetición sin reenvío normal y exclusión de una reserva cancelada.
- Revisar apariencia del ícono, el prototipo navegable Figma y ejecutar DEMO.md.
- Preparar los ZIP, subirlos a Blackboard y realizar la defensa individual.

No se crearon servicios remotos, no se activó un cron real con secretos, no se
fusionaron PR y no se afirma que la consigna esté cumplida en la nube hasta
completar esas comprobaciones. Los límites de recordatorios y planes gratuitos
están detallados en RECORDATORIOS.md y RENDER_FREE.md.
