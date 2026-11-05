package com.example.flutter_suscripciones.deteccion

/**
 * Candado para procesar la cola de cobros. La app (al abrirse o volver) y la
 * tarea de fondo de WorkManager corren en dos motores de Flutter distintos,
 * pero en el mismo proceso de Android: este objeto es común a los dos, así
 * nunca procesan la misma cola a la vez.
 *
 * Vence a los 3 minutos por si un motor muere sin soltarlo. Si Android mata
 * el proceso, el candado desaparece con él.
 */
object TurnoDeteccion {
    const val DURACION_MS = 3 * 60 * 1000L

    private var dueno: String? = null
    private var desde = 0L

    /** true si [quien] consiguió el turno (o ya lo tenía). */
    @Synchronized
    fun tomar(quien: String, ahora: Long = System.currentTimeMillis()): Boolean {
        val actual = dueno
        if (actual != null && actual != quien && ahora - desde <= DURACION_MS) return false
        dueno = quien
        desde = ahora
        return true
    }

    /** Lo suelta solo si es de [quien]. */
    @Synchronized
    fun soltar(quien: String) {
        if (dueno == quien) dueno = null
    }

    @Synchronized
    fun reiniciar() {
        dueno = null
        desde = 0L
    }
}
