# Recordatorios de reservas próximas

La consigna exige un push antes del turno; los avisos inmediatos de creación y
cancelación no satisfacen ese requisito por sí solos. Se agregó un recordatorio
FCM para reservas confirmadas que empiezan en los próximos **60 minutos**.

## Mecanismo real

`.github/workflows/booking-reminders.yml` ejecuta una petición HTTPS cada diez
minutos, en los minutos 7, 17, 27, 37, 47 y 57 de cada hora UTC. El reloj de la
reserva se compara como un instante UTC; no depende de la zona del runner.

El workflow invoca `POST /api/v1/internal/booking-reminders`. Flask comprueba
`X-Scheduler-Key`, selecciona las reservas futuras confirmadas sin
`reminder_sent_at`, llama a Firebase Admin y guarda la marca si FCM aceptó al
menos un dispositivo del propietario. El cliente reconoce `booking_reminder`
y abre los detalles de la reserva autenticada al tocarlo.

`SELECT ... FOR UPDATE SKIP LOCKED` mantiene bloqueada cada reserva hasta el
commit: una ejecución concurrente omite filas que ya se están procesando. Una
cancelación también usa el bloqueo de fila. Una reserva cancelada o iniciada no
se selecciona; además se comprueba el inicio justo antes de enviar. El TTL Android
es el tiempo restante hasta el comienzo, para no entregar un recordatorio que
quedó en espera durante días. No se agregaron tablas de tareas, Redis ni workers.

Respuesta de ejemplo: `{"checked":1,"sent":1,"pending":0}`. Los números son
reservas, no dispositivos. `pending` significa que no se aceptó ningún envío
(por falta de token, token inválido o fallo del SDK); se vuelve a intentar en la
siguiente ejecución mientras el turno siga siendo futuro y dentro de la ventana.

## Activación con tus cuentas

1. Desplegar el código en Render Free, con la migración `1003_booking_reminders`,
   cuenta Firebase Admin y `FCM_ENABLED=true`. La app debe haber registrado un
   token real mediante Activar avisos.
2. Generar una clave privada aleatoria en PowerShell, sin subirla a Git:

   ```powershell
   $bytes = New-Object byte[] 32
   $rng = [System.Security.Cryptography.RandomNumberGenerator]::Create()
   $rng.GetBytes($bytes)
   $schedulerKey = [Convert]::ToBase64String($bytes)
   $rng.Dispose()
   ```

3. Copiar su valor sólo a la variable privada `REMINDER_SCHEDULER_KEY` de Render y
   al secret de GitHub del mismo nombre. No ponerlo en la app, la URL ni el YAML.
   GitHub → Settings → Secrets and variables → Actions → Secrets → New repository
   secret. Para copiarlo desde PowerShell: `$schedulerKey | Set-Clipboard`.
4. En la pestaña **Variables** de Actions agregar:
   - `REMINDER_API_BASE_URL`: `https://TU-SERVICIO.onrender.com/api/v1`.
   - `REMINDERS_ENABLED`: `true`.
5. El workflow debe estar en la **rama predeterminada** para que funcione el cron.
   Mientras el PR no esté integrado, usar la llamada manual de abajo para la demo.
   No se fusionaron ramas ni se activó un programador remoto en esta tarea.
6. Tras integrar el PR, Actions → Recordatorios de reservas → Run workflow.
   Revisar los contadores devueltos. Crear una reserva dentro de la próxima hora,
   enviar la app a segundo plano y esperar el aviso; tocarlo debe abrir esa reserva.

Prueba manual desde PowerShell (con la clave todavía sólo en memoria):

```powershell
$base = 'https://TU-SERVICIO.onrender.com/api/v1'
Invoke-RestMethod -Method Post -Uri "$base/internal/booking-reminders" `
  -Headers @{ 'X-Scheduler-Key' = $schedulerKey } -TimeoutSec 120
# Repetir: la misma reserva aceptada no debe volver a contarse como enviada.
```

Sin una clave de al menos 32 caracteres el endpoint devuelve 503; con una clave
incorrecta devuelve 401. Un Firebase ID Token de usuario no autoriza al scheduler.
Con FCM desactivado responde 503. Swagger declara una seguridad separada
`SchedulerKey`; no se expone una ruta pública que dispare mensajes arbitrarios.

## Gratuidad y límites

Se verificó que el repositorio es **público**. GitHub permite runners estándar
sin cargo en repositorios públicos ([facturación oficial](https://docs.github.com/en/billing/concepts/product-billing/github-actions)).
El workflow se omite si el repositorio pasa a privado o falta la variable de
activación. No contrata cron jobs de Render, que no son parte de su Web Service Free.

GitHub puede demorar los eventos programados; no es un reloj de precisión ni un
servicio de entrega garantizada. En repositorios públicos se desactivan tras
60 días sin actividad. Se eligió una ventana de una hora para tolerar retrasos
habituales, pero una caída prolongada puede perder un recordatorio. Consultar
[las reglas de schedule](https://docs.github.com/en/actions/reference/workflows-and-actions/events-that-trigger-workflows#schedule).

Render puede tardar cerca de un minuto en despertar. La petición espera hasta
110 segundos. La base Free vence: ver [RENDER_FREE.md](RENDER_FREE.md). No se
modificaron los planes para resolver estas limitaciones.

La marca registra aceptación por FCM, no lectura ni entrega comprobada al teléfono.
Una caída entre el envío y el commit puede producir un duplicado al reintentar.
Si un usuario tiene varios dispositivos y sólo uno acepta el envío, se marca la
reserva y no se vuelve a molestar al dispositivo que ya lo recibió. El envío es
síncrono y pensado para el volumen pequeño del TP; no es una plataforma masiva.
Estas limitaciones evitan afirmar una garantía de entrega exactamente una vez.
