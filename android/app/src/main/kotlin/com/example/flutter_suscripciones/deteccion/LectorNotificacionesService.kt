package com.example.flutter_suscripciones.deteccion

import android.app.Notification
import android.os.Build
import android.os.Bundle
import android.os.Parcelable
import android.service.notification.NotificationListenerService
import android.service.notification.StatusBarNotification
import org.json.JSONObject
import java.lang.ref.WeakReference

/**
 * Lector de notificaciones de pago (RF02). Android lo ejecuta aunque la app
 * esté cerrada, una vez el usuario da el "Acceso a notificaciones".
 *
 * Por cada notificación:
 *  1. Si la app que la publicó no está en la lista permitida ni es la app de
 *     SMS predeterminada del usuario (AppSmsPredeterminada), se ignora
 *     sin leer su título ni su texto (en modo descubrimiento, solo se informa
 *     el paquete).
 *  2. Si el texto no parece un cobro, se descarta sin guardarlo.
 *  3. Si parece un cobro, se guarda en la cola local y, si la app está
 *     abierta, se envía en vivo a Flutter.
 *
 * El guardado (paso 3) es 100 % nativo: no depende de Flutter ni de que la
 * app esté abierta. El aviso en vivo es opcional y nunca puede tumbar el
 * servicio.
 *
 * Además, cada vez que el servicio se (re)conecta revisa las notificaciones
 * activas de la barra: así recupera las que llegaron mientras estaba detenido
 * (por ejemplo, si MIUI cerró la app al quitarla de recientes).
 */
class LectorNotificacionesService : NotificationListenerService() {

    companion object {
        /** true mientras Android mantiene el servicio conectado. */
        @Volatile
        var conectado = false
            private set

        /**
         * Solo en debug y solo en memoria: informa el paquete de las
         * notificaciones de apps NO permitidas (nunca su título ni su texto:
         * en chats y SMS el título es el nombre del contacto), para poder
         * identificar los paquetes del banco y de la app de SMS.
         */
        @Volatile
        var modoDescubrimiento = false

        /** Lo conecta CanalDeteccion mientras Flutter escucha el EventChannel. */
        @Volatile
        var oyente: ((Map<String, Any?>) -> Unit)? = null

        @Volatile
        private var instancia: WeakReference<LectorNotificacionesService>? = null

        /**
         * Revisa las notificaciones activas de la barra si el servicio está
         * conectado. Devuelve cuántas se guardaron, o null si no está conectado.
         */
        fun recuperarActivasSiConectado(): Int? =
            instancia?.get()?.takeIf { conectado }?.recuperarActivas()
    }

    override fun onListenerConnected() {
        conectado = true
        instancia = WeakReference(this)
        RegistroDeteccion.marcarConexion(this)
        RegistroDeteccion.log(this, "Servicio conectado")
        // Por si el usuario cambió de app de SMS mientras el lector no estaba.
        AppSmsPredeterminada.actualizar(this, "servicio conectado")
        recuperarActivas()
    }

    override fun onListenerDisconnected() {
        conectado = false
        RegistroDeteccion.marcarDesconexion(this)
        RegistroDeteccion.log(this, "Servicio desconectado: se intenta reconectar")
        // Si el permiso sigue activo, intenta reconectarlo (si el usuario quitó
        // el acceso, ReconexionLector no hace nada).
        ReconexionLector.reconectar(this, "servicio desconectado")
    }

    override fun onNotificationPosted(sbn: StatusBarNotification) {
        try {
            val resultado = procesar(sbn)
            RegistroDeteccion.log(this, "Recibida de ${sbn.packageName}: $resultado")
        } catch (e: Exception) {
            // Nunca tumbar el servicio por una notificación con formato raro.
            RegistroDeteccion.log(this, "Error procesando una notificación de ${sbn.packageName}", e)
        }
    }

    /** Recorre las notificaciones activas y guarda las que falten (sin duplicar). */
    fun recuperarActivas(): Int {
        val activas = try {
            activeNotifications ?: emptyArray()
        } catch (e: Exception) {
            // Puede fallar si el servicio aún no termina de conectarse.
            RegistroDeteccion.log(this, "No se pudieron leer las notificaciones activas", e)
            return 0
        }
        var guardadas = 0
        for (sbn in activas) {
            try {
                if (procesar(sbn, enVivo = false) == "guardada") guardadas++
            } catch (e: Exception) {
                RegistroDeteccion.log(this, "Error recuperando una notificación activa", e)
            }
        }
        RegistroDeteccion.log(this, "Notificaciones activas revisadas: ${activas.size}, guardadas: $guardadas")
        return guardadas
    }

