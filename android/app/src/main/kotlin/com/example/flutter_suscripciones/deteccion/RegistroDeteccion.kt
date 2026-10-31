package com.example.flutter_suscripciones.deteccion

import android.content.Context
import android.util.Log

/** Tag fijo de los logs: adb logcat -v time -s SubTrackDeteccion:V (ver docs/deteccion.md). */
const val TAG = "SubTrackDeteccion"

/**
 * Horas de la última conexión, desconexión y notificación del lector, en
 * SharedPreferences para que sobrevivan si Android mata el proceso. Las
 * muestra la pantalla de depuración. Nunca guarda el texto ni el paquete de
 * las notificaciones: solo la hora y el resultado.
 */
object RegistroDeteccion {
    private const val ARCHIVO = "subtrack_deteccion"

    private fun prefs(context: Context) =
        context.applicationContext.getSharedPreferences(ARCHIVO, Context.MODE_PRIVATE)

    fun marcarConexion(context: Context) =
        prefs(context).edit().putLong("ultima_conexion", System.currentTimeMillis()).apply()

    fun marcarDesconexion(context: Context) =
        prefs(context).edit().putLong("ultima_desconexion", System.currentTimeMillis()).apply()

    /** resultado: "guardada", "repetida", "descartada" o "app no permitida". */
    fun marcarNotificacion(context: Context, resultado: String) =
        prefs(context).edit()
            .putLong("ultima_notificacion", System.currentTimeMillis())
            .putString("ultimo_resultado", resultado)
            .apply()

    fun leer(context: Context): Map<String, Any?> {
        val p = prefs(context)
        fun hora(clave: String): Long? = p.getLong(clave, 0L).takeIf { it > 0 }
        return mapOf(
            "ultima_conexion" to hora("ultima_conexion"),
            "ultima_desconexion" to hora("ultima_desconexion"),
            "ultima_notificacion" to hora("ultima_notificacion"),
            "ultimo_resultado" to p.getString("ultimo_resultado", null),
        )
    }

    /** Logs detallados (con paquete) solo en debug; nunca el texto de la notificación. */
    fun log(context: Context, mensaje: String) {
        if (ConfiguracionDeteccion.esDebug(context)) Log.i(TAG, mensaje)
    }
}
