# Windows 11 y PowerShell: configuración y ejecución

Tu Flutter 3.47.7, Dart 3.13.5, SDK API 36 y NDK 28.2.13676358 ya funcionan.
No reinstalar ni actualizar herramientas por esta auditoría. Los pasos de instalación
sólo aplican a una máquina nueva; en tu PC continuar con Firebase/backend.
Ver [COMPATIBILIDAD.md](COMPATIBILIDAD.md).

Comandos desde la raíz del repositorio, salvo indicación contraria. Se verificó
el código con Flutter 3.47.7 / Dart 3.13.5 y Python 3.12.14. Android Studio debe
tener instalado un SDK Android compatible con `flutter doctor` y un emulador
con **Google Play / Google APIs** para FCM. No hace falta Firestore.

## 1. Preparar herramientas y dependencias

```powershell
flutter --version
flutter doctor
flutter doctor --android-licenses
flutter pub get
flutter analyze
flutter test
flutter emulators
# Reemplazar por el ID que devuelve el comando anterior.
flutter emulators --launch ID_DEL_EMULADOR
flutter devices
```

Si PowerShell bloquea scripts de activación Python, se puede usar siempre
`.venv\Scripts\python.exe` sin cambiar la política global. Para FlutterFire CLI,
si no se encuentra el comando, agregar `%LOCALAPPDATA%\Pub\Cache\bin` al PATH
(o la ruta de caché que use tu instalación).

## 2. Crear Firebase Authentication y registrar Android

