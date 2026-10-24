# Backend de SubTrack

API REST en **Node.js 24 + Express 5 + PostgreSQL**. En esta fase solo cubre la
autenticación (registro, login y sesión con JWT).

## Estructura

```
backend/
├── .env.example          Plantilla de variables de entorno
├── package.json
└── src/
    ├── app.js            Punto de entrada: crea el servidor y monta las rutas
    ├── db.js             Pool de conexiones a PostgreSQL
    ├── routes/           Qué URL atiende cada controlador
    ├── controllers/      Lógica de cada endpoint (consultas a la BD)
    ├── middlewares/      Validación de datos, verificación del token y errores
    └── utils/            Utilidades (HttpError)
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

## 3. Ejecutar

```bash
npm run dev     # se reinicia solo al guardar cambios
npm start       # modo normal
```

Debe aparecer `API de SubTrack escuchando en http://0.0.0.0:3000`.

> La primera vez Windows puede preguntar si permite a Node.js acceder a la red.
> Acepta en **redes privadas** para que el celular pueda conectarse.

## 4. Probar los endpoints

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
