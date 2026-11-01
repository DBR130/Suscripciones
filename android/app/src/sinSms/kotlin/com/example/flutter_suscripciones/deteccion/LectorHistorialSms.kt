package com.example.flutter_suscripciones.deteccion

import android.content.Context

/**
 * Versión "sinSms": no existe la búsqueda en el historial de SMS. La app no
 * declara READ_SMS y este archivo no lee nada; Flutter oculta la opción.
 * La versión "completa" está en src/completa.
 */
object LectorHistorialSms {
    const val DISPONIBLE = false
    val PERMISO: String? = null

    @Suppress("UNUSED_PARAMETER")
    fun permisoConcedido(context: Context): Boolean = false

    @Suppress("UNUSED_PARAMETER")
    fun leer(context: Context, desdeMs: Long): Map<String, Any?> = emptyMap()
}
