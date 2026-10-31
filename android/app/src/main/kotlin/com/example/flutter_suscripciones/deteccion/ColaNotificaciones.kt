package com.example.flutter_suscripciones.deteccion

import android.content.Context
import android.util.Log
import org.json.JSONArray
import org.json.JSONObject
import java.io.File
import java.security.MessageDigest

/**
 * Cola local de notificaciones que parecen cobros, en el almacenamiento
 * interno de la app (filesDir/deteccion/cola.json: solo esta app puede
 * leerlo). El servicio escribe aunque la app esté cerrada; Flutter la lee al
 * abrirse y borra las que ya procesó.
 */
object ColaNotificaciones {
    private const val MAXIMO = 200 // si se llena, se descartan las más viejas
    private const val DIAS_RETENCION = 30L
    private val lock = Any()

    private fun archivo(context: Context): File =
        File(context.filesDir, "deteccion/cola.json").also { it.parentFile?.mkdirs() }

    /** Huella para no guardar dos veces la misma notificación (también la usará el backend). */
    fun huella(paquete: String, titulo: String, texto: String, recibidaEn: Long): String {
        val bytes = MessageDigest.getInstance("SHA-256")
            .digest("$paquete\n$titulo\n$texto\n$recibidaEn".toByteArray(Charsets.UTF_8))
        return bytes.joinToString("") { "%02x".format(it) }
    }

    /**
     * Agrega una notificación. Devuelve false si ya estaba: misma huella (la
     * misma notificación leída otra vez desde la barra) o misma app y texto.
     */
    fun agregar(context: Context, notificacion: JSONObject): Boolean = synchronized(lock) {
        val lista = leerInterno(context)
        val repetida = lista.any {
            it.optString("id") == notificacion.optString("id") ||
                (it.optString("paquete") == notificacion.optString("paquete") &&
                    it.optString("texto") == notificacion.optString("texto"))
        }
        if (repetida) return false
        lista.add(notificacion)
        while (lista.size > MAXIMO) lista.removeAt(0)
        escribir(context, lista)
        true
    }

    fun leer(context: Context): List<JSONObject> = synchronized(lock) { leerInterno(context) }

    fun borrar(context: Context, ids: Collection<String>) = synchronized(lock) {
        escribir(context, leerInterno(context).filterNot { it.optString("id") in ids })
    }

    fun vaciar(context: Context) = synchronized(lock) { escribir(context, emptyList()) }

    private fun leerInterno(context: Context): MutableList<JSONObject> {
        val f = archivo(context)
        if (!f.exists()) return mutableListOf()
        val limite = System.currentTimeMillis() - DIAS_RETENCION * 24 * 60 * 60 * 1000
        return try {
            val arreglo = JSONArray(f.readText(Charsets.UTF_8))
            (0 until arreglo.length())
                .mapNotNull { arreglo.optJSONObject(it) }
                .filter { it.optLong("recibida_en") >= limite } // se borran las de más de 30 días
                .toMutableList()
        } catch (e: Exception) {
            mutableListOf() // archivo dañado: se empieza de nuevo
        }
    }

    private fun escribir(context: Context, lista: List<JSONObject>) {
        val f = archivo(context)
        val temporal = File(f.parentFile, "cola.json.tmp")
        temporal.writeText(JSONArray(lista).toString(), Charsets.UTF_8)
        val ok = temporal.renameTo(f) // reemplazo atómico: nunca queda un archivo a medias
        if (ok) {
            Log.i(TAG, "Cola escrita: ${lista.size} notificaciones")
        } else {
            Log.e(TAG, "No se pudo escribir la cola en ${f.absolutePath}")
        }
    }
}
