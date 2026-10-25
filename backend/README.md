# Backend de SubTrack

API REST en **Node.js 24 + Express 5 + PostgreSQL**: autenticación con JWT,
suscripciones, resumen del dashboard y preferencias del usuario.

## Estructura

```
backend/
├── .env.example          Plantilla de variables de entorno
├── package.json
├── db/
│   ├── migraciones/      001_inicial.sql, 002_modelo_completo.sql, ...
│   ├── migrar.js         npm run db:migrate
│   └── README.md         Cómo crear la BD y correr migraciones
├── src/
│   ├── server.js         Punto de entrada: valida el .env y abre el puerto
│   ├── app.js            Crea la app Express y monta las rutas
│   ├── db.js             Pool de conexiones a PostgreSQL y transacciones
│   ├── routes/           Qué URL atiende cada controlador
│   ├── controllers/      Lógica de cada endpoint (consultas a la BD)
│   ├── middlewares/      Validación de datos, verificación del token y errores
│   ├── services/         Cálculos sin BD (resumen.js)
│   └── utils/            HttpError y fechas
└── test/                 npm test (node:test + supertest)
```

Flujo de una petición: `routes` → `middlewares` (validar / verificar token) →
`controllers` → respuesta JSON. Si algo falla, el error llega a
`middlewares/errorHandler.js`, que responde `{ "error": "mensaje" }`.

## Conceptos rápidos

- **Pool (pg)**: conexiones a PostgreSQL abiertas y reutilizables.
- **Consultas parametrizadas**: los valores van en `$1, $2...` y nunca se
  concatenan al SQL. Esto evita la inyección SQL.
- **bcrypt**: la contraseña se guarda como *hash* (irreversible). Al iniciar
  sesión se compara con `bcrypt.compare`.
- **JWT**: un texto firmado que el servidor entrega al iniciar sesión. La app lo
  guarda y lo envía en cada petición (`Authorization: Bearer <token>`). Vence a
  los 7 días.

## 1. Instalar

Requiere Node.js 24 y PostgreSQL con la base `subtrack` y sus tablas ya creadas.

```bash
cd backend
npm install
```

## 2. Configurar el `.env`

Copia la plantilla y edítala:

```bash
copy .env.example .env
```

(en Git Bash: `cp .env.example .env`). Luego abre `.env` y cambia:

- `DATABASE_URL`: reemplaza `TU_CONTRASEÑA` por la contraseña del usuario
  `postgres`. Si tiene caracteres especiales, codifícalos (`@` → `%40`,
  `#` → `%23`, `:` → `%3A`, `/` → `%2F`).
- `JWT_SECRET`: genera uno aleatorio con

  ```bash
  node -e "console.log(require('crypto').randomBytes(48).toString('hex'))"
  ```

`.env` está en `.gitignore`: nunca lo subas al repositorio.

## 3. Crear/actualizar las tablas

```bash
npm run db:migrate
```

Ver [db/README.md](db/README.md).

## 4. Ejecutar

```bash
npm run dev     # se reinicia solo al guardar cambios
npm start       # modo normal
npm test        # pruebas (usan la base subtrack_test, no la real)
```

Debe aparecer `API de SubTrack escuchando en http://0.0.0.0:3000`.

> La primera vez Windows puede preguntar si permite a Node.js acceder a la red.
> Acepta en **redes privadas** para que el celular pueda conectarse.

## 5. Probar los endpoints

Ejemplos con `curl` (Git Bash). En PowerShell usa `curl.exe` en lugar de `curl`.
En Thunder Client / Postman usa el mismo método, URL y cuerpo JSON
(Body → JSON).

### GET /api/health

Comprueba que la API funciona y que se conecta a la base de datos.

```bash
curl http://localhost:3000/api/health
```

- `200 {"ok":true}`
- `503 {"ok":false,"error":"Sin conexión a la base de datos"}` → revisa
  `DATABASE_URL` y que PostgreSQL esté encendido.

### POST /api/auth/registro

```bash
curl -X POST http://localhost:3000/api/auth/registro \
  -H "Content-Type: application/json" \
  -d '{"nombre":"Ana","correo":"ana@correo.com","password":"123456"}'
```

- `201 {"token":"eyJ...","usuario":{"id":1,"nombre":"Ana","correo":"ana@correo.com"}}`
- `400` datos inválidos (nombre vacío, correo mal escrito, contraseña < 6).
- `409 {"error":"Ya existe una cuenta con ese correo"}`

El correo se guarda sin espacios y en minúsculas.

### POST /api/auth/login

```bash
curl -X POST http://localhost:3000/api/auth/login \
  -H "Content-Type: application/json" \
  -d '{"correo":"ana@correo.com","password":"123456"}'
```

- `200 {"token":"eyJ...","usuario":{...}}`
- `401 {"error":"Correo o contraseña incorrectos"}`

### GET /api/auth/me

Copia el `token` de la respuesta anterior:

```bash
curl http://localhost:3000/api/auth/me -H "Authorization: Bearer PEGA_AQUI_EL_TOKEN"
```

En Thunder Client: pestaña **Auth → Bearer** y pega el token.

- `200 {"usuario":{"id":1,"nombre":"Ana","correo":"ana@correo.com"}}`
- `401` si falta el token, es inválido o expiró.

### Suscripciones

