# T7: Reapertura de descartados

## Qué
- Los pagos de comercios descartados se conservan en el backend hasta 400
  días (son de servicios conocidos o recurrentes, nunca compras sueltas). Se
  borran al eliminar la cuenta (cascada) y cuando pasan los 400 días.
- Al restaurar o confirmar, termina esa retención especial: los pagos siguen
  las reglas normales.
- Migración 010: columnas `reabierto` (BOOLEAN) y `motivo` (TEXT) en
  `candidatos_suscripcion`.
- Si un comercio descartado acumula 3 o más cobros periódicos con montos
  similares, el candidato se reabre una sola vez (`reabierto = true`) con el
  motivo "Vimos 3 cobros mensuales de $X". Si se descarta de nuevo, no se
  reabre más (solo con "Volver a proponer").
- El motivo se ve en la tarjeta de la pantalla 05 y en el aviso del flujo B.
- Explicar la retención de 400 días en la sección de privacidad de
  `docs/deteccion.md`.

## Criterios de aceptación
- Descartado que luego acumula 3 cobros mensuales → se propone de nuevo una
  vez, con el motivo.
- Descartado de nuevo y 4.º cobro → no se reabre.
