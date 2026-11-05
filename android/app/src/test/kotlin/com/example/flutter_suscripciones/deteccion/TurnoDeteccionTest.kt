package com.example.flutter_suscripciones.deteccion

import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test

/**
 * Candado para procesar la cola: la app y la tarea de fondo (dos motores de
 * Flutter en el mismo proceso) nunca procesan a la vez.
 */
class TurnoDeteccionTest {
    @Before
    fun limpiar() = TurnoDeteccion.reiniciar()

    @Test
    fun `un solo dueno a la vez`() {
        assertTrue(TurnoDeteccion.tomar("fondo", ahora = 0))
        assertFalse(TurnoDeteccion.tomar("app", ahora = 1_000))
        TurnoDeteccion.soltar("fondo")
        assertTrue(TurnoDeteccion.tomar("app", ahora = 2_000))
    }

    @Test
    fun `vence a los 3 minutos si el dueno no lo suelta`() {
        assertTrue(TurnoDeteccion.tomar("fondo", ahora = 0))
        assertFalse(TurnoDeteccion.tomar("app", ahora = 3 * 60_000 - 1))
        assertTrue(TurnoDeteccion.tomar("app", ahora = 3 * 60_000 + 1))
    }

    @Test
    fun `no lo suelta quien no lo tiene`() {
        assertTrue(TurnoDeteccion.tomar("fondo", ahora = 0))
        TurnoDeteccion.soltar("app")
        assertFalse(TurnoDeteccion.tomar("app", ahora = 1_000))
    }
}
