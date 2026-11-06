package com.example.flutter_suscripciones.deteccion

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test

/** Marca del celular (Build.MANUFACTURER) -> grupo de la guía de segundo plano. */
class FabricanteSegundoPlanoTest {
    @Test
    fun `agrupa las marcas por la capa del fabricante`() {
        assertEquals("xiaomi", FabricanteSegundoPlano.grupo("Xiaomi"))
        assertEquals("xiaomi", FabricanteSegundoPlano.grupo("Redmi"))
        assertEquals("xiaomi", FabricanteSegundoPlano.grupo("POCO"))
        assertEquals("samsung", FabricanteSegundoPlano.grupo("samsung"))
        assertEquals("oppo", FabricanteSegundoPlano.grupo("OPPO"))
        assertEquals("oppo", FabricanteSegundoPlano.grupo("realme"))
        assertEquals("oppo", FabricanteSegundoPlano.grupo("OnePlus"))
        assertEquals("vivo", FabricanteSegundoPlano.grupo("vivo"))
        assertEquals("huawei", FabricanteSegundoPlano.grupo("HUAWEI"))
        assertEquals("huawei", FabricanteSegundoPlano.grupo("HONOR"))
    }

    @Test
    fun `otras marcas o vacio quedan en otra`() {
        assertEquals("otra", FabricanteSegundoPlano.grupo("Google"))
        assertEquals("otra", FabricanteSegundoPlano.grupo("motorola"))
        assertEquals("otra", FabricanteSegundoPlano.grupo(""))
    }

    @Test
    fun `en Xiaomi la primera pantalla es la de inicio automatico que ya se probo`() {
        assertEquals(
            "com.miui.securitycenter" to "com.miui.permcenter.autostart.AutoStartManagementActivity",
            FabricanteSegundoPlano.pantallas("xiaomi").first(),
        )
    }

    @Test
    fun `Samsung y otras marcas no tienen pantalla propia (se usan los ajustes de la app)`() {
        assertTrue(FabricanteSegundoPlano.pantallas("samsung").isEmpty())
        assertTrue(FabricanteSegundoPlano.pantallas("otra").isEmpty())
    }
}

/**
 * Rescate tardío: la app pidió reconectar un lector desconectado y, al
 * reconectarse, la recuperación desde la barra marca lo que guarda.
 */
class RescateTardioTest {
    @Before
    fun limpiar() = RescateTardio.reiniciar()

    @Test
    fun `sin pedido previo, una conexion no es rescate tardio`() {
        assertFalse(RescateTardio.tomar(ahora = 1_000))
    }

    @Test
    fun `la conexion poco despues del pedido es rescate tardio, una sola vez`() {
        RescateTardio.pedir(ahora = 0)
        assertTrue(RescateTardio.tomar(ahora = 30_000))
        assertFalse(RescateTardio.tomar(ahora = 31_000))
    }

    @Test
    fun `vence a los 2 minutos`() {
        RescateTardio.pedir(ahora = 0)
        assertFalse(RescateTardio.tomar(ahora = 2 * 60_000 + 1))
    }
}
