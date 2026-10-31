// Búsqueda de la guía de cancelación que corresponde a una suscripción.
// Funciones puras (sin BD) para probarlas en test/guias.test.js.

/**
 * Normaliza un nombre para compararlo:
 * - minúsculas y sin tildes ("Música" → "musica"),
 * - "+" se lee como "plus" ("Disney+" → "disney plus"),
 * - cualquier otro signo cuenta como espacio.
 */
export function normalizar(texto) {
  return String(texto)
    .normalize('NFD')
    .replace(/[̀-ͯ]/g, '') // quita las tildes que quedaron separadas
    .toLowerCase()
    .replace(/\+/g, ' plus ')
    .replace(/[^a-z0-9ñ]+/g, ' ')
    .trim();
}

/**
 * Busca la guía para `nombreServicio` entre `guias` (filas de la tabla, con
 * nombre_servicio, alias y es_generica). Coincide si el nombre, ya
 * normalizado, contiene el nombre o un alias de la guía como palabras
 * completas: "Netflix Estándar" encuentra "Netflix". Si varias coinciden,
 * gana la más larga ("Apple TV+" antes que "Apple").
 *
 * Si ninguna coincide, devuelve la genérica.
 * @returns {{ guia: object, esGenerica: boolean }}
 */
export function buscarGuia(nombreServicio, guias) {
  const nombre = ` ${normalizar(nombreServicio)} `;
  let mejor = null;
  let largoMejor = 0;
  for (const g of guias) {
    if (g.es_generica) continue;
    for (const clave of [g.nombre_servicio, ...(g.alias ?? [])]) {
      const c = normalizar(clave);
      if (c && nombre.includes(` ${c} `) && c.length > largoMejor) {
        mejor = g;
        largoMejor = c.length;
      }
    }
  }
  if (mejor) return { guia: mejor, esGenerica: false };
  return { guia: guias.find((g) => g.es_generica) ?? null, esGenerica: true };
}
