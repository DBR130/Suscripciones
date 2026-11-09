# Despliegue de SubTrack en la nube (Render + Neon)

Guía paso a paso para usar la app **sin USB y sin el PC encendido**. No hace
falta haber desplegado nada antes.

| Pieza | Dónde | Plan |
|---|---|---|
| Base de datos PostgreSQL | [Neon](https://neon.tech), región AWS US East (N. Virginia) | Gratuito |
| Backend (Node.js + Express) | [Render](https://render.com), Web Service, región Virginia (US East) | Gratuito |
| App | APK release instalado en el celular, apuntando a la URL de Render | — |

```
Celular (APK release) ──HTTPS──► Render: backend (carpeta backend/) ──SSL──► Neon: PostgreSQL
```

> **Lo que nunca va al repositorio:** la cadena de conexión de Neon (tiene la
> contraseña) y el `JWT_SECRET`. La cadena vive en `backend/.env.produccion`
> (ignorado por git) y en las variables de entorno de Render.

---

## 1. Crear la base de datos en Neon

1. Entra a [neon.tech](https://neon.tech) y crea una cuenta (puedes usar tu
   cuenta de GitHub o de Google).
2. Crea un proyecto nuevo:
   - **Project name:** `subtrack`
   - **Postgres version:** la más reciente que ofrezca.
   - **Region:** **AWS US East 1 (N. Virginia)**, la misma región que Render,
     para que la API y la base estén cerca.
3. Al terminar, Neon crea una base llamada `neondb`. En el panel del proyecto
   toca **Connect** y copia la **cadena de conexión** (connection string).
   Tiene esta forma:

   ```
   postgresql://neondb_owner:CONTRASEÑA@ep-algo-123456.us-east-1.aws.neon.tech/neondb?sslmode=require&channel_binding=require
   ```

   - Si ves una opción **Connection pooling**, déjala **desactivada**: así la
     cadena es la conexión directa (el host **no** tiene `-pooler`), que sirve
     tanto para las migraciones como para la API.
   - `sslmode=require` obliga a usar conexión cifrada. Déjalo tal cual.
4. Guarda la cadena en un lugar seguro: la usarás en los pasos 2 y 3. **No la
   pegues en ningún archivo del repositorio** salvo `backend/.env.produccion`.

---

## 2. Crear las tablas, el catálogo y la demo en Neon (desde tu PC)

Las migraciones **no se aplican solas** al desplegar: se corren desde tu PC. Tu
`.env` local (la base `subtrack` de tu PC) no se toca: estos comandos leen
otro archivo, `backend/.env.produccion`.

En PowerShell, desde la carpeta del proyecto:

```powershell
cd backend
Copy-Item .env.produccion.example .env.produccion
notepad .env.produccion
```

En el Bloc de notas, reemplaza la línea `DATABASE_URL=...` por la cadena de
Neon del paso 1 (sin comillas) y guarda.

Comprueba que git **no** lo ve (no debe aparecer en la lista):

```powershell
git status --short
```

Ahora, en orden:

```powershell
npm run db:migrate:nube
```

Debe mostrar las 6 migraciones:

```
+ 001_inicial.sql
+ 002_modelo_completo.sql
+ 003_categoria.sql
+ 004_cobros_y_precios.sql
+ 005_guias_cancelacion.sql
+ 006_detecciones.sql
```

```powershell
npm run db:guias:nube
```

Carga las 20 guías de cancelación (y la genérica).

```powershell
npm run db:demo:nube
```

Crea el usuario de demostración **demo@subtrack.co / Demo1234** con
suscripciones, historial, ahorro y dos candidatos detectados (pantalla 05).
Solo toca a ese usuario.

> **Aviso "SECURITY WARNING: The SSL modes 'prefer', 'require'…"**: lo
> imprime la librería `pg` al leer `sslmode=require`. Es informativo: hoy
> `require` ya funciona con verificación completa del certificado (Neon usa
> un certificado público). Si quieres quitar el aviso, cambia
> `sslmode=require` por `sslmode=verify-full` en la cadena; funciona igual.

**Alternativa sin archivo** (solo para un comando; la variable desaparece al
cerrar esa ventana de PowerShell):

```powershell
$env:DATABASE_URL = "postgresql://...neon.tech/neondb?sslmode=require&channel_binding=require"
npm run db:migrate
Remove-Item Env:DATABASE_URL
```

Funciona porque una variable definida en la terminal gana sobre la del `.env`.
Con `.env.produccion` es más difícil equivocarse de base, por eso es la
opción recomendada.

**Cuando agregues una migración nueva** (007, 008…): vuelve a correr
`npm run db:migrate:nube`. Si se te olvida, los logs de Render lo avisan al
arrancar (ver paso 3).

---

## 3. Crear el Web Service en Render

Render despliega **lo que esté en GitHub**: antes de este paso, la rama que
vas a desplegar debe estar subida (push) con los cambios de esta fase.

1. Entra a [render.com](https://render.com) y crea una cuenta **con GitHub**
   (así Render puede leer el repositorio).
2. En el panel: **New → Web Service**. Conecta el repositorio
   `flutter_suscripciones` (si no aparece, toca *Configure account* y dale
   acceso a ese repositorio).
3. Llena el formulario:

   | Campo | Valor |
   |---|---|
   | **Name** | El que quieras, por ejemplo `subtrack-api`. Será parte de la URL: `https://subtrack-api.onrender.com` (si el nombre está ocupado, Render agrega letras al final) |
   | **Language** | Node |
   | **Branch** | La rama a desplegar (por ejemplo `David` mientras pruebas, o `main` cuando unan los cambios) |
   | **Region** | Virginia (US East) |
   | **Root Directory** | `backend` |
   | **Build Command** | `npm ci` |
   | **Start Command** | `npm start` |
   | **Instance Type** | Free |

4. **Environment Variables** (botón *Add Environment Variable*):

   | Variable | Valor |
   |---|---|
   | `DATABASE_URL` | La cadena de Neon del paso 1 |
   | `JWT_SECRET` | Uno **nuevo**, distinto al de tu PC (ver abajo) |
   | `NODE_ENV` | `production` |

   **No** agregues `PORT`: Render lo asigna solo y el servidor lo lee de
   `process.env.PORT`.

   Para generar el `JWT_SECRET`, en PowerShell:

   ```powershell
   node -e "console.log(require('crypto').randomBytes(48).toString('hex'))"
   ```

   Copia el texto que imprime. Si algún día lo cambias, todas las sesiones
   abiertas se cierran (los usuarios vuelven a iniciar sesión).

5. En **Advanced → Health Check Path** escribe `/api/health`. Render la usa
   para saber si el servidor está vivo.
6. Toca **Create Web Service**. Render instala las dependencias y arranca el
   servidor. En la pestaña **Logs** deben aparecer:

   ```
   API de SubTrack escuchando en http://0.0.0.0:10000
   Base de datos al día: no hay migraciones pendientes.
   [cobros] al arrancar (2026-11-01): ...
   ```

   Si en cambio aparece **"ATENCIÓN: hay N migraciones pendientes"**, corre
   `npm run db:migrate:nube` desde tu PC (paso 2). El servidor **no** las
   aplica solo, a propósito.

   La versión de Node sale de `"engines": { "node": ">=24" }` en
   `backend/package.json`.

Con **Auto-Deploy** activado (viene así por defecto), cada push a esa rama
vuelve a desplegar el backend.

---

## 4. Probar la URL de Render

En el navegador (del PC o del celular) abre:

```
https://TU-SERVICIO.onrender.com/api/health
```

Debe responder:

```json
{"ok":true}
```

- Si el servicio estaba dormido, la primera vez tarda **cerca de 1 minuto**.
- `{"ok":false,"error":"Sin conexión a la base de datos"}` (503): revisa
  `DATABASE_URL` en Render (Environment) y que el proyecto de Neon exista.

Anota la URL exacta, **con https y sin barra al final**: la necesita la app.

---

## 5. Generar el APK release e instalarlo en el celular

El APK release apunta a la URL que le pases al compilar. En PowerShell, desde
la carpeta del proyecto (cambia la URL por la tuya):

```powershell
flutter build apk --release --flavor completa --dart-define=API_URL=https://TU-SERVICIO.onrender.com
```

El archivo queda en `build\app\outputs\flutter-apk\app-completa-release.apk`
(unos 55 MB). Con `--flavor sinSms` sale la versión sin "Buscar suscripciones
en mis SMS" (sin READ_SMS): `app-sinsms-release.apk`. Ver "Versiones completa
y sinSms" en [deteccion.md](deteccion.md).

- **La URL debe ser `https://`.** El APK release solo permite HTTPS
  (`android:usesCleartextTraffic="false"` en el manifest principal); el HTTP
  sin cifrar queda solo para debug y el backend local.
- **Firma:** para la entrega, el release se firma con la llave de debug
  (`android/app/build.gradle.kts`). Basta para instalarlo en cualquier
  celular. No hay llave de Play Store.
- Si compilas **sin** `--dart-define=API_URL=...`, la app apunta a
  `http://10.0.2.2:3000` y no podrá conectarse. Compila siempre con la URL.

**Instalarlo con el cable (lo más fácil):**

```powershell
adb install -r build\app\outputs\flutter-apk\app-completa-release.apk
```

`-r` reemplaza la versión instalada sin borrar sus datos (las dos versiones
están firmadas con la misma llave).

**Sin cable:** copia el APK al celular (Drive, WhatsApp a ti mismo, USB) y
ábrelo desde el administrador de archivos. Android pedirá permitir "instalar
apps de origen desconocido" para esa app. Instalada así, al dar el acceso a
notificaciones puede aparecer **"Ajuste restringido"**: la pantalla de
permisos de SubTrack explica cómo habilitarlo.

**Diferencias del APK release** con lo que probabas por USB:

- No existe la pantalla de depuración ni el modo descubrimiento.
- **No se pueden simular pagos con adb** (`com.android.shell` solo se permite
  en debug). La detección funciona con SMS reales de la app de SMS
  predeterminada (ver [probar-la-app.md](probar-la-app.md)).
- No escribe logs del lector.

Para desarrollar contra la nube con hot reload (y simular pagos con adb), usa
la configuración **"Celular (nube)"** de `.vscode/launch.json`, después de
cambiar `TU-SERVICIO` por el nombre real.

> **Probar siempre el APK release en el celular antes de dar por terminado un
> cambio; R8 puede romper clases que en debug funcionan.** El release pasa por
> R8 (minify), que borra lo que no ve usado, incluidas clases que una librería
> crea por reflexión. Ejemplo real: WorkManager (encargo B) cerraba la app al
> abrir (`NoSuchMethodException: androidx.work.impl.WorkDatabase_Impl.<init>`).
> Las reglas para conservarlas están en `android/app/proguard-rules.pro`.

---

## 6. Antes de una demostración, y límites del plan gratuito

### Despertar el servidor

Render **duerme el servicio tras 15 minutos sin tráfico** y tarda **cerca de 1
minuto** en despertar. Entre 2 y 5 minutos antes de mostrar la app:

1. Abre `https://TU-SERVICIO.onrender.com/api/health` en el navegador y espera
   el `{"ok":true}`.
2. Abre la app una vez (o inicia sesión con `demo@subtrack.co`).

Mientras siga usándose, no se vuelve a dormir. Si se duerme a mitad de la
demo, la app muestra **"Despertando el servidor, puede tardar hasta un
minuto…"** y espera hasta 75 s en vez de fallar a los 10 s. No reintenta la
petición: Render la retiene mientras despierta y después la procesa.

### Límites (plan gratuito)

| Servicio | Límite | Qué significa para SubTrack |
|---|---|---|
| Render | Se duerme tras 15 min sin tráfico; ~1 min en despertar | Ver arriba. La primera petición del día es lenta |
| Render | Horas de instancia gratuitas al mes (750 al escribir esto) | Alcanzan para un servicio encendido todo el mes |
| Render | Sin disco persistente; los logs no se guardan mucho tiempo | No afecta: los datos están en Neon |
| Render | La tarea de cobros de las 00:05 no corre si el servidor está dormido | Al despertar, el servidor procesa los cobros atrasados (los registra al arrancar) |
| Render | Recordatorios | No dependen del servidor: los programa el celular |
| Neon | La base se suspende tras unos minutos sin uso | Despierta en menos de un segundo con la primera consulta |
| Neon | Almacenamiento y horas de cómputo limitados | Sobra para el proyecto; revisa los límites actuales en la página de precios de Neon |

### Si algo sale mal

| Síntoma | Qué revisar |
|---|---|
| La app dice "No se pudo conectar con el servidor" al instante | La URL del APK (¿`https`? ¿sin barra final?) y que el celular tenga internet |
| "El servidor está tardando en despertar" | Abre `/api/health` en el navegador, espera el `{"ok":true}` y vuelve a intentarlo |
| `/api/health` responde 503 | `DATABASE_URL` en Render; que el proyecto de Neon exista |
| Errores de tablas que no existen | Faltan migraciones: `npm run db:migrate:nube` (los logs de Render lo avisan) |
| "Tu sesión expiró" después de cambiar el `JWT_SECRET` | Normal: inicia sesión de nuevo |

### Si se filtra la cadena de Neon

En Neon, **Roles → Reset password** para el usuario de la base. Copia la
nueva cadena en `backend/.env.produccion` y en la variable `DATABASE_URL` de
Render (Render vuelve a desplegar solo).
