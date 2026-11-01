package com.example.flutter_suscripciones.deteccion

import android.Manifest
import android.content.Context
import android.content.pm.PackageManager
import android.provider.Telephony

/**
 * Versión "completa": lee el historial de SMS recibidos desde el proveedor de
 * SMS de Android (funciona con cualquier app de SMS, incluido Truecaller).
 * Solo se usa cuando el usuario toca "Buscar en mis SMS" y concede READ_SMS.
 *
 * Privacidad: aquí mismo se aplica el filtro de cobro (FiltroCobros). Los SMS
 * que no parecen cobros se descartan sin salir de esta función; a Flutter
 * solo pasan el texto y la fecha de los que parecen cobros, y de ahí al
 * backend solo los campos extraídos (ver docs/deteccion.md).
 *
 * La versión "sinSms" tiene otro archivo con el mismo nombre que no lee nada.
 */
object LectorHistorialSms {
    const val DISPONIBLE = true
    val PERMISO: String? = Manifest.permission.READ_SMS

    /** Tope de SMS de cobro que se devuelven (los más recientes). */
    private const val MAXIMO = 2000

    fun permisoConcedido(context: Context): Boolean =
        context.checkSelfPermission(Manifest.permission.READ_SMS) == PackageManager.PERMISSION_GRANTED

    /**
     * SMS recibidos desde [desdeMs] (milisegundos) que parecen cobros, del más
     * reciente al más antiguo. También cuenta cuántos se leyeron y cuántos
     * vienen de remitentes de empresa (números cortos o nombres), para saber
     * si Xiaomi está ocultando los SMS de servicio.
     */
    fun leer(context: Context, desdeMs: Long): Map<String, Any?> {
        val config = ConfiguracionDeteccion.de(context)
        val mensajes = ArrayList<Map<String, Any?>>()
        var leidos = 0
        var deEmpresas = 0
        val columnas = arrayOf(Telephony.Sms._ID, Telephony.Sms.ADDRESS, Telephony.Sms.BODY, Telephony.Sms.DATE)
        context.contentResolver.query(
            Telephony.Sms.Inbox.CONTENT_URI,
            columnas,
            "${Telephony.Sms.DATE} >= ?",
            arrayOf(desdeMs.toString()),
            "${Telephony.Sms.DATE} DESC",
        )?.use { c ->
            val iId = c.getColumnIndexOrThrow(Telephony.Sms._ID)
            val iRemitente = c.getColumnIndexOrThrow(Telephony.Sms.ADDRESS)
            val iTexto = c.getColumnIndexOrThrow(Telephony.Sms.BODY)
            val iFecha = c.getColumnIndexOrThrow(Telephony.Sms.DATE)
            while (c.moveToNext()) {
                leidos++
                if (esRemitenteDeEmpresa(c.getString(iRemitente).orEmpty())) deEmpresas++
                val texto = c.getString(iTexto).orEmpty()
                // Lo que no parece un cobro se descarta aquí, en memoria.
                if (mensajes.size < MAXIMO && FiltroCobros.motivoDescarte(texto, config) == null) {
                    mensajes.add(mapOf("id" to "sms:${c.getLong(iId)}", "texto" to texto, "fecha" to c.getLong(iFecha)))
                }
            }
        }
        // Solo cantidades: nunca el texto ni el remitente.
        RegistroDeteccion.log(
            context,
            "Historial de SMS: $leidos leídos ($deEmpresas de empresas), ${mensajes.size} parecen cobro",
        )
        return mapOf("mensajes" to mensajes, "leidos" to leidos, "de_empresas" to deEmpresas)
    }

    /** Números cortos (85954) o nombres ("Bancolombia"): así escriben los bancos. */
    private fun esRemitenteDeEmpresa(remitente: String): Boolean {
        val r = remitente.trim()
        if (r.any { it.isLetter() }) return true
        val digitos = r.filter { it.isDigit() }
        return digitos.length in 3..6 && digitos.length == r.length
    }
}