1. Crear un proyecto en [Firebase Console](https://console.firebase.google.com/).
   Elegir el plan Spark gratuito; no se necesita habilitar facturación para Auth
   email/contraseña y FCM en este proyecto. Analytics es opcional.
2. Authentication → Comenzar → Proveedores → Email/Password → habilitar y guardar.
   La política de contraseñas de Firebase puede ser más estricta que el mínimo
   de 6 caracteres del formulario; la app mostrará los errores del proveedor.
3. Configuración del proyecto → Tus apps → Agregar Android. Usar exactamente
   **`com.nestorarakaki.club`**, igual a namespace, applicationId y MainActivity.
   No registrar el antiguo `com.example.club_app`.
4. Descargar `google-services.json` a `android/app/google-services.json`. Está
   excluido de Git. No sustituirlo por el JSON privado de Firebase Admin.
5. Las claves SHA no son necesarias para email/contraseña básico. Si Firebase
   exige verificación adicional o se agregan proveedores, registrar las huellas
   de la firma utilizada según la consola.

El plugin Google Services ya está declarado y sólo se aplica si existe el JSON;
Se usa Google Services 4.5.0, recomendado en la [guía oficial](https://firebase.google.com/docs/android/setup).
Por eso `flutter analyze` y `flutter test` no dependen de configuraciones privadas.
Android mínimo: API 24 o el mínimo superior requerido por Flutter.

## 3. FlutterFire y configuración cliente

Instalar Firebase CLI con Node.js LTS y configurar FlutterFire:

```powershell
npm install -g firebase-tools
firebase login
dart pub global activate flutterfire_cli
flutterfire configure --project=TU_PROJECT_ID --platforms=android --android-package-name=com.nestorarakaki.club
Copy-Item config/firebase.example.json config/firebase.json
```

`flutterfire configure` registra/verifica la aplicación y genera, entre otros,
`lib/firebase_options.dart`. Esta implementación **no lo importa** para que el
análisis funcione antes de crear Firebase. La inicialización usa la configuración
nativa de `google-services.json` si los cuatro valores FIREBASE_* están vacíos,
o `FirebaseOptions` explícitas si se completan todos en `config/firebase.json`.
No es necesario modificar Dart tras ejecutar FlutterFire.

Para que el arranque y el isolate FCM usen configuración explícita, completar
`config/firebase.json` con los valores Android reales de `firebase_options.dart`
o de la configuración cliente del proyecto:

| Clave local | Valor cliente Firebase |
| --- | --- |
| `FIREBASE_API_KEY` | `apiKey` (cliente; no clave privada) |
| `FIREBASE_APP_ID` | `appId` Android, formato `1:...:android:...` |
| `FIREBASE_MESSAGING_SENDER_ID` | `messagingSenderId` / número del proyecto |
| `FIREBASE_PROJECT_ID` | `projectId` |
| `API_BASE_URL` | URL Flask completa, incluida `/api/v1` |

Dejar los cuatro valores vacíos también es válido si el JSON Android está
instalado y se compila con Google Services. Evitar valores parciales o de otro
proyecto. Este archivo sólo contiene configuración cliente; **nunca** poner
`private_key`, `client_email`, JSON de servicio o tokens de usuario en Flutter.
No se inventan IDs en el archivo de ejemplo.

## 4. Backend local y PostgreSQL

Instalar Python 3.12 y Docker Desktop (motor Linux) o PostgreSQL 16. Docker Desktop
debe estar abierto. Estos comandos crean únicamente la base local de Compose:

```powershell
Set-Location backend
py -3.12 -m venv .venv
.venv\Scripts\python.exe -m pip install -r requirements.txt
Copy-Item .env.example .env
docker compose up -d --wait db
```

Editar `backend/.env`: `DATABASE_URL` ya coincide con Compose. Completar
`FIREBASE_PROJECT_ID` y `GOOGLE_APPLICATION_CREDENTIALS` con la ruta al JSON privado
obtenido en Firebase → Configuración → Cuentas de servicio → Generar clave privada.
Usar una ruta con `/`, por ejemplo `C:/Users/TU_USUARIO/secrets/firebase-admin.json`.
Guardar el archivo fuera del repositorio. La cuenta requiere lectura de usuarios
(`firebaseauth.users.get`) y, para push, envío FCM (`cloudmessaging.messages.create`,
por ejemplo el rol Firebase Cloud Messaging API Admin). No desactivar la
verificación de revocación ni usar Firebase Auth Emulator con este backend.

```powershell
.venv\Scripts\python.exe -m flask --app wsgi db upgrade
# seed_data.json contiene datos DEMO, no sedes reales.
.venv\Scripts\python.exe -m flask --app wsgi seed --file seed_data.json
.venv\Scripts\python.exe -m flask --app wsgi run --host 0.0.0.0 --port 8000
```

Dejar esa terminal abierta. En otra, desde la raíz:

```powershell
Invoke-RestMethod http://localhost:8000/api/v1/health
flutter run --dart-define-from-file=config/firebase.json
```

Usar `API_BASE_URL=http://10.0.2.2:8000/api/v1` en el JSON para el emulador Android
estándar. Un teléfono físico usa la IP LAN de Windows (ver `ipconfig`); habilitar
el puerto local en Firewall sólo en una red de confianza. `localhost` en Android
es el propio dispositivo. Para release, usar HTTPS de Render.

## 5. Activar notificaciones reales

1. Usar el mismo proyecto Firebase que Auth y habilitar Firebase Cloud Messaging
   API (HTTP v1) en la consola de Google Cloud si aún no está habilitada.
2. Verificar los permisos FCM de la cuenta de servicio del backend. No usar
   la server key del protocolo legacy ni introducir credenciales privadas en Dart.
3. Configurar `FCM_ENABLED=true` en `.env` del backend (reiniciar Flask), o como
   variable privada del servicio Render (redeploy).
4. Iniciar sesión en la app y tocar **Activar avisos**. En Android 13+ aceptar
   el permiso. Si se deniega permanentemente, habilitarlo en Ajustes → Apps →
   ClubNestorArakaki → Notificaciones y volver a tocar el botón.
5. El token real se obtiene por Firebase Messaging y se registra con Bearer en
   `/api/v1/devices`. Una rotación del token y el regreso al primer plano vuelven
   a sincronizarlo. No se imprime ni se copia manualmente a la API.
6. Crear una reserva: se muestra un aviso local en primer plano; Android presenta
   el push del sistema en segundo plano. Tocar un aviso abre la reserva propia.
   También se procesa el aviso que inicia la app cerrada. `recipient_uid` impide
   abrir los detalles bajo otra cuenta, y el backend vuelve a verificar propiedad.
7. Cancelar una reserva futura: se envía otro aviso. Repetir la cancelación no
   duplica el aviso. Al cerrar sesión se intenta desvincular e invalidar el token
   y se limpian los avisos locales; una caída de red puede dejar un registro viejo
   que se limpia cuando Firebase lo declare inválido. El contenido visible es genérico.

No forzar la detención de la app en Ajustes para probar segundo plano: Android
puede impedir mensajes hasta que vuelva a abrirse. Para la demo, usar Inicio o
Recientes. El envío es best effort y una reserva confirmada sigue siendo válida
aunque falle FCM. Para los recordatorios de reservas próximas, activar el
workflow siguiendo [RECORDATORIOS.md](RECORDATORIOS.md); no requiere otra
instalación Android ni una cola persistente.

## 6. Usar Render y compilar Android

Seguir [RENDER_FREE.md](RENDER_FREE.md), cambiar `API_BASE_URL` en el JSON a
`https://TU-SERVICIO.onrender.com/api/v1`, y ejecutar:

```powershell
flutter clean
flutter pub get
flutter run --dart-define-from-file=config/firebase.json
# APK demo release (requiere URL HTTPS; firma debug por ahora):
flutter build apk --release --dart-define-from-file=config/firebase.json
```

No hace falta `flutter clean` cada vez; se indica al cambiar configuración nativa
Firebase. Cambiar `--dart-define` requiere reiniciar la app, no sólo hot reload.
No se verificó un APK firmado para distribución en tienda; requiere keystore propio.

## 7. Pruebas backend en Windows

```powershell
Set-Location backend
.venv\Scripts\python.exe -m pip install -r requirements-dev.txt
docker compose --profile test up -d --wait test-db
$env:TEST_DATABASE_URL = 'postgresql+psycopg://club:club_local@localhost:5433/club_test'
.venv\Scripts\python.exe -m pytest --cov=app --cov-report=term-missing
.venv\Scripts\python.exe -m ruff check app tests migrations wsgi.py
.venv\Scripts\python.exe -m ruff format --check app tests migrations wsgi.py
```

Los cuatro casos POSIX del arranque se omiten con un mensaje si no se encuentra
`sh`. Ejecutarlos en Git Bash/WSL para repetir la suite completa.

Las pruebas truncan **sólo** la base descartable terminada en `_test`. Nunca usar
una base real para `TEST_DATABASE_URL`. Los tests del script POSIX de Render
requieren `sh` (Git for Windows/WSL); la API y las demás pruebas usan Python.
