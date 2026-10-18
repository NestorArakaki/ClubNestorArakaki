# Verificación integral

Rama: `feat/flutter-firebase-free-render`, creada desde
`origin/feat/backend-reservas`, commit `0711e9a7e14f71955fc5393c303ce6c7885e9e7c`.
Se obtuvieron las referencias remotas y se comprobaron `backend/` y
`backend/docs/API.md` antes de modificar archivos. No se partió de `main`.

## Comprobaciones ejecutadas

Entorno: Linux Cloud, Flutter 3.47.7 / Dart 3.13.5, Python 3.12.14 y PostgreSQL 16
local descartable en Docker. No se usó SQLite ni credenciales Firebase reales.

| Comprobación | Resultado |
| --- | --- |
| `flutter pub get` | Dependencias resueltas y `pubspec.lock` actualizado |
| `flutter analyze` | Sin observaciones |
| `flutter test` | 24 pruebas aprobadas |
| Formato Dart | `dart format lib test` aplicado |
| `pytest --cov=app --cov-report=term-missing` | 80 pruebas aprobadas, 97% cobertura |
| Ruff análisis y formato | Sin observaciones |
| `pip check` | Sin dependencias rotas |
| Alembic | `downgrade base` → `upgrade` correcto, sólo en base descartable |
| `flask --app wsgi db check` | Sin operaciones pendientes |
| Precarga | Dos ejecuciones correctas; se conservan dos sedes demo |
| Arranque `sh scripts/start.sh` | Migración → seed opcional → Gunicorn real |
| HTTP real sobre Gunicorn | Salud, sedes, canchas, Swagger y OpenAPI: 200 |
| OpenAPI | Incluye los endpoints autenticados de dispositivos; validado por pytest |
| Git | Sin errores de whitespace |

Las pruebas Flutter cubren validación de login/registro/recuperación, navegación
según sesión, cierre de sesión, perfil, paginación, parseo UTF-8 y JSON, catálogo,
horarios, disponibilidad, horas contiguas, conversión a zona de la sede,
Bearer/renovación única ante 401, errores HTTP 400/404/409/422/500/503, timeout y
red, reserva exitosa, conflicto con recarga, respuesta perdida sin repetir POST,
confirmación de cancelación, historial, campos de perfil y tokens FCM.
Usan `AuthService` y `MockClient` de prueba; producción usa Firebase Auth real.

El backend incluye las pruebas originales de concurrencia/superposición y nuevas
pruebas de dispositivos, propiedad, reasignación idempotente, token largo,
notificación al propietario, cancelación sin duplicar avisos, fallo push sin perder
reserva y limpieza de token inválido. Los tests del script de inicio comprueban
que una migración o seed fallidos impiden llegar a Gunicorn. En Windows sin `sh`,
sólo esos cuatro casos POSIX se omiten con una razón explícita; usar Git Bash/WSL
para ejecutarlos. La suite completa de 80 casos se ejecutó aquí en Linux.

## Pendientes de servicios externos

- Crear/configurar Firebase, registrar `com.nestorarakaki.club`, habilitar
  Email/Password, completar configuración cliente y cuenta Admin. Probar login,
  persistencia y token real contra la API del mismo proyecto.
- Verificar push real en primer plano, segundo plano, arranque al tocar aviso,
  permiso denegado/concedido y rotación de token con Google Play Services.
- Crear y desplegar los recursos **Free** de Render. Verificar `btree_gist`,
  variables, salud HTTPS, cold start y vencimiento de PostgreSQL.
- Ejecutar la checklist de [demostración](DEMO.md) en el emulador Windows.
- Ejecutar GitHub Actions remoto. Se agregaron workflows, pero un resultado local
  no se presenta como una ejecución exitosa de GitHub.
- Firma propia para distribución por tienda (la demo conserva firma debug).

## Límites del alcance

Una franja de apertura por día, sin excepciones de feriados, pagos ni interfaz
administrativa. Las reservas y cancelaciones se rigen por las reglas de la API.
No hay claves de idempotencia para POST; ante respuesta perdida hay que consultar
Mis reservas. El cliente bloquea el intento incierto en la pantalla de reserva.
Los avisos son best effort después del commit, sin cola persistente ni
recordatorios programados. Una caída posterior al commit puede perder un aviso.
Las credenciales, permisos externos y la entrega de FCM real no fueron simulados
ni se afirman verificados sin configuración del proyecto.
