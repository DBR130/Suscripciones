# T8: Aviso de pago registrado

## Qué
- Solo en el flujo en vivo (cola de notificaciones al abrir o volver a la
  app); no en la búsqueda del historial ni en "Compartir".
- Cuando un pago se registra en una suscripción existente, notificación local
  en el canal de detección: "Registramos un pago de {monto} en {servicio}".
- Si hubo cambio de precio: "{servicio} subió de {antes} a {ahora}" (o
  "bajó").
- Si en una misma revisión se registran 3 o más pagos, un solo aviso de
  resumen.
- Nada si el pago fue repetido, compra normal o comercio descartado.
- El backend devuelve en `resultados` lo necesario (nombre del servicio,
  monto y, si cambió, el monto anterior).

## Criterios de aceptación
- Pago registrado en Netflix → "Registramos un pago de $44.900 en Netflix".
- Netflix de $44.900 a $49.900 → "Netflix subió de $44.900 a $49.900".
- Repetido → ningún aviso.
