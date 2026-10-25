// Punto de entrada del backend de SubTrack: valida la configuración y abre el
// puerto. Las variables de entorno se cargan desde .env con
// `node --env-file=.env` (ver los scripts de package.json).

// Sin estas variables el servidor no puede funcionar: mejor avisar y salir.
// Se revisan antes de importar app.js porque db.js usa DATABASE_URL al cargarse.
for (const nombre of ['DATABASE_URL', 'JWT_SECRET']) {
  if (!process.env[nombre]) {
    console.error(`Falta la variable de entorno ${nombre}. Revisa el archivo .env (ver .env.example).`);
    process.exit(1);
  }
}

const { app } = await import('./app.js');
const { iniciarTareas } = await import('./tareas.js');

const PORT = Number(process.env.PORT) || 3000;
// 0.0.0.0 = escuchar en todas las interfaces de red, no solo en localhost.
// Así un celular conectado a la misma red WiFi puede llegar usando la IP del PC.
const HOST = '0.0.0.0';

app.listen(PORT, HOST, (err) => {
  if (err) {
    console.error('No se pudo iniciar el servidor:', err.message);
    process.exit(1);
  }
  console.log(`API de SubTrack escuchando en http://${HOST}:${PORT}`);
  // Cobros automáticos: al arrancar y todos los días a las 00:05 (Colombia).
  iniciarTareas();
});
