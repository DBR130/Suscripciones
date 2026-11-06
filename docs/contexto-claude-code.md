# SubTrack: contexto para Claude Code (traspaso a Santiago)

> **Copia este archivo como `CLAUDE.md` en la raíz del repo antes de empezar.**
> (`CLAUDE.md` está en `.gitignore`: cada uno tiene su copia local.)

Responde y documenta **en español**.

## Qué es

App Android para controlar suscripciones (streaming, software, gimnasio):
costo, frecuencia de cobro, recordatorios, guías para cancelar, ahorro y
**detección automática** de cobros desde las notificaciones de SMS del banco.

| Parte | Tecnología | Dónde |
|---|---|---|
| App | Flutter (Dart), go_router, flutter_secure_storage, flutter_local_notifications, fl_chart | `lib/` |
| Nativo | Kotlin: lector de notificaciones, filtro de cobros, cola, reconexión, WorkManager | `android/app/src/main/kotlin/.../deteccion/` |
| Backend | Node + Express 5, en **Render** (`https://subtrack-api-4150.onrender.com`, plan gratis: se duerme a los 15 min, ~1 min en despertar) | `backend/` |
| Base de datos | PostgreSQL en **Neon** (local: `subtrack`; tests: `subtrack_test`) | `backend/db/migraciones/` |

### Carpetas clave

| Carpeta | Qué hay |
|---|---|
| `lib/deteccion/` | Parser, analizador, almacén cifrado local, procesador de la cola, tarea de fondo (`segundo_plano.dart`), turno, pantallas 03/04/05, Compartir, depuración |
| `lib/services/`, `lib/Pages/`, `lib/widgets/`, `lib/Common/` | API, sesión, recordatorios; pantallas; barra flotante y animaciones; tema y rutas |
| `android/app/src/completa/`, `src/sinSms/`, `src/debug/` | Lo propio de cada versión; receptor solo de debug |
| `backend/src/`, `backend/db/` | API; migraciones SQL, `guias.json` (catálogo), `procesadores.json`, demo |
| `test/` (+ `test/fixtures/` con SMS reales), `backend/test/`, `android/app/src/test/` | Tests |
| `docs/` | `deteccion.md` (**la referencia de la detección**: arquitectura, privacidad, decisiones, cómo probar cada hito), `despliegue.md`, `google-play.md`, `probar-la-app.md`, `tickets/` |
| `design/` | `subtrack-simulacion.html` (fuente visual, manda) y `subtrack-pantallas.md` |

## Reglas de trabajo

- **Ramas:** `main` (estable, etiqueta `v1.0`), `develop` (pruebas; **Render
  despliega desde `develop`**: un merge ahí publica el backend), `David`,
  `santiago` (la de Santiago). Trabaja solo en tu rama; commits pequeños y
  descriptivos; no hagas push ni merge sin que el dueño lo pida.
- **Nunca subir `backend/.env` ni `backend/.env.produccion`** (en
  `.gitignore`). Nunca commitear secretos (cadena de Neon, `JWT_SECRET`).
- **Enmascarar tarjetas:** en tests, fixtures, docs y logs, solo `*0000`.
- **Privacidad:** el texto de los SMS nunca va al backend, solo campos
  extraídos (banco, comercio, monto, moneda, fecha, huella). No leer correos
  ni chats. No inventar nombres de paquete. No ampliar el parser a formatos
  no vistos en SMS reales.
- **No cambiar el `applicationId`** (`com.example.flutter_suscripciones`): se
  pierden datos, sesión y acceso a notificaciones al reinstalar.
- **Flavors:** `completa` (con READ_SMS para el historial, predeterminado) y
  `sinSms`. Todo cambio debe funcionar en las dos.
- **Compilar siempre con** `--dart-define=API_URL=https://subtrack-api-4150.onrender.com`
  (sin eso la app apunta a `http://10.0.2.2:3000`).
