# Tickets: mejoras de la detección (noviembre de 2026)

Acordados en la revisión del plan (preguntas Q1 a Q25). Cada ticket es una
rebanada vertical: celular, backend, base de datos y pantalla, con sus tests.
Se implementan en orden, con TDD (test que falla, código mínimo, commit).

| # | Ticket | Depende de | Migración |
|---|---|---|---|
| [T1](T1-nombres-pegados-y-senal.md) | Nombres pegados y señal de suscripción | — | — |
| [T2](T2-servicios-ambiguos.md) | Servicios ambiguos | T1 | 008 |
| [T3](T3-procesadores-candidatos.md) | Procesadores: detección y candidatos separados por monto | T1 | 009 |
| [T4](T4-pantalla-05-nombre-editable.md) | Pantalla 05: "Pago procesado por X" y nombre editable | T3 | — |
| [T5](T5-sugerencia-por-monto.md) | Sugerencia por monto | T4 | (008) |
| [T6](T6-deshacer-descartes.md) | Deshacer descartes | — | — |
| [T7](T7-reapertura-de-descartados.md) | Reapertura de descartados | T6 | 010 |
| [T8](T8-aviso-pago-registrado.md) | Aviso de pago registrado | — | — |
| [T9](T9-documentacion.md) | Documentación | todos | — |

Reglas comunes:

- Las reglas nuevas quedan iguales en el celular (`lib/deteccion/`) y en el
  backend (`backend/src/services/detecciones.js`).
- El texto de los SMS nunca sale del celular.
- No se amplía el parser a formatos de SMS que no se hayan visto en mensajes
  reales.
