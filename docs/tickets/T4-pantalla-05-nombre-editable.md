# T4: Pantalla 05: "Pago procesado por X" y nombre editable

## Qué
- Un candidato de procesador se muestra como "Pago procesado por {procesador}"
  con la pregunta "¿Qué servicio es?".
- El lápiz abre la hoja con nombre, monto y frecuencia para cualquier
  candidato; el nombre tiene sugerencias del catálogo mientras se escribe.
- En un candidato de procesador, tocar "Es mía" abre la hoja para escribir el
  nombre antes de confirmar.
- Al confirmar se envía `nombre_servicio`; la suscripción queda con ese
  nombre.
- Los cobros siguientes del mismo procesador con monto ±10 % del candidato
  confirmado se registran en esa suscripción (caso a).

## Criterios de aceptación
- Confirmar un candidato EBANX como "Crunchyroll" crea la suscripción
  "Crunchyroll" con sus pagos.
- Un cobro posterior de EBANX de $19.900 se registra en "Crunchyroll"; uno de
  $34.900 no.
- Limitación documentada: una subida de más del 10 % del servicio aparece
  como candidato nuevo del procesador.
