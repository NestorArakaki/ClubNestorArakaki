# Ajuste final de UX/UI

La consulta de las ocho referencias de Figma y la captura de Home fueron
bloqueadas por el límite de llamadas del plan Starter. Se implementó la
alternativa autorizada en el pedido: identidad deportiva, azul oscuro/lima,
tarjetas Material 3, jerarquía tipográfica y estados semánticos. No se afirma
una reproducción exacta de las pantallas de Figma.

## Comportamiento

- Próximas / en curso: solamente `confirmed` con `ends_at > ahora`.
- Historial: canceladas de cualquier fecha y confirmadas finalizadas.
- `Booking.phaseAt` distingue Confirmada, En curso, Finalizada y Cancelada;
  el mismo componente muestra texto, ícono y color en listado, Inicio y detalle.
  Cancelada usa `colorScheme.error`. Son estados de presentación de Flutter;
  PostgreSQL sigue usando los estados existentes.
- Ambas pestañas clasifican una consulta paginada completa `period=all` y
  `status=all`. Cambiar de pestaña no dispara otra consulta. Volver de un detalle
  y deslizar para actualizar vuelven a consultar la API.
- Inicio usa perfil, sedes y reservas reales: saludo si hay nombre, siguiente
  reserva confirmada (prioriza una en curso), estado vacío y acceso a sedes.
  No incorpora precios, puntuaciones, fotos ni filtros nuevos. El filtro por
  deporte sigue en las canchas de cada sede.
- La navegación suma Inicio y conserva Sedes, Mis reservas y Perfil. Un push
  de la cuenta actual abre el detalle y actualiza Mis reservas al regresar;
  uno de otra cuenta se descarta.
- Los errores de conexión/servidor tienen ícono, título, explicación y reintento
  manual de consultas. El servidor puede tardar en reactivarse en Render Free.
  Los errores inesperados no muestran trazas. Los formularios muestran errores
  junto a los campos y en un bloque visible con anuncio de accesibilidad.
- Los horarios sin disponibilidad tienen estado vacío. Se mantienen los
  checks consecutivos, la confirmación, la actualización tras un 409 y el bloqueo
  de nuevos intentos ante un resultado de reserva desconocido.
- Sólo GET se reintenta tras renovar el token ante un 401. Las escrituras,
  incluido POST de reservas, requieren una nueva acción explícita.
- Se conserva el estado explícito de activación de FCM y la actualización de
  permisos al reanudar. Un token registrado no demuestra la entrega de un push.

## Archivos del ajuste

| Archivos | Responsabilidad |
| --- | --- |
| `lib/app.dart`, `lib/theme.dart` | Navegación, retorno desde push y tema compartido. |
| `lib/models/models.dart` | Clasificación temporal y estado visual de las reservas. |
| `lib/screens/bookings_screen.dart` | Próximas/Historial, detalle y actualización tras cancelar. |
| `lib/screens/dashboard_screen.dart` | Inicio con datos reales y navegación. |
| `lib/screens/venues_screen.dart` | Tarjetas y estado vacío de sedes. |
| `lib/screens/auth_screen.dart` | Validación y errores junto al formulario. |
| `lib/screens/availability_screen.dart` | Estado vacío cuando no hay turnos disponibles. |
| `lib/screens/profile_screen.dart` | Mensajes seguros ante errores inesperados al guardar. |
| `lib/services/api_client.dart` | Reintento con token renovado limitado a consultas GET. |
| `lib/widgets/async_view.dart`, `lib/widgets/error_panel.dart` | Carga y errores reutilizables. |
| `lib/widgets/booking_card.dart`, `lib/widgets/venue_card.dart`, `lib/widgets/empty_state.dart` | Presentación compartida de tarjetas, estados y vacíos. |
| `test/widget_test.dart`, `test/ux_test.dart` | Regresiones existentes y casos nuevos de UX. |
| `docs/UX_FINAL.md` | Alcance y comprobaciones manuales de este ajuste. |

No se modifican backend, contrato REST, dependencias ni configuración de Firebase.

## Verificación automatizada

Con Flutter 3.47.7: `flutter analyze` sin observaciones, `flutter test` con
67 pruebas aprobadas y `dart format --output=none --set-exit-if-changed lib test`
sin cambios pendientes. Incluye paginación, canceladas futuras, límites de
inicio/fin, colores y etiquetas, actualización al cancelar, Inicio con/sin
próximas, errores/reintento, timeout, validación Firebase y navegación por push.
Se verificó una superficie de 393 × 852 puntos con texto al 150% sin overflow,
y se revisaron capturas de widgets con fuentes e íconos Material.

## Pendiente de repetir en Pixel 7

Las integraciones reales ya fueron comprobadas por el usuario antes de este
ajuste. Las pruebas de widgets y las capturas de revisión no reemplazan la
comprobación de esta versión en el teléfono:

1. Revisar Inicio con/sin reserva, nombre largo, desplazamiento, navegación
   gestual, teclado y tamaño de fuente del dispositivo.
2. Reservar varios bloques, cancelar una reserva futura y otra en curso;
   comprobar Próximas, Historial, detalle e Inicio al actualizar/regresar.
3. Probar modo avión, reintento al recuperar conexión y reactivación de Render.
   Ante un fallo al confirmar, revisar Mis reservas antes de repetir el POST.
4. Repetir login incorrecto, correo existente y validación de campos.
5. Abrir una reserva desde un push con la app abierta, en segundo plano y
   cerrada; comprobar el retorno a Mis reservas y el aislamiento entre cuentas.
6. Revocar/restaurar permisos en Ajustes: al volver debe cambiar la acción y
   «Notificaciones activadas», sin registros repetidos del mismo token.

No se incorporan eliminación de cuentas, administración ni pagos.
