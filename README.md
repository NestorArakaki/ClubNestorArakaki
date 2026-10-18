# ClubNestorArakaki

Aplicación Android de reservas deportivas: Flutter, Firebase Authentication,
Firebase Cloud Messaging, Flask y PostgreSQL. Incluye sedes/canchas, disponibilidad
real, reservas de horas consecutivas, cancelación, historial y perfil.
No incluye administración, pagos ni datos simulados en Flutter.

La rama `feat/flutter-firebase-free-render` parte de `feat/backend-reservas`
(commit base `0711e9a`). El PR de esta implementación debe integrarse después
del PR #1 del backend; su base de revisión es `feat/backend-reservas`.

- [Instalación completa en Windows 11 / PowerShell](docs/INSTALACION_WINDOWS.md)
- [Contrato REST](backend/docs/API.md)
- [Backend local, reglas y pruebas](backend/README.md)
- [Despliegue Render Free](docs/RENDER_FREE.md)
- [Verificación y límites](docs/VERIFICACION.md)
- [Checklist para la demostración](docs/DEMO.md)

## Inicio rápido (PowerShell, desde la raíz)

Primero crear el proyecto Firebase y registrar Android con el ID definitivo
`com.nestorarakaki.club`, siguiendo la guía. El mismo proyecto se usa en Android
y en Firebase Admin del backend. No se incluyen credenciales de cuentas de servicio.

```powershell
flutter pub get
Copy-Item config/firebase.example.json config/firebase.json
# Completar config/firebase.json con la configuración CLIENTE de Firebase.
flutter analyze
flutter test
flutter devices
flutter run --dart-define-from-file=config/firebase.json
```

`API_BASE_URL` incluye `/api/v1`; local en emulador Android:
`http://10.0.2.2:8000/api/v1`. Para Render, cambiar ese único valor a
`https://TU-SERVICIO.onrender.com/api/v1` y volver a ejecutar Flutter.
Si falta configuración Firebase, la app muestra instrucciones en pantalla.
HTTP está permitido sólo en variantes debug/profile; una compilación release
requiere API HTTPS. Se mantiene firma debug para demos; configurar una firma
propia antes de publicar en Play Store.

## Organización

`lib/services/`: autenticación Firebase real, cliente REST, notificaciones y zonas
horarias. `lib/models/`: parseo del contrato. `lib/screens/`: formularios y flujos.
`lib/widgets/`: carga/error/reintento y confirmaciones. Los dobles de Firebase/API
existen únicamente en `test/`, nunca como modo de ejecución de la aplicación.

El envío push es best effort: una falla de notificación no revierte una reserva,
y Mis reservas es la fuente para comprobar el resultado si se pierde la conexión.
La activación real requiere configuración y permisos externos; ver las guías.