- **Antes de cambiar de rama:** `git restore linux macos windows` (solo
  cambian por fines de línea; nunca commitearlos).
- **Tests del backend nunca tocan la base real:** usan `subtrack_test`; un
  candado (`backend/src/utils/candadoBd.js`) lo impide. En los tests, importa
  `src/db.js` dentro de `before()`, nunca con `import` estático.
- **Al terminar:** `flutter analyze` sin avisos, `flutter test` y `npm test`
  pasando; mantener `docs/deteccion.md` al día.

## Comandos (PowerShell, desde la raíz)

```powershell
# Pruebas
flutter analyze
flutter test
cd backend; npm test; cd ..                       # contra subtrack_test
$env:JAVA_HOME = 'C:\Program Files\Android\Android Studio\jbr'
cd android; .\gradlew.bat :app:testCompletaDebugUnitTest; cd ..   # nativas (JUnit)

# Migraciones y catálogo (en backend/)
npm run db:migrate          # local
npm run db:migrate:nube     # Neon (usa .env.produccion)
npm run db:guias            # catálogo local;  db:guias:nube para Neon

# Compilar e instalar
flutter build apk --release --flavor completa --dart-define=API_URL=https://subtrack-api-4150.onrender.com
flutter build apk --release --flavor sinSms   --dart-define=API_URL=https://subtrack-api-4150.onrender.com
flutter build apk --debug   --flavor completa --dart-define=API_URL=https://subtrack-api-4150.onrender.com
adb install -r build\app\outputs\flutter-apk\app-completa-debug.apk

# Logs (solo debug) y depuración
adb logcat -v time -s SubTrackDeteccion:V flutter:V
adb shell am broadcast -a com.example.flutter_suscripciones.PROCESAR_COLA -p com.example.flutter_suscripciones   # forzar la tarea de fondo
```

Simular un cobro y más comandos: `docs/deteccion.md` › "Cómo probar".

## Estado actual

- Fases 1–5 (auth, suscripciones, recordatorios, cancelación, despliegue) y
  fase de diseño: hechas.
- Detección automática, hitos 1–8: hechos (ver tabla al inicio de
  `docs/deteccion.md`).
- **Encargo A** (hallazgos de pruebas reales, hito 7: unir duplicados, series
  dentro de una mezcla, precio de referencia de ambiguos, diagnóstico) y
  **encargo B** (hito 8: aviso al instante con la app cerrada, WorkManager
  `ProcesarColaWorker` + motor de Flutter sin pantalla + turno entre la app y
  la tarea de fondo): **terminados y probados en el Xiaomi**.
- **Hallazgo de HyperOS:** la tarea de fondo depende del **autoencendido
  (Inicio automático)** de SubTrack; sin él, HyperOS la retrasa o no la deja
  correr con la app cerrada. Detalle en `docs/deteccion.md` › hito 8 › "Xiaomi
  (HyperOS) y Android".
- Backend sin cambios ni migraciones en el encargo B.
- **Fechas:** congelamiento **12 de noviembre**; entrega **19 de noviembre**.

### Decisiones que no se reabren

Están en `docs/deteccion.md` (privacidad, apps de SMS permitidas, reconexión,
historial opcional, compras normales en el celular, duplicados, procesadores,
ambiguos con precio de referencia, series, descartes, cambio de precio 5 % /
15 % convertidos, tarea de fondo y turno). Léelas antes de proponer cambios.

## Pendiente

1. **Encargo C** (texto completo abajo).
2. Antes de subir a `develop`: migraciones 008–010 y catálogo en Neon
   (`npm run db:migrate:nube`, `npm run db:guias:nube`).
3. **Merge a `develop`** (despliega en Render), **APK release** de las dos
   versiones con `--dart-define=API_URL=...` y **etiqueta de versión**.

## Encargo C (texto original, sin cambios)

Encargo C:
[PEGA AQUÍ EL PROMPT DEL ENCARGO C]
