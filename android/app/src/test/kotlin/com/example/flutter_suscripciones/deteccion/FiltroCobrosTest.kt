package com.example.flutter_suscripciones.deteccion

import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Test
import java.io.File

/**
 * Filtro nativo de cobros, con las palabras reales de res/raw/deteccion_apps.json.
 * Corre en el PC:  cd android  y  .\gradlew :app:testCompletaDebugUnitTest
 */
class FiltroCobrosTest {
    // Gradle corre los tests con android/app como carpeta de trabajo.
    private val config = JSONObject(File("src/main/res/raw/deteccion_apps.json").readText())
    private val palabrasCobro = palabras("palabras_cobro")
    private val palabrasExcluidas = palabras("palabras_excluidas")

    private fun palabras(clave: String): List<String> {
        val arreglo = config.getJSONArray(clave)
        return (0 until arreglo.length()).map { FiltroCobros.normalizar(arreglo.getString(it)) }
    }

    private fun fixture(nombre: String, lista: String): List<JSONObject> {
        val arreglo = JSONObject(File("../../test/fixtures/$nombre").readText()).getJSONArray(lista)
        return (0 until arreglo.length()).map { arreglo.getJSONObject(it) }
    }

    private fun motivo(texto: String) = FiltroCobros.motivoDescarte(texto, palabrasCobro, palabrasExcluidas)

    @Test
    fun `los SMS de cobro reales pasan, lleguen por la app de SMS que sea`() {
        for (n in fixture("notificaciones_reales.json", "notificaciones")) {
            assertNull(n.getString("caso"), motivo(n.getString("texto")))
        }
    }

    @Test
    fun `los avisos de Truecaller que no son SMS se descartan`() {
        for (a in fixture("avisos_no_sms.json", "avisos")) {
            assertNotNull("debería descartarse: ${a.getString("caso")}", motivo(a.getString("texto")))
        }
    }

    @Test
    fun `un telefono no cuenta como monto`() {
        assertEquals("no tiene monto", motivo("Pago Facil Colombia · 3001234567"))
        assertEquals("no tiene monto", motivo("Compra y Venta El Paisa +57 604 444 5566"))
        // Pero un monto de verdad junto a un teléfono sí.
        assertNull(motivo("Bancolombia: Compraste \$19.900,00 en NETFLIX. Dudas: 6045109095"))
    }

    @Test
    fun `llamadas y spam se descartan por palabra excluida`() {
        val excluida = "palabra excluida (código, llamada o spam)"
        assertEquals(excluida, motivo("Llamada perdida de +57 300 123 4567"))
        assertEquals(excluida, motivo("Alerta de estafa: este número pide un pago de \$50.000"))
        assertEquals(excluida, motivo("Spam call: Payment Services 3001234567"))
    }

    @Test
    fun `SMS personales y codigos siguen descartandose`() {
        assertEquals("no tiene palabras de cobro", motivo("Hola, nos vemos a las 3"))
        assertNotNull(motivo("Bancolombia: tu codigo para la compra de \$19.900 es 123456"))
        assertEquals("sin texto", motivo("  "))
    }
}
