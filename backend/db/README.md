# Base de datos de SubTrack

PostgreSQL 18. El esquema se maneja con **migraciones**: archivos `.sql`
numerados en `db/migraciones/` que se aplican en orden y una sola vez.

| Archivo | Qué hace |
|---|---|
| `001_inicial.sql` | Tablas `usuarios` y `suscripciones` de la fase 1 |
| `002_modelo_completo.sql` | Preferencias del usuario, estados de la suscripción, pruebas gratis y tablas `historial_pagos`, `cancelaciones`, `guias_cancelacion`, `notificaciones_enviadas` |
| `003_categoria.sql` | Columna opcional `categoria` en `suscripciones`, limitada a las categorías del diseño |
| `004_cobros_y_precios.sql` | `UNIQUE (suscripcion_id, fecha_pago)` en `historial_pagos` y tabla `cambios_precio` |
| `005_guias_cancelacion.sql` | Columnas `alias`, `duracion_minutos`, `actualizada_en` y `es_generica` en `guias_cancelacion`; `pasos` pasa a JSONB |

La tabla `schema_migrations` guarda qué migraciones ya se aplicaron.

## Crear la base de datos desde cero (por ejemplo, Santiago)

1. Instala PostgreSQL 18 y recuerda la contraseña del usuario `postgres`.
2. Crea la base vacía. Desde una terminal:

   ```bash
   psql -U postgres -c "CREATE DATABASE subtrack;"
   ```

   O en pgAdmin: clic derecho en **Databases → Create → Database...**, nombre
   `subtrack`.
3. Configura `backend/.env` (ver `backend/README.md`).
4. Aplica las migraciones:

   ```bash
   cd backend
   npm install
   npm run db:migrate
   ```

   Debe mostrar:

   ```
   + 001_inicial.sql
   + 002_modelo_completo.sql
   + 003_categoria.sql
   + 004_cobros_y_precios.sql
   + 005_guias_cancelacion.sql
   ```

5. Carga el catálogo de guías de cancelación:

   ```bash
   npm run db:guias
   ```

## Actualizar una base que ya existe

```bash
npm run db:migrate
```

Solo aplica las migraciones pendientes. Si ya está al día, muestra
`La base de datos ya está al día.`

Si tu base se creó a mano antes de que existieran las migraciones (tiene la
tabla `usuarios` pero no `schema_migrations`), la `001` se marca como aplicada
sin ejecutarse y luego se aplica la `002`. No se borran datos.

Cada migración corre dentro de una **transacción**: si algo falla, no queda a
medias y la base sigue como estaba.

## Catálogo de guías de cancelación

Las guías están en `db/guias.json`, no en el código de la app. Para
actualizarlas (por ejemplo, si un proveedor cambia sus pasos):

1. Edita `db/guias.json`. Cada guía tiene:

   | Campo | Qué es |
   |---|---|
   | `nombre_servicio` | Nombre principal, único (`"Netflix"`) |
   | `alias` | Otros nombres con que el usuario lo escribe (`["HBO Max", "HBO"]`) |
   | `duracion_minutos` | Tiempo aproximado (`3`) |
   | `enlace_directo` | Página oficial de cuenta o ayuda (`https://...`) o `null` |
   | `pasos` | Arreglo de textos, en orden (3 a 5) |
   | `es_generica` | `true` solo en "Otro servicio", la que se usa si no hay coincidencia |

2. Corre `npm run db:guias`. Inserta las nuevas y actualiza las que
   cambiaron; las que no cambiaron no se tocan. Correrlo varias veces da el
   mismo resultado. Una guía que quites del JSON **no** se borra de la BD.

La app busca la guía comparando el nombre de la suscripción con
`nombre_servicio` y `alias`, sin mayúsculas ni tildes, y acepta el plan en
el nombre ("Netflix Estándar" → Netflix). Si no encuentra ninguna, usa la
genérica. Los cambios se ven en la app sin publicar otra versión (RNF08).

## Usuario de demostración

```bash
npm run db:demo
```

Crea (o reinicia) **solo** el usuario `demo@subtrack.co` / `Demo1234`, con 8
suscripciones activas (una en USD, una prueba gratis que termina en 2 días,
una con cobro mañana, una marcada para cancelar), 2 canceladas con su ahorro,
6 meses de historial de pagos y un cambio de precio reciente. Las fechas se
calculan desde hoy, así que conviene correrlo el día de la demostración.
Ningún otro usuario se modifica.

## Agregar una migración nueva

1. Crea `db/migraciones/003_descripcion_corta.sql` (el número siguiente).
2. Escribe ahí los cambios (`ALTER TABLE`, `CREATE TABLE`, ...).
3. Corre `npm run db:migrate`.

Nunca edites una migración que ya se aplicó en otra máquina: crea una nueva.

## Base de datos de pruebas

`npm test` usa una base aparte llamada `subtrack_test` (la crea sola, la
borra y le aplica las migraciones en cada ejecución). Nunca toca `subtrack`.
Para usar otra base, define `TEST_DATABASE_URL`; su nombre debe terminar en
`_test`.

## Modelo

- **usuarios**: `dias_anticipacion_recordatorio` (0–30, por defecto 3),
  `pais` (`CO`), `permiso_notificaciones`.
- **suscripciones**: `nombre_servicio`, `categoria` (opcional: `Streaming`,
  `Música`, `Cloud gaming`, `Almacenamiento`, `Gimnasio`, `Software`,
  `Diseño`), `monto` (NUMERIC 12,2), `moneda`
  (`COP` o `USD`), `frecuencia` (`semanal`, `mensual`, `anual`),
  `fecha_proximo_cobro`, `es_prueba_gratis` + `fecha_fin_prueba` (obligatoria
  si es prueba), `dias_aviso` (NULL = usar la preferencia del usuario),
  `origen` (`manual`, `notificacion`), `estado` (`activa`,
  `marcada_para_cancelar`, `cancelada`), `fecha_deteccion`.
- **historial_pagos**, **cancelaciones**, **cambios_precio**: dependen de una
  suscripción y se borran con ella. Un pago es único por suscripción y fecha.
- **notificaciones_enviadas**: dependen del usuario; si se borra la
  suscripción, el aviso se conserva sin ella.
- **guias_cancelacion**: catálogo general, una guía por servicio.

Al borrar un usuario se borran en cascada todas sus suscripciones, pagos,
cancelaciones y avisos.
