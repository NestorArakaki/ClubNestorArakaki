# Verificación del backend contra el TP

Auditoría posterior al frontend: **85 pruebas aprobadas y 96% de cobertura**
sobre PostgreSQL 16 real descartable con Python 3.12.14. Ruff análisis/formato
correctos. No se usó SQLite ni credenciales Firebase reales.

Se conservan los tests de reservas, superposición, concurrencia, cancelación,
propiedad, perfil, validaciones, errores, OpenAPI, dispositivos y arranque seguro.
Se agregaron pruebas de recordatorios próximos: secreto de scheduler, ventana,
estado, marca persistente, TTL, reintento y dos peticiones concurrentes. Se prueba
el nombre compuesto real de la cancha. La cancelación permite reservas en curso;
las finalizadas siguen protegidas en historial.

`db check` no detectó cambios pendientes. Se ejecutó upgrade de 1003, downgrade a
1002 y upgrade nuevamente sólo en la base descartable. La marca nueva es nullable
y no reemplaza ni elimina reservas existentes. Ocho advertencias del SDK sobre
`Message.token` no impidieron aprobar la suite.

La implementación anterior verificó seed repetido, migraciones desde base vacía
y arranque HTTP real con Gunicorn. Resultados completos, evidencia CI y pasos
personales pendientes en [VERIFICACION.md](../../docs/VERIFICACION.md).
El envío con SDK sustituido no equivale a entrega Firebase real. Activación
segura del programador en [RECORDATORIOS.md](../../docs/RECORDATORIOS.md).

CI actual: [Backend aprobado](https://github.com/NestorArakaki/ClubNestorArakaki/actions/runs/39134442623),
y [Flutter aprobado con APK debug](https://github.com/NestorArakaki/ClubNestorArakaki/actions/runs/39134442583),
commit funcional `4cadd6c`. No se activó el programador de recordatorios remoto.
