// Crea (o reinicia) el usuario de demostración con datos realistas.
//
// Uso:  npm run db:demo
// Entra con:  demo@subtrack.co / Demo1234
//
// SOLO toca a ese usuario: lo borra (con todos SUS datos, por ON DELETE
// CASCADE) y lo vuelve a crear. Ningún otro usuario se modifica.
import crypto from 'node:crypto';

import bcrypt from 'bcryptjs';
import pg from 'pg';

import { verificarBdPermitida } from '../src/utils/candadoBd.js';
import { hoyColombia, sumarDias, sumarMeses } from '../src/utils/fechas.js';

export const CORREO_DEMO = 'demo@subtrack.co';
export const PASSWORD_DEMO = 'Demo1234';

// dias: cuántos días faltan para el próximo cobro (desde hoy).
// desdeMeses: hace cuántos meses empezó (para el historial y "Desde").
const ACTIVAS = [
  { nombre: 'Netflix', categoria: 'Streaming', monto: 38900, dias: 1, desdeMeses: 30 },
  {
    nombre: 'Disney+', categoria: 'Streaming', monto: 26900, dias: 2, desdeMeses: 0,
    prueba: true, origen: 'notificacion',
  },
  {
    nombre: 'Spotify', categoria: 'Música', monto: 19900, dias: 8, desdeMeses: 40,
    montoAnterior: 16900, origen: 'notificacion',
  },
  { nombre: 'iCloud+', categoria: 'Almacenamiento', monto: 14900, dias: 11, desdeMeses: 24 },
  {
    nombre: 'Smart Fit', categoria: 'Gimnasio', monto: 89900, dias: 13, desdeMeses: 9,
    estado: 'marcada_para_cancelar',
  },
  { nombre: 'Adobe Photoshop', categoria: 'Software', monto: 47900, dias: 18, desdeMeses: 14 },
  { nombre: 'ChatGPT Plus', categoria: 'Software', monto: 20, moneda: 'USD', dias: 20, desdeMeses: 7 },
  { nombre: 'Canva Pro', categoria: 'Diseño', monto: 199000, frecuencia: 'anual', dias: 80, desdeMeses: 22 },
];

// haceDias: cuándo se canceló.
const CANCELADAS = [
  { nombre: 'Paramount+', categoria: 'Streaming', monto: 21900, haceDias: 20, desdeMeses: 12 },
  { nombre: 'Crunchyroll', categoria: 'Streaming', monto: 16900, haceDias: 55, desdeMeses: 10 },
];

const MESES_HISTORIAL = 6;

// Detección automática (pantalla 05): pagos detectados en notificaciones y
// los candidatos pendientes que generaron. Claude es un servicio conocido;
// Bodytech se detectó por sus cobros mensuales; DiDi Food es una compra
// normal y no genera candidato. haceDias: cuándo llegó cada cobro.
const PAGOS_DETECTADOS = [
  { comercio: 'ANTHROPIC* CLAUDE SUB', normalizado: 'Claude', banco: 'Nequi', monto: 68139.27, haceDias: 33 },
  { comercio: 'ANTHROPIC* CLAUDE SUB', normalizado: 'Claude', banco: 'Nequi', monto: 69850.5, haceDias: 3 },
  { comercio: 'BODYTECH*CHAPINERO', normalizado: 'Bodytech', banco: 'Bancolombia', monto: 99900, haceMeses: 2 },
  { comercio: 'BODYTECH*CHAPINERO', normalizado: 'Bodytech', banco: 'Bancolombia', monto: 99900, haceMeses: 1 },
  { comercio: 'BODYTECH*CHAPINERO', normalizado: 'Bodytech', banco: 'Bancolombia', monto: 99900, haceDias: 4 },
  { comercio: 'DIDI FOOD', normalizado: 'Didi Food', banco: 'Bancolombia', monto: 18900, haceDias: 2 },
];
const CANDIDATOS = [
  { nombre: 'Claude', monto: 69850.5, banco: 'Nequi', conocido: true },
  { nombre: 'Bodytech', monto: 99900, banco: 'Bancolombia', conocido: false },
];

/** Fechas de cobro mensual hacia atrás desde `proximo`, hasta `limite` (incluido). */
function cobrosAnteriores(proximo, limite, hasta) {
  const fechas = [];
  for (let i = 1; i <= 60; i++) {
    const f = sumarMeses(proximo, -i);
    if (f < limite) break;
    if (f <= hasta) fechas.push(f);
  }
  return fechas;
}

