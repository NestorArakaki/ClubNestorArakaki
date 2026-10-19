# Entrega académica: código, modelo y demostración

La Entrega 1 es grupal: mockup/prototipo navegable Figma y documentación que indique
la cátedra. La Entrega 2 es individual: backend en nube, app conectada, ícono,
auth, reservas, modelo de datos y manejo de errores; demostrar en emulador y subir
**dos ZIP de código** a Blackboard antes de exponer. No se inventó una fecha de entrega.

## Preparar los archivos en PowerShell

Desde el repositorio Git (no desde un ZIP descomprimido):

```powershell
Set-Location C:\dev\ClubNestorArakaki
git status
flutter analyze
flutter test
py -3.12 tools/package_tp.py
Get-ChildItem dist\*.zip
Get-FileHash dist\*.zip -Algorithm SHA256
```

El script necesita Python estándar y Git, sin paquetes nuevos. Si hay cambios
sin guardar o archivos sin versionar, se detiene: revisarlos antes de hacer un
commit propio. No sube archivos a Blackboard ni cambia ramas. Produce:

- `dist/ClubNestorArakaki_flutter.zip`: fuentes Flutter/Android, pruebas y guías.
- `dist/ClubNestorArakaki_backend.zip`: carpeta backend con migraciones, pruebas,
  README y guías compartidas. Mantiene su ruta `backend/`.

Cada ZIP contiene `ENTREGA_COMMIT.txt` con el commit. Se toman sólo archivos
versionados y se excluyen explícitamente configuraciones Firebase locales,
`.env`, claves Admin y keystores. No incluye SDK, venv, .git, builds ni cachés.
`.env.example` y `config/firebase.example.json` son ejemplos sin credenciales y
sí se entregan. Una configuración privada del alumno no debe agregarse a Git para
que el profesor pueda ejecutar: se proporcionan pasos para configurarla por separado.

Para reconstruir el proyecto completo se pueden descomprimir ambos ZIP en la
misma carpeta. Las guías/README compartidos son iguales. Desde un clon, el historial
Git es la evidencia del desarrollo; los ZIP sólo son la copia de código requerida.

## Antes de Blackboard

1. Verificar que ambos ZIP abran y contengan `lib/main.dart`, respectivamente
   `backend/wsgi.py`, sus README y el modelo `docs/MODELO_DATOS.md`.
2. No confundir un APK o la URL GitHub con los ZIP de código que pide la consigna.
3. Comprobar API pública HTTPS y la base Free vigente; documentar la URL desplegada
   sin secretos. Abrir Swagger y una operación real desde Android.
4. Probar registro/login, perfil, filtro, disponibilidad, reserva, cancelación,
   historial, error de conexión y recordatorio real. Ver `DEMO.md`.
5. Abrir el prototipo Figma y comprobar su navegación. El repositorio enlaza el
   diseño del grupo, pero la lectura de sus capas no prueba que todos los enlaces
   del prototipo estén conectados.
6. Subir los dos ZIP y la documentación solicitada por la cátedra desde la cuenta
   del alumno. Registrar la confirmación/fecha de Blackboard. Esa acción es personal.
7. Estudiar `GUIA_DEFENSA_TP.md`, abrir las funciones que se van a explicar y poder
   justificar las decisiones. Revisar el historial sin atribuir como manual una
   implementación que no se comprende.
