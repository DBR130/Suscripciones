package com.example.flutter_suscripciones.deteccion

import java.text.Normalizer

/**
 * Primer filtro, en el celular: decide si un texto "parece un cobro" para
 * guardarlo. Es a propósito sencillo; la interpretación completa (comercio,
 * monto, fecha) la hace el parser en Dart (hito 2).
 *
 * Privacidad: lo que no pasa este filtro se descarta en el acto y no se guarda.
 */
object FiltroCobros {
    // Un monto: "$19.900", "$ 26.900", "68.139,27", "19900", "COP 26,900.00", "USD 20.00".
    private val monto = Regex(
        """(\$\s?\d)|(\b(cop|usd)\s?\d)|(\d{1,3}([.,]\d{3})+([.,]\d{1,2})?)|(\d{4,}([.,]\d{1,2})?)"""
    )

    // Teléfonos, que no son montos: "+57 300 123 4567", celulares (3001234567),
    // fijos (6045109095) y líneas 01 8000. Truecaller los muestra en sus avisos
    // de llamadas y spam, y sin esto "4567890" pasaría por un monto.
    private val telefono = Regex(
        """(\+\d{1,3}([\s-]?\d{2,4}){2,4})|(\b(3\d{9}|60\d{8}|01\s?8000\s?\d{5,6})\b)"""
    )

    /** Minúsculas y sin tildes ("Débito" -> "debito"). */
    fun normalizar(texto: String): String =
        Normalizer.normalize(texto, Normalizer.Form.NFD)
            .replace(Regex("\\p{Mn}+"), "")
            .lowercase()

    /** Por qué se descartó, o null si parece un cobro. */
    fun motivoDescarte(texto: String, config: ConfiguracionDeteccion): String? =
        motivoDescarte(texto, config.palabrasCobro, config.palabrasExcluidas)

    /** Igual, con las palabras ya normalizadas (así se prueba sin Android). */
    fun motivoDescarte(texto: String, palabrasCobro: List<String>, palabrasExcluidas: List<String>): String? {
        val t = normalizar(texto)
        if (t.isBlank()) return "sin texto"
        val palabras = t.split(Regex("[^a-z0-9]+")).toSet()
        if (palabrasExcluidas.any { it in palabras }) return "palabra excluida (código, llamada o spam)"
        if (palabrasCobro.none { it in palabras }) return "no tiene palabras de cobro"
        if (!monto.containsMatchIn(t.replace(telefono, " "))) return "no tiene monto"
        return null
    }
}