export async function crearDemo(connectionString, hoy = hoyColombia()) {
  verificarBdPermitida(connectionString);
  const client = new pg.Client({ connectionString });
  await client.connect();
  try {
    await client.query('BEGIN');

    // Borra SOLO al usuario demo (sus suscripciones, pagos, cancelaciones,
    // cambios de precio y avisos se van con él por ON DELETE CASCADE).
    await client.query('DELETE FROM usuarios WHERE correo = $1', [CORREO_DEMO]);

    const hash = await bcrypt.hash(PASSWORD_DEMO, 10);
    const { rows: [usuario] } = await client.query(
      `INSERT INTO usuarios (nombre, correo, password_hash, dias_anticipacion_recordatorio)
       VALUES ('Daniela Bustos', $1, $2, 3) RETURNING id`,
      [CORREO_DEMO, hash],
    );

    const limiteHistorial = sumarMeses(hoy, -MESES_HISTORIAL);
    const ayer = sumarDias(hoy, -1);

    async function insertar(s, extra) {
      const desde = sumarMeses(hoy, -s.desdeMeses);
      const { rows: [fila] } = await client.query(
        `INSERT INTO suscripciones (usuario_id, nombre_servicio, categoria, monto, moneda, frecuencia,
           fecha_proximo_cobro, es_prueba_gratis, fecha_fin_prueba, origen, estado, fecha_deteccion, creado_en)
         VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10::varchar, $11,
           CASE WHEN $10::varchar = 'notificacion' THEN $12::date END, $12::date)
         RETURNING id`,
        [usuario.id, s.nombre, s.categoria, s.monto, s.moneda ?? 'COP', s.frecuencia ?? 'mensual',
          extra.proximo, s.prueba === true, s.prueba ? extra.proximo : null, s.origen ?? 'manual',
          extra.estado ?? s.estado ?? 'activa', desde],
      );
      return { id: fila.id, desde };
    }

    async function pagos(id, fechas, montoDe) {
      for (const f of fechas) {
        await client.query(
          'INSERT INTO historial_pagos (suscripcion_id, monto, fecha_pago) VALUES ($1, $2, $3)',
          [id, montoDe(f), f],
        );
      }
    }

    for (const s of ACTIVAS) {
      const proximo = sumarDias(hoy, s.dias);
      const { id, desde } = await insertar(s, { proximo });
      // Las pruebas gratis no tienen pagos; las anuales casi nunca caen en 6 meses.
      if (!s.prueba && (s.frecuencia ?? 'mensual') === 'mensual') {
        const limite = desde > limiteHistorial ? desde : limiteHistorial;
        // Antes del cambio de precio se pagaba el monto anterior.
        await pagos(id, cobrosAnteriores(proximo, limite, ayer), () => s.montoAnterior ?? s.monto);
      }
      if (s.montoAnterior) {
        await client.query(
          `INSERT INTO cambios_precio (suscripcion_id, monto_anterior, monto_nuevo, fecha_cambio)
           VALUES ($1, $2, $3, NOW() - INTERVAL '5 days')`,
          [id, s.montoAnterior, s.monto],
        );
      }
    }

    for (const s of CANCELADAS) {
      const fechaCancelacion = sumarDias(hoy, -s.haceDias);
      // El cobro que habría seguido a la cancelación.
      const proximo = sumarDias(fechaCancelacion, 10);
      const { id, desde } = await insertar(s, { proximo, estado: 'cancelada' });
      const limite = desde > limiteHistorial ? desde : limiteHistorial;
      await pagos(id, cobrosAnteriores(proximo, limite, fechaCancelacion), () => s.monto);
      await client.query(
        `INSERT INTO cancelaciones (suscripcion_id, fecha_cancelacion, ahorro_proyectado_anual)
         VALUES ($1, $2, $3)`,
        [id, fechaCancelacion, s.monto * 12],
      );
    }

    const ultimoPago = {};
    for (const [i, p] of PAGOS_DETECTADOS.entries()) {
      const dia = p.haceMeses ? sumarMeses(sumarDias(hoy, -4), -p.haceMeses) : sumarDias(hoy, -p.haceDias);
      ultimoPago[p.normalizado] = dia > (ultimoPago[p.normalizado] ?? '') ? dia : ultimoPago[p.normalizado];
      await client.query(
        `INSERT INTO pagos_detectados (usuario_id, comercio, comercio_normalizado, monto, moneda, fecha, banco, huella)
         VALUES ($1, $2, $3, $4, 'COP', $5, $6, $7)`,
        [usuario.id, p.comercio, p.normalizado, p.monto, `${dia}T10:15:00`, p.banco,
          crypto.createHash('sha256').update(`demo-${i}`).digest('hex')],
      );
    }
    for (const c of CANDIDATOS) {
      await client.query(
        `INSERT INTO candidatos_suscripcion (usuario_id, comercio_normalizado, monto, moneda, frecuencia_estimada,
           es_servicio_conocido, banco, fecha_ultimo_pago)
         VALUES ($1, $2, $3, 'COP', 'mensual', $4, $5, $6)`,
        [usuario.id, c.nombre, c.monto, c.conocido, c.banco, ultimoPago[c.nombre]],
      );
    }

    await client.query('COMMIT');
    return { usuarioId: usuario.id, suscripciones: ACTIVAS.length + CANCELADAS.length };
  } catch (err) {
    await client.query('ROLLBACK');
    throw err;
  } finally {
    await client.end();
  }
}

if (import.meta.main) {
  if (!process.env.DATABASE_URL) {
    console.error('Falta DATABASE_URL. Revisa el archivo .env (ver .env.example).');
    process.exit(1);
  }
  try {
    const { suscripciones } = await crearDemo(process.env.DATABASE_URL);
    console.log(`Usuario demo listo: ${CORREO_DEMO} / ${PASSWORD_DEMO} (${suscripciones} suscripciones).`);
  } catch (err) {
    console.error('No se pudo crear el usuario demo:', err.message);
    process.exit(1);
  }
}