Todas requieren `Authorization: Bearer <token>`. Para no repetirlo, en Git
Bash guarda el token en una variable:

```bash
TOKEN=PEGA_AQUI_EL_TOKEN
```

| Método y ruta | Cuerpo | Respuesta |
|---|---|---|
| `GET /api/suscripciones?estado=activa` | — | `200 {"suscripciones":[...]}` ordenadas por `fecha_proximo_cobro`. `estado` es opcional y admite varios separados por coma |
| `POST /api/suscripciones` | ver abajo | `201 {"suscripcion":{...}}` |
| `GET /api/suscripciones/:id` | — | `200 {"suscripcion":{...},"pagos":[{"fecha_pago","monto"}],"pagado_total":0}` (los 3 últimos pagos) |
| `PUT /api/suscripciones/:id` | igual que POST | `200 {"suscripcion":{...}}` |
| `DELETE /api/suscripciones/:id` | — | `204` |
| `PATCH /api/suscripciones/:id/estado` | `{"estado":"marcada_para_cancelar"}` | `200 {"suscripcion":{...}}` |

Campos del POST/PUT:

| Campo | Obligatorio | Valores |
|---|---|---|
| `nombre_servicio` | sí | texto, máx. 100 |
| `categoria` | no (`null`) | `Streaming`, `Música`, `Cloud gaming`, `Almacenamiento`, `Gimnasio`, `Software`, `Diseño`; `null` o `""` = sin categoría |
| `monto` | sí | número ≥ 0, máx. 2 decimales (`38900` o `"12.99"`) |
| `moneda` | no (`COP`) | `COP`, `USD` |
| `frecuencia` | sí | `semanal`, `mensual`, `anual` |
| `fecha_proximo_cobro` | sí | `AAAA-MM-DD` |
| `es_prueba_gratis` | no (`false`) | `true`, `false` |
| `fecha_fin_prueba` | si es prueba | `AAAA-MM-DD` |
| `dias_aviso` | no (`null`) | entero 0–30; `null` = usar la preferencia global |

```bash
curl -X POST http://localhost:3000/api/suscripciones \
  -H "Authorization: Bearer $TOKEN" -H "Content-Type: application/json" \
  -d '{"nombre_servicio":"Netflix","monto":38900,"frecuencia":"mensual","fecha_proximo_cobro":"2026-11-20"}'

curl "http://localhost:3000/api/suscripciones?estado=activa" -H "Authorization: Bearer $TOKEN"

curl -X PATCH http://localhost:3000/api/suscripciones/1/estado \
  -H "Authorization: Bearer $TOKEN" -H "Content-Type: application/json" \
  -d '{"estado":"cancelada"}'
```

Si la suscripción no existe **o es de otro usuario**, responde `404`.

### GET /api/resumen

```bash
curl http://localhost:3000/api/resumen -H "Authorization: Bearer $TOKEN"
```

```json
{
  "totales": [
    { "moneda": "COP", "gasto_mensual": 58900, "proyeccion_anual": 706800, "cantidad": 3 },
    { "moneda": "USD", "gasto_mensual": 20, "proyeccion_anual": 240, "cantidad": 1 }
  ],
  "por_categoria": [
    { "categoria": "Streaming", "moneda": "COP", "gasto_mensual": 38900, "cantidad": 1 },
    { "categoria": null, "moneda": "USD", "gasto_mensual": 20, "cantidad": 1 }
  ],
  "cantidad_activas": 4,
  "proximos_cobros": [ { "...": "...", "dias_restantes": 2 } ],
  "pruebas_por_terminar": [ { "...": "...", "dias_restantes": 3 } ],
  "dias_anticipacion_recordatorio": 3
}
```

- Solo cuenta suscripciones `activa` y `marcada_para_cancelar`.
- Mensual equivalente: semanal × 52 / 12, mensual, anual / 12. Las monedas no
  se convierten.
- Las pruebas gratis cuentan en `cantidad` pero no suman gasto (cuestan 0
  mientras dura la prueba).
- Próximos cobros y pruebas: de hoy a 7 días.
- `por_categoria`: gasto mensual por categoría y moneda, de mayor a menor;
  `categoria: null` = sin categoría (va al final).

### Preferencias y cuenta

```bash
curl http://localhost:3000/api/usuarios/me/preferencias -H "Authorization: Bearer $TOKEN"

curl -X PUT http://localhost:3000/api/usuarios/me/preferencias \
  -H "Authorization: Bearer $TOKEN" -H "Content-Type: application/json" \
  -d '{"dias_anticipacion_recordatorio":7}'

# Elimina la cuenta y TODOS sus datos. 403 si la contraseña no coincide.
curl -X DELETE http://localhost:3000/api/usuarios/me \
  -H "Authorization: Bearer $TOKEN" -H "Content-Type: application/json" \
  -d '{"password":"123456"}'
```

### Ver los datos en la BD

```sql
SELECT id, nombre, correo, creado_en FROM usuarios;
```

Verás que `password_hash` empieza por `$2b$10$...`: es el hash, no la contraseña.

## Conectar desde el celular

1. PC y celular en la misma red WiFi.
2. Busca la IP del PC con `ipconfig` (campo "Dirección IPv4", ej. `192.168.1.50`).
3. Desde el navegador del celular abre `http://192.168.1.50:3000/api/health`.
   Si no carga, revisa el Firewall de Windows (permitir Node.js en red privada).
