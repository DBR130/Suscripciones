package com.example.flutter_suscripciones.deteccion

/**
 * Guía "Mantén SubTrack activa en segundo plano" (encargo C, ver
 * docs/deteccion.md, "Fabricantes que cierran apps").
 *
 * Varias capas de fabricante cierran las apps en segundo plano y no vuelven a
 * lanzar el lector de notificaciones. No existe API pública para saber si el
 * ajuste que lo evita está activo ni para activarlo: solo se puede abrir la
 * pantalla donde el usuario lo cambia.
 */
object FabricanteSegundoPlano {
    /** Build.MANUFACTURER -> "xiaomi", "samsung", "oppo", "vivo", "huawei" u "otra". */
    fun grupo(fabricante: String): String {
        val f = fabricante.trim().lowercase()
        return when {
            f in setOf("xiaomi", "redmi", "poco") -> "xiaomi"
            f == "samsung" -> "samsung"
            f in setOf("oppo", "realme", "oneplus") -> "oppo"
            f == "vivo" -> "vivo"
            f in setOf("huawei", "honor") -> "huawei"
            else -> "otra"
        }
    }

    /**
     * Pantallas propias del fabricante (paquete, actividad), en orden. Si
     * ninguna existe en el celular, se abren los ajustes de la app.
     *
     * Solo la de Xiaomi está probada en un celular real (Xiaomi 25080RABDG,
     * HyperOS). Las demás son las que usan las capas de cada marca; si el
     * celular no las tiene o no las deja abrir, se cae a los ajustes de la app.
     * Samsung no tiene pantalla de inicio automático: lo que cuenta es la
     * batería "Sin restricciones" de la app.
     */
    fun pantallas(grupo: String): List<Pair<String, String>> = when (grupo) {
        "xiaomi" -> listOf(
            "com.miui.securitycenter" to "com.miui.permcenter.autostart.AutoStartManagementActivity",
        )
        "oppo" -> listOf(
            "com.coloros.safecenter" to "com.coloros.safecenter.permission.startup.StartupAppListActivity",
        )
        "vivo" -> listOf(
            "com.vivo.permissionmanager" to "com.vivo.permissionmanager.activity.BgStartUpManagerActivity",
        )
        "huawei" -> listOf(
            "com.huawei.systemmanager" to "com.huawei.systemmanager.startupmgr.ui.StartupNormalAppListActivity",
        )
        else -> emptyList()
    }
}

/**
 * Marca el "rescate tardío": la app se abrió con el lector desconectado y
 * pidió reconectarlo (log "App con el lector desconectado (…): se intenta
 * reconectar"). Si el lector se conecta poco después, lo que la recuperación
 * desde la barra guarde llegó tarde: el proceso estaba muerto cuando llegó el
 * cobro. LectorNotificacionesService marca esas entradas de la cola
 * ("rescate_tardio") y Flutter decide si eran cobros nuevos (encargo C,
 * punto 5).
 *
 * En memoria, como TurnoDeteccion: el pedido y la conexión ocurren en el
 * mismo proceso.
 */
object RescateTardio {
    const val VENTANA_MS = 2 * 60 * 1000L

    private var pedidoEn: Long? = null

    @Synchronized
    fun pedir(ahora: Long = System.currentTimeMillis()) {
        pedidoEn = ahora
    }

    /** true si hubo un pedido hace menos de [VENTANA_MS]. Lo consume. */
    @Synchronized
    fun tomar(ahora: Long = System.currentTimeMillis()): Boolean {
        val pedido = pedidoEn ?: return false
        pedidoEn = null
        return ahora - pedido <= VENTANA_MS
    }

    @Synchronized
    fun reiniciar() {
        pedidoEn = null
    }
}
