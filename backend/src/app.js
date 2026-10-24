// Punto de entrada del backend de SubTrack.
// Las variables de entorno se cargan desde .env con `node --env-file=.env`
// (ver los scripts de package.json).
import cors from 'cors';
import express from 'express';

import { manejarErrores, noEncontrado } from './middlewares/errorHandler.js';
import authRoutes from './routes/auth.routes.js';
import healthRoutes from './routes/health.routes.js';

// Sin estas variables el servidor no puede funcionar: mejor avisar y salir.
for (const nombre of ['DATABASE_URL', 'JWT_SECRET']) {
  if (!process.env[nombre]) {
    console.error(`Falta la variable de entorno ${nombre}. Revisa el archivo .env (ver .env.example).`);
    process.exit(1);
  }
}

const app = express();

// Permite peticiones desde otros orígenes (útil si se prueba desde un navegador).
app.use(cors());
// Convierte el cuerpo JSON de las peticiones en un objeto en req.body.
app.use(express.json());

app.use('/api/health', healthRoutes);
app.use('/api/auth', authRoutes);

// Estos dos van al final: primero 404 para rutas desconocidas y luego el
// manejador de errores.
app.use(noEncontrado);
app.use(manejarErrores);

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
});
