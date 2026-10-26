# Compatibilidad con la computadora del alumno

No se cambiaron versiones de herramientas durante la auditoría académica.
Se mantiene la combinación que ya compiló el APK en CI. El entorno Cloud tiene
sus propias rutas y no modifica `C:\Android\Sdk` ni las herramientas de Windows.

| Herramienta/configuración | Proyecto y verificación | Entorno indicado por el alumno |
| --- | --- | --- |
| Flutter | 3.47.7 estable, fijado en CI | 3.47.7: coincide |
| Dart | 3.13.5, `pubspec.yaml` | 3.13.5: coincide |
| Android compile/target | API 36, heredado de Flutter 3.47.7 | API 36: coincide |
| NDK | 28.2.13676358, `flutter.ndkVersion` | Misma versión |
| SDK mínimo de la app | API 24 | Pixel 7 con Android 16/API 36 lo supera |
| Android Gradle Plugin | 9.1.0 en settings.gradle.kts | Lo descarga Gradle; no instalar otro manualmente |
| Gradle Wrapper | 9.3.1 en gradle-wrapper.properties | Usa el wrapper del proyecto, no Gradle global |
| Kotlin | 2.4.0, configuración existente | Gestionado por Gradle |
| Java de compilación | source/target y Kotlin JVM 17; CI usa JDK 17 | Revisar JDK efectivo con flutter doctor -v; no cambiar si compila |
| Java Cloud | OpenJDK 21.0.12.1 al preparar herramientas | Diferencia del host Cloud, no requisito de reinstalación Windows |
| Google Services | 4.5.0, previamente incorporado | Se aplica cuando existe google-services.json |
| Desugaring | 2.1.4 | Necesario por flutter_local_notifications; no se agregó otra dependencia en la auditoría |
| Identificador Android | com.nestorarakaki.club | Registrar exactamente éste en Firebase |

Los flags `android.newDsl=false` y `android.builtInKotlin=false` pertenecen a la
configuración previa de la plantilla Flutter y se conservaron. No se migró el
proyecto a otro sistema Gradle durante esta revisión. El heap Gradle ya se había
reducido a 3 GB en la implementación anterior por la memoria limitada de Cloud;
no indica que tengas que cambiar tu RAM, Java o Flutter.

## Comprobar sin reinstalar

```powershell
Set-Location C:\dev\ClubNestorArakaki
flutter --version
flutter doctor -v
flutter devices
flutter pub get
flutter analyze
flutter test
flutter run --dart-define-from-file=config/firebase.json
```

`flutter doctor -v` informa el Java usado por Flutter, que puede ser el de Android
Studio y diferir del `java -version` global. Sólo investigar diferencias si hay
un fallo real de compilación. No cambiar versiones para hacer coincidir la ruta
Linux `/tmp` o `/workspace` con Windows.

`android/local.properties` contiene rutas locales, no versiones del proyecto:
`sdk.dir` debe apuntar a `C:\Android\Sdk` y `flutter.sdk` a tu instalación existente.
Flutter genera/actualiza ese archivo local, que está excluido de Git y de los ZIP.
No copiar el local.properties de Cloud. El emulador Pixel 7 requiere Google
Play/Google APIs para verificar FCM. Las guías de Firebase/Render configuran
servicios, no reinstalan el entorno Android que ya está funcionando.
