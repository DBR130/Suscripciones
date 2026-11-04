# T5: Sugerencia por monto

## Qué
- `precio_referencia_cop` en `guias.json`: solo Crunchyroll, 19.900 COP
  (plan del probador, octubre de 2026, de un SMS y un correo reales). Los
  demás quedan vacíos. Claude no se usa (cobra en USD).
- `GET /api/guias` lo devuelve.
- En la hoja de edición, si el monto del candidato (COP) está a ±5 % del
  precio de referencia de un servicio, aparece el chip "¿Es {servicio}?" que
  llena el nombre al tocarlo. Nunca se elige solo.

## Criterios de aceptación
- Candidato EBANX de $19.900 → chip "¿Es Crunchyroll?".
- Candidato EBANX de $34.900 → sin chip.
