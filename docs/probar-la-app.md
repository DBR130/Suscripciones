# Cómo probar SubTrack (guía para probadores)

Esta guía es para ti si vas a probar SubTrack en tu celular. No necesitas saber
programar. Tardas unos 15 minutos.

**Qué hace la app:** SubTrack lleva la cuenta de tus suscripciones (Netflix,
Spotify…). Además puede **detectarlas sola**: cuando tu banco te manda un SMS
de cobro, la app lo lee y te pregunta si es una suscripción.

**Qué necesitas:**

- Un celular Android (Xiaomi, Samsung, Motorola…).
- El archivo de la app (termina en `.apk`), que te envía el equipo.
- Que alguien te pueda enviar un SMS de prueba (ver la sección 5).

> Los nombres de los menús pueden cambiar un poco según la marca y la versión
> de tu celular. Si no encuentras una opción, usa la **lupa de Ajustes** y
> escribe la palabra en negrita (por ejemplo, "restringido" o "SMS").

---

## 1. Instalar la app

La app todavía no está en Play Store, así que se instala desde el archivo.

1. Abre el archivo `.apk` que te enviaron (desde WhatsApp, Drive o la app
   **Archivos** del celular).
2. Android dice que por seguridad no puede instalar apps de esa fuente. Toca
   **Ajustes** y activa **Permitir desde esta fuente** (o **Instalar apps
   desconocidas**). Vuelve atrás.
3. Toca **Instalar**.
4. Es normal que aparezca un aviso de **Play Protect** ("App no reconocida" o
   "App no segura"), porque la app no viene de Play Store. Toca **Más
   detalles** y luego **Instalar de todas formas**. Si pregunta si quieres
   enviar la app para que la analicen, puedes decir que no.
5. En Xiaomi puede aparecer además un análisis de seguridad propio. Espera a
   que termine y toca **Instalar** o **Continuar**.

La app puede aparecer en el celular con el nombre **flutter_suscripciones**.
Es SubTrack.

Ábrela, crea tu cuenta y, si pregunta si puede **enviarte notificaciones**,
toca **Permitir** (así te avisa de los cobros que detecta).

> La primera vez que abres la app puede tardar hasta un minuto en conectarse:
> el servidor gratuito "se duerme" cuando nadie lo usa. La app te avisa que lo
> está despertando. Es normal.

---

## 2. Dar el acceso a notificaciones

Para leer los SMS de cobro, SubTrack necesita el **acceso a notificaciones**.

1. En la app, en la pantalla de detección automática, toca **Dar permiso y
   detectar**. Se abre el ajuste de Android.
2. Busca **SubTrack** (o **flutter_suscripciones**) y activa el interruptor.
3. Android muestra un aviso fuerte diciendo que la app podrá leer tus
   notificaciones. Toca **Permitir**.
4. Vuelve a SubTrack.

**Qué lee y qué no:** Android le entrega a la app todas las notificaciones,
pero SubTrack solo mira las de tu app de SMS. De ahí solo guarda los mensajes
que parecen un cobro, y al servidor solo envía el banco, el comercio, el monto
y la fecha, nunca el texto completo. No lee WhatsApp, correos ni redes
sociales.

### Si aparece "Ajuste restringido"

Como la app no viene de Play Store, Android puede bloquear el interruptor con
el mensaje **"Ajuste restringido"** (o "Configuración restringida"). Se
habilita así:

**Xiaomi (HyperOS / MIUI):**

1. Intenta activar el acceso una vez (para que aparezca el aviso) y ciérralo.
2. Ve a **Ajustes → Aplicaciones → Administrar aplicaciones → SubTrack**
   (o flutter_suscripciones).
3. Toca los **tres puntos ⋮** de arriba a la derecha y luego **Permitir
   configuración restringida**. Confirma con tu PIN o huella.
4. Vuelve al paso 2 de esta sección y activa el acceso.

**Samsung (One UI):**

1. Intenta activar el acceso una vez (para que aparezca el aviso) y ciérralo.
2. Ve a **Ajustes → Aplicaciones → SubTrack** (o flutter_suscripciones).
3. Toca los **tres puntos ⋮** de arriba a la derecha y luego **Permitir
   ajustes restringidos**. Confirma con tu PIN o huella.
4. Vuelve al paso 2 de esta sección y activa el acceso.

Si no ves los tres puntos, busca "restringido" en la lupa de Ajustes.

