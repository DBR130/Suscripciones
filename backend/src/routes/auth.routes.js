import { Router } from 'express';

import { login, me, registro } from '../controllers/auth.controller.js';
import { verificarToken } from '../middlewares/auth.js';
import { validarLogin, validarRegistro } from '../middlewares/validaciones.js';

// Rutas de autenticación. Se montan en /api/auth (ver app.js).
// Cada ruta pasa por sus middlewares en orden y al final llega al controlador.
const router = Router();

router.post('/registro', validarRegistro, registro);
router.post('/login', validarLogin, login);
router.get('/me', verificarToken, me);

export default router;
