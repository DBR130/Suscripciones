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

    /** Minúsculas y sin tildes ("Débito" -> "debito"). */
    fun normalizar(texto: String): String =
        Normalizer.normalize(texto, Normalizer.Form.NFD)
            .replace(Regex("\\p{Mn}+"), "")
            .lowercase()

    /** Por qué se descartó, o null si parece un cobro. */
    fun motivoDescarte(texto: String, config: ConfiguracionDeteccion): String? {
        val t = normalizar(texto)
        if (t.isBlank()) return "sin texto"
        val palabras = t.split(Regex("[^a-z0-9]+")).toSet()
        if (config.palabrasExcluidas.any { it in palabras }) return "palabra excluida (posible código de verificación)"
        if (config.palabrasCobro.none { it in palabras }) return "no tiene palabras de cobro"
        if (!monto.containsMatchIn(t)) return "no tiene monto"
        return null
    }
}
