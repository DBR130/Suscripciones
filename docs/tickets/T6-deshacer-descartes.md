# T6: Deshacer descartes

## Qué
- `GET /api/detecciones/descartadas`: candidatos descartados del usuario.
- `POST /api/detecciones/candidatos/:id/restaurar`: deja el candidato en
  `pendiente`. 404 si no existe o es de otro usuario; 409 si no está
  descartado.
- Pantalla 05: "No es mía" descarta al instante; la tarjeta se va y aparece
  una barra de 5 s "Descartamos X · Deshacer" (llama a restaurar). "Es mía"
  se sigue confirmando con el botón del final.
- Perfil → "Detecciones descartadas": nombre (o "Pago procesado por X"),
  último monto y frecuencia, con "Volver a proponer".
- Las barras de aviso quedan por encima de la barra de navegación flotante.

## Criterios de aceptación
- Restaurar un descarte de otro usuario → 404.
- Descartar y deshacer deja el candidato pendiente.
