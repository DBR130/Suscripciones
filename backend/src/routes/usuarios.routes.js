import { Router } from 'express';

import {
  actualizarPreferencias, eliminarCuenta, obtenerPreferencias,
} from '../controllers/usuarios.controller.js';
import { verificarToken } from '../middlewares/auth.js';
import { validarEliminarCuenta, validarPreferencias } from '../middlewares/validaciones.js';

// Rutas de la cuenta del usuario. Se montan en /api/usuarios (ver app.js).
const router = Router();

router.use(verificarToken);

router.get('/me/preferencias', obtenerPreferencias);
router.put('/me/preferencias', validarPreferencias, actualizarPreferencias);
router.delete('/me', validarEliminarCuenta, eliminarCuenta);

export default router;