---

## 3. Quitar la restricción de batería

Para ahorrar batería, Xiaomi y Samsung pueden **detener la app** cuando no la
usas, y entonces no detecta los SMS. Quita la restricción:

**Xiaomi (HyperOS / MIUI):**

1. **Ajustes → Aplicaciones → Administrar aplicaciones → SubTrack**.
2. Activa **Inicio automático**.
3. Entra a **Ahorro de batería** y elige **Sin restricciones**.

**Samsung (One UI):**

1. **Ajustes → Aplicaciones → SubTrack → Batería** y elige **Sin
   restricciones**.
2. Revisa también **Ajustes → Batería → Límites de uso en segundo plano**:
   SubTrack **no** debe estar en "Aplicaciones en suspensión" ni en
   "Aplicaciones en suspensión profunda". Si quieres, agrégala a
   "Aplicaciones que nunca se suspenden".

---

## 4. Ver cuál es tu app de SMS

SubTrack lee los SMS de tu **app de SMS predeterminada** (la que usas para
mensajes de texto), sea cual sea: Mensajes de Google, Mensajes de Samsung,
Mensajes de Xiaomi, Truecaller… Para saber cuál es:

**Xiaomi:** **Ajustes → Aplicaciones → Administrar aplicaciones → tres puntos
⋮ → Aplicaciones predeterminadas → Mensajes** (o **SMS**).

**Samsung:** **Ajustes → Aplicaciones → Elegir aplicaciones predeterminadas →
Aplicación de SMS**.

En cualquier celular: busca "**SMS**" en la lupa de Ajustes.

Cuéntale al equipo cuál tienes. Si recibes los SMS del banco en una app
distinta a la predeterminada, también avísanos.

---

## 5. SMS de prueba

Pídele a alguien que te envíe **por SMS** (mensaje de texto normal, no
WhatsApp) uno de estos mensajes, copiado tal cual. No importa desde qué número
llegue: la app reconoce el banco por el texto.

**Formato Bancolombia:**

```
Bancolombia: Compraste $19.900,00 en NETFLIX con tu T.Deb *1234, el 01/11/2026 a las 10:30.
```

**Formato Nequi:**

```
NEQUI: Pagaste 26.900 en SPOTIFY
```

(Puedes cambiar el comercio, por ejemplo por DISNEY PLUS o YOUTUBE PREMIUM, y
el monto. Mantén el resto igual.)

**Qué debería pasar:**

1. Te llega el SMS como siempre. SubTrack lo guarda en silencio, aunque la app
   esté cerrada.
2. Abre SubTrack (o vuelve a ella). En unos segundos llega una notificación:
   **"¿Tienes una suscripción a Netflix?"**.
3. Tócala: la app te muestra el cobro para **confirmarlo** como suscripción o
   **descartarlo**.
4. Si lo confirmas, aparece en tu lista de suscripciones, en el inicio.

**Estos NO deberían detectarse** (si alguno se detecta, avísanos):

- Un SMS normal: `Hola, ¿cómo vas?`
- Un código: `Bancolombia: tu codigo para la compra de $19.900 es 123456`
- Dinero recibido: `NEQUI: Recibiste 50.000 de JUAN PEREZ`
- Una llamada perdida o un aviso de spam de Truecaller.

---

## 6. Si la app dice "Detección pausada"

A veces Android "desconecta" el lector de SubTrack, sobre todo **después de
instalar una versión nueva** de la app o de reiniciar el celular. La app
intenta reconectarse sola. Si no lo logra, en **Perfil** dice **"Detección
pausada · toca para reactivarla"** y en el inicio aparece el aviso **"La
detección está pausada"**.

Para arreglarlo:

1. Toca **Abrir el ajuste** en el aviso (o el interruptor en Perfil).
2. **Desactiva** el acceso de SubTrack.
3. **Vuelve a activarlo** (y confirma con **Permitir**).
4. Regresa a SubTrack: el aviso desaparece y Perfil dice **"Activo"**.

Si vuelve a pausarse seguido, revisa la sección 3 (batería).

---

## Qué reportar al equipo

- Marca y modelo del celular.
- Tu app de SMS predeterminada (sección 4).
- Qué SMS de prueba te enviaron y qué pasó (¿llegó la notificación? ¿cuánto
  tardó?).
- Capturas de pantalla de cualquier error o aviso raro.
