package com.example.flutter_suscripciones.deteccion

import android.app.Notification
import android.os.Build
import android.os.Bundle
import android.os.Parcelable
import android.service.notification.NotificationListenerService
import android.service.notification.StatusBarNotification
import org.json.JSONObject

/**
 * Lector de notificaciones de pago (RF02). Android lo ejecuta aunque la app
 * esté cerrada, una vez el usuario da el "Acceso a notificaciones".
 *
 * Por cada notificación:
 *  1. Si la app que la publicó no está en la lista permitida, se ignora
 *     (en modo descubrimiento, solo se informa el paquete y el título).
 *  2. Si el texto no parece un cobro, se descarta sin guardarlo.
 *  3. Si parece un cobro, se guarda en la cola local y, si la app está
 *     abierta, se envía en vivo a Flutter.
 */
class LectorNotificacionesService : NotificationListenerService() {

    companion object {
        /** true mientras Android mantiene el servicio conectado. */
        @Volatile
        var conectado = false
            private set

        /**
         * Solo en debug y solo en memoria: informa paquete y título de
         * notificaciones de apps NO permitidas (nunca su texto), para poder
         * identificar los paquetes del banco y de la app de SMS.
         */
        @Volatile
        var modoDescubrimiento = false

        /** Lo conecta CanalDeteccion mientras Flutter escucha el EventChannel. */
        @Volatile
        var oyente: ((Map<String, Any?>) -> Unit)? = null
    }

    override fun onListenerConnected() {
        conectado = true
    }

    override fun onListenerDisconnected() {
        conectado = false
    }

    override fun onNotificationPosted(sbn: StatusBarNotification) {
        try {
            procesar(sbn)
        } catch (e: Exception) {
            // Nunca tumbar el servicio por una notificación con formato raro.
        }
    }

    private fun procesar(sbn: StatusBarNotification) {
        val n = sbn.notification ?: return
        // Resúmenes de grupo y notificaciones fijas (música, descargas) no son cobros.
        if (n.flags and Notification.FLAG_GROUP_SUMMARY != 0) return
        if (sbn.isOngoing) return

        val config = ConfiguracionDeteccion.de(this)
        val paquete = sbn.packageName
        val titulo = n.extras.getCharSequence(Notification.EXTRA_TITLE)?.toString().orEmpty()

        if (!config.permitida(paquete)) {
            if (config.esDebug && modoDescubrimiento) {
                // Solo metadatos, solo en vivo: el texto de apps no permitidas no se lee.
                emitir(mapOf("tipo" to "descubierta", "paquete" to paquete, "titulo" to titulo,
                    "recibida_en" to sbn.postTime))
            }
            return
        }

        val texto = textoDe(n.extras)
        val motivo = FiltroCobros.motivoDescarte(texto, config)
        if (motivo != null) {
            if (config.esDebug && modoDescubrimiento) {
                emitir(mapOf("tipo" to "descartada", "paquete" to paquete, "titulo" to titulo,
                    "motivo" to motivo, "recibida_en" to sbn.postTime))
            }
            return // descartada: no se guarda
        }

        val huella = ColaNotificaciones.huella(paquete, titulo, texto, sbn.postTime)
        val notificacion = JSONObject()
            .put("id", huella)
            .put("paquete", paquete)
            .put("app", config.appsPermitidas[paquete] ?: paquete)
            .put("titulo", titulo)
            .put("texto", texto)
            .put("recibida_en", sbn.postTime)
        if (ColaNotificaciones.agregar(this, notificacion)) {
            emitir(mapOf("tipo" to "guardada", "notificacion" to aMapa(notificacion)))
        }
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

    private fun emitir(evento: Map<String, Any?>) {
        oyente?.invoke(evento)
    }
}

/** JSONObject -> Map, para enviarlo por los canales de Flutter. */
fun aMapa(json: JSONObject): Map<String, Any?> =
    json.keys().asSequence().associateWith { clave -> json.opt(clave).takeUnless { it == JSONObject.NULL } }
