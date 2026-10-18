# Demostración universitaria

## Antes de empezar

- [ ] Base Render aún vigente, ambos servicios en Free; no hay recursos pagos.
- [ ] `/api/v1/health` devuelve `ok` y `/venues` contiene el catálogo esperado.
- [ ] Si se usan datos demo, explicarlo; no presentarlos como sedes reales confirmadas.
- [ ] Email/Password habilitado y configuración Android del mismo proyecto Firebase.
- [ ] API_BASE_URL correcta, incluye `/api/v1`; HTTPS si se usa release.
- [ ] Emulador con Google Play/Google APIs, conexión y hora correctas.
- [ ] Cuenta Admin con permisos Auth y FCM; API FCM v1 habilitada y FCM_ENABLED=true.
- [ ] Permisos Android concedidos mediante Activar avisos.
- [ ] Recordatorios: REMINDER_SCHEDULER_KEY configurado; workflow activado en rama principal o llamada manual lista.
- [ ] Ícono propio visible, filtro por deporte y nombres sede/dirección/tipo/número comprobados.
- [ ] Modelo de datos y guía de defensa abiertos; ambos ZIP preparados para Blackboard.
- [ ] Abrir salud antes de empezar para despertar Render Free.

## Flujo completo

1. Abrir la app sin sesión: comprobar validaciones de correo y contraseña.
2. Registrar una cuenta real; cerrar y volver a abrir la app para comprobar persistencia.
3. Entrar a Perfil, guardar nombre/apellido/fecha válida; email no editable.
4. Elegir sede, revisar horarios y canchas obtenidos de la API.
5. Elegir fecha futura y un turno; mostrar bloques disponibles y ocupados/pasados.
6. Seleccionar dos horas contiguas si hay espacio y confirmar una sola vez.
7. Ver aviso, abrir Mis reservas y comprobar sede, cancha, fecha, estado y zona horaria.
8. Dejar la app en segundo plano y crear/cancelar desde otra sesión del mismo
   usuario para probar el push y la apertura del detalle al tocarlo.
9. Con otra cuenta, intentar el mismo intervalo: debe responder conflicto y
   actualizar disponibilidad. Verificar que no aparecen reservas de otra persona.
10. Cancelar la reserva propia futura, aceptar confirmación y comprobar que
    el turno vuelve a estar disponible. La reserva queda como cancelada.
11. Abrir Historial (puede estar vacío en una base nueva); consultar próximas/en curso.
12. Solicitar recuperación de contraseña y comprobar el correo recibido.
13. Cerrar sesión: vuelve el login y no quedan rutas de datos de la cuenta anterior.

## Recuperación ante problemas

- Si Render tarda en despertar, esperar y tocar Reintentar. No enviar varios POST.
- Si se pierde la respuesta al reservar, **primero revisar Mis reservas**: la
  operación podría haberse confirmado. Volver a elegir el turno sólo después
  de verificarlo; el servidor mantiene la exclusión contra superposiciones.
- Si falla Firebase, revisar proyecto/JSON/Email-Password/permisos; no reemplazar
  autenticación por un usuario fijo.
- Si no llega el push, comprobar token registrado, permisos y logs del backend.
  La reserva puede estar confirmada igualmente: consultar Mis reservas.
- Si la fecha aparece desplazada, recordar que se muestran horarios de la sede,
  no la zona del teléfono. La fecha de disponibilidad pertenece a esa sede.


## Evidencia específica del recordatorio

Reservar una hora completa cuyo comienzo sea dentro de los próximos 60 minutos.
Verificar que la reserva quede confirmada, poner Android en segundo plano e
invocar el endpoint protegido o esperar el workflow. Tocar el push debe abrir
la reserva correcta. Repetir la llamada: el contador `sent` ya no debe incluir
esa reserva. Para probar un turno cancelado, cancelar antes de disparar el
recordatorio y verificar que no se seleccione. Ver `RECORDATORIOS.md` para comandos.
Una notificación inmediata al crear no reemplaza esta evidencia.
