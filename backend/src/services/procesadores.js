// Procesadores de pago (EBANX, PayU, dLocal...): cobran en nombre de otro
// servicio, así que el SMS trae su nombre y no el del servicio
// ("Pagaste 19.900,00 en SERVICIOS WEB EBANX CO" era Crunchyroll).
//
// La lista está en db/procesadores.json y se entrega a la app en
// GET /api/guias, así el celular y el backend usan la misma.
import fs from 'node:fs';
import path from 'node:path';

import { normalizar } from './guias.js';

export const PROCESADORES = JSON.parse(
  fs.readFileSync(path.join(import.meta.dirname, '../../db/procesadores.json'), 'utf8'),
);

/**
 * Nombre del procesador cuyo alias aparece en `comercio` como palabra
 * completa ("Servicios Web Ebanx Co" -> "EBANX"), o null. Igual que
 * CatalogoServicios.procesadorDe en lib/deteccion/catalogo_servicios.dart.
 */
export function procesadorDe(comercio) {
  const t = ` ${normalizar(comercio)} `;
  const tSeparado = ` ${normalizar(comercio, { separarPegadas: true })} `;
  for (const p of PROCESADORES) {
    for (const alias of p.alias) {
      const a = normalizar(alias);
      if (a && (t.includes(` ${a} `) || tSeparado.includes(` ${a} `))) return p.nombre;
    }
  }
  return null;
}
