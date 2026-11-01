// Punto de entrada del backend de SubTrack: valida la configuración y abre el
// puerto. En local, las variables de entorno se cargan desde .env con
// `node --env-file-if-exists=.env` (ver los scripts de package.json). En
// Render no hay .env: las variables se configuran en su panel.

// Sin estas variables el servidor no puede funcionar: mejor avisar y salir.
// Se revisan antes de importar app.js porque db.js usa DATABASE_URL al cargarse.
for (const nombre of ['DATABASE_URL', 'JWT_SECRET']) {
  if (!process.env[nombre]) {
    console.error(
      `Falta la variable de entorno ${nombre}. En local, revisa el archivo .env (ver .env.example); `
      + 'en Render, agrégala en Environment (ver docs/despliegue.md).',
    );
    process.exit(1);
  }
}

const { app } = await import('./app.js');
const { iniciarTareas } = await import('./tareas.js');
const { query } = await import('./db.js');
const { migracionesPendientes } = await import('../db/migrar.js');

// Render asigna el puerto en la variable PORT; en local se usa 3000.
const PORT = Number(process.env.PORT) || 3000;
// 0.0.0.0 = escuchar en todas las interfaces de red, no solo en localhost.
// Así un celular conectado a la misma red WiFi puede llegar usando la IP del
// PC, y Render puede enviar el tráfico al servidor.
const HOST = '0.0.0.0';

/**
 * Avisa en los logs si faltan migraciones. NO las aplica: eso se hace a mano
 * con "npm run db:migrate" (o "db:migrate:nube" contra Neon).
 */
async function revisarMigraciones() {
  try {
    const pendientes = await migracionesPendientes(query);
    if (pendientes.length === 0) {
      console.log('Base de datos al día: no hay migraciones pendientes.');
    } else {
      console.warn(
        `ATENCIÓN: hay ${pendientes.length} migraciones pendientes (${pendientes.join(', ')}). `
        + 'La API puede fallar hasta aplicarlas con "npm run db:migrate" '
        + '(contra Neon: "npm run db:migrate:nube", ver docs/despliegue.md).',
      );
    }
  } catch (err) {
    console.error('No se pudo revisar las migraciones (¿la base de datos responde?):', err.message);
  }
}

app.listen(PORT, HOST, (err) => {
  if (err) {
    console.error('No se pudo iniciar el servidor:', err.message);
    process.exit(1);
  }
  console.log(`API de SubTrack escuchando en http://${HOST}:${PORT}`);
  revisarMigraciones();
  // Cobros automáticos: al arrancar y todos los días a las 00:05 (Colombia).
  iniciarTareas();
});