    /**
     * Aplica los filtros y guarda si corresponde. Devuelve el resultado para
     * los logs: "guardada", "repetida", "descartada (motivo)", "app no
     * permitida" o "ignorada (motivo)".
     *
     * enVivo = false cuando viene de recuperarActivas(): no cuenta como
     * "última notificación recibida" ni informa apps no permitidas.
     */
    private fun procesar(sbn: StatusBarNotification, enVivo: Boolean = true): String {
        val n = sbn.notification ?: return "ignorada (sin contenido)"
        // Resúmenes de grupo y notificaciones fijas (música, descargas) no son cobros.
        if (n.flags and Notification.FLAG_GROUP_SUMMARY != 0) return "ignorada (resumen de grupo)"
        if (sbn.isOngoing) return "ignorada (notificación fija)"
        // Llamadas entrantes y perdidas (por ejemplo, el identificador de
        // llamadas de Truecaller): nunca son cobros. "missed_call" es
        // Notification.CATEGORY_MISSED_CALL (Android 13+).
        if (n.category == Notification.CATEGORY_CALL || n.category == "missed_call") return "ignorada (llamada)"

        val config = ConfiguracionDeteccion.de(this)
        val paquete = sbn.packageName

        if (!config.permitida(this, paquete)) {
            if (!enVivo) return "app no permitida"
            RegistroDeteccion.marcarNotificacion(this, "app no permitida")
            if (config.esDebug && modoDescubrimiento) {
                // Solo el paquete, solo en vivo: de apps no permitidas no se lee
                // ni el título (nombre del contacto en chats y SMS) ni el texto.
                emitir(mapOf("tipo" to "descubierta", "paquete" to paquete, "recibida_en" to sbn.postTime))
            }
            return "app no permitida"
        }

        val titulo = n.extras.getCharSequence(Notification.EXTRA_TITLE)?.toString().orEmpty()

        val texto = textoDe(n.extras)
        val motivo = FiltroCobros.motivoDescarte(texto, config)
        if (motivo != null) {
            if (enVivo) {
                RegistroDeteccion.marcarNotificacion(this, "descartada")
                if (config.esDebug && modoDescubrimiento) {
                    // Sin título: en la app de SMS es el nombre del contacto.
                    emitir(mapOf("tipo" to "descartada", "paquete" to paquete, "motivo" to motivo,
                        "recibida_en" to sbn.postTime))
                }
            }
            return "descartada ($motivo)" // no se guarda
        }

        val huella = ColaNotificaciones.huella(paquete, titulo, texto, sbn.postTime)
        val notificacion = JSONObject()
            .put("id", huella)
            .put("paquete", paquete)
            .put("app", config.nombreDe(this, paquete))
            .put("titulo", titulo)
            .put("texto", texto)
            .put("recibida_en", sbn.postTime)
        val guardada = ColaNotificaciones.agregar(this, notificacion)
        if (enVivo) RegistroDeteccion.marcarNotificacion(this, if (guardada) "guardada" else "repetida")
        if (!guardada) return "repetida"
        emitir(mapOf("tipo" to "guardada", "notificacion" to aMapa(notificacion)))
        return "guardada"
    }

    /** El texto más completo disponible: texto largo, mensajes (SMS) o texto corto. */
    private fun textoDe(extras: Bundle): String {
        extras.getCharSequence(Notification.EXTRA_BIG_TEXT)?.toString()
            ?.takeIf { it.isNotBlank() }?.let { return it }

        // Apps de SMS como Google Mensajes usan MessagingStyle: el último mensaje.
        val mensajes = arregloDeParcelables(extras, Notification.EXTRA_MESSAGES)
        val ultimo = mensajes?.lastOrNull() as? Bundle
        ultimo?.getCharSequence("text")?.toString()?.takeIf { it.isNotBlank() }?.let { return it }

        return extras.getCharSequence(Notification.EXTRA_TEXT)?.toString().orEmpty()
    }

    @Suppress("DEPRECATION")
    private fun arregloDeParcelables(extras: Bundle, clave: String): Array<out Parcelable>? =
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            extras.getParcelableArray(clave, Parcelable::class.java)
        } else {
            extras.getParcelableArray(clave)
        }

    /** Aviso en vivo a Flutter. Si falla (app cerrada), no afecta el guardado. */
    private fun emitir(evento: Map<String, Any?>) {
        try {
            oyente?.invoke(evento)
        } catch (e: Exception) {
            RegistroDeteccion.log(this, "No se pudo enviar el evento en vivo", e)
        }
    }
}

/** JSONObject -> Map, para enviarlo por los canales de Flutter. */
fun aMapa(json: JSONObject): Map<String, Any?> =
    json.keys().asSequence().associateWith { clave -> json.opt(clave).takeUnless { it == JSONObject.NULL } }
