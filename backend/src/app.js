// Configuración de la aplicación Express: middlewares y rutas.
// No abre el puerto: eso lo hace server.js. Así los tests pueden importar
// `app` y probarla con supertest sin levantar un servidor real.
import cors from 'cors';
import express from 'express';

import { manejarErrores, noEncontrado } from './middlewares/errorHandler.js';
import authRoutes from './routes/auth.routes.js';
import healthRoutes from './routes/health.routes.js';
import resumenRoutes from './routes/resumen.routes.js';
import suscripcionesRoutes from './routes/suscripciones.routes.js';
import usuariosRoutes from './routes/usuarios.routes.js';

export const app = express();

// Permite peticiones desde otros orígenes (útil si se prueba desde un navegador).
app.use(cors());
// Convierte el cuerpo JSON de las peticiones en un objeto en req.body.
app.use(express.json());

app.use('/api/health', healthRoutes);
app.use('/api/auth', authRoutes);
app.use('/api/suscripciones', suscripcionesRoutes);
app.use('/api/resumen', resumenRoutes);
app.use('/api/usuarios', usuariosRoutes);

// Estos dos van al final: primero 404 para rutas desconocidas y luego el
// manejador de errores.
app.use(noEncontrado);
app.use(manejarErrores);
