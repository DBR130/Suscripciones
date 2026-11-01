package com.example.flutter_suscripciones.deteccion

import android.content.Context
import android.provider.Telephony

/**
 * La app de SMS predeterminada del usuario (Mensajes de Google, Truecaller,
 * Mensajes de Samsung...). Se trata como una app permitida más, con el mismo
 * filtro de cobro: así la detección funciona con cualquier app de SMS sin
 * tener que agregarlas una por una a res/raw/deteccion_apps.json.
 *
 * Se vuelve a consultar al abrir la app (o volver a ella) y cuando el lector
 * se conecta, por si el usuario cambió de app de SMS.
 */
object AppSmsPredeterminada {
    @Volatile
    private var paquete: String? = null

    @Volatile
    private var consultada = false

    /** Consulta a Android cuál es la app de SMS predeterminada. */
    fun actualizar(context: Context, motivo: String): String? {
        val nuevo = try {
            Telephony.Sms.getDefaultSmsPackage(context)
        } catch (e: Exception) {
            // Tablets sin telefonía o celulares raros: no hay app de SMS.
            null
        }
        if (!consultada || nuevo != paquete) {
            RegistroDeteccion.log(context, "App de SMS predeterminada ($motivo): ${nuevo ?: "ninguna"}")
        }
        paquete = nuevo
        consultada = true
        return nuevo
    }

    /** La última consultada (la consulta si aún no se ha hecho). */
    fun paquete(context: Context): String? =
        if (consultada) paquete else actualizar(context, "primera consulta")

    /** Nombre visible de la app ("Truecaller"), o uno genérico si Android no lo da. */
    fun nombre(context: Context, paquete: String): String = try {
        val pm = context.packageManager
        pm.getApplicationLabel(pm.getApplicationInfo(paquete, 0)).toString()
    } catch (e: Exception) {
        "App de SMS predeterminada"
    }
}
