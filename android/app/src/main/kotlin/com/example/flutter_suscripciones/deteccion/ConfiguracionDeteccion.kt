package com.example.flutter_suscripciones.deteccion

import android.content.Context
import android.content.pm.ApplicationInfo
import com.example.flutter_suscripciones.R
import org.json.JSONArray
import org.json.JSONObject

/**
 * Lee res/raw/deteccion_apps.json: qué apps se procesan y qué palabras
 * indican un cobro. Se carga una sola vez por proceso.
 */
class ConfiguracionDeteccion private constructor(
    /** paquete -> nombre legible, de las apps permitidas (incluye las de debug si aplica). */
    val appsPermitidas: Map<String, String>,
    val palabrasCobro: List<String>,
    val palabrasExcluidas: List<String>,
    val esDebug: Boolean,
) {
    fun permitida(paquete: String): Boolean = appsPermitidas.containsKey(paquete)

    companion object {
        @Volatile
        private var instancia: ConfiguracionDeteccion? = null

        fun de(context: Context): ConfiguracionDeteccion =
            instancia ?: synchronized(this) {
                instancia ?: cargar(context.applicationContext).also { instancia = it }
            }

        /** true en compilaciones debug (flutter run), false en release. */
        fun esDebug(context: Context): Boolean =
            (context.applicationInfo.flags and ApplicationInfo.FLAG_DEBUGGABLE) != 0

        private fun cargar(context: Context): ConfiguracionDeteccion {
            val texto = context.resources.openRawResource(R.raw.deteccion_apps)
                .bufferedReader(Charsets.UTF_8).use { it.readText() }
            val json = JSONObject(texto)
            val debug = esDebug(context)

            val apps = LinkedHashMap<String, String>()
            leerApps(json.optJSONArray("apps_permitidas"), apps)
            // com.android.shell solo en debug: en release nadie puede simular pagos.
            if (debug) leerApps(json.optJSONArray("apps_solo_debug"), apps)

            return ConfiguracionDeteccion(
                appsPermitidas = apps,
                palabrasCobro = leerTextos(json.optJSONArray("palabras_cobro")),
                palabrasExcluidas = leerTextos(json.optJSONArray("palabras_excluidas")),
                esDebug = debug,
            )
        }

        private fun leerApps(arreglo: JSONArray?, destino: MutableMap<String, String>) {
            if (arreglo == null) return
            for (i in 0 until arreglo.length()) {
                val app = arreglo.optJSONObject(i) ?: continue
                val paquete = app.optString("paquete").trim()
                if (paquete.isNotEmpty()) destino[paquete] = app.optString("nombre", paquete)
            }
        }

        private fun leerTextos(arreglo: JSONArray?): List<String> {
            if (arreglo == null) return emptyList()
            return (0 until arreglo.length()).map { FiltroCobros.normalizar(arreglo.optString(it)) }
        }
    }
}
