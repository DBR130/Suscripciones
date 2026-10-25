import { Router } from 'express';

import {
  actualizar, cambiarEstado, crear, eliminar, listar, obtener,
} from '../controllers/suscripciones.controller.js';
import { verificarToken } from '../middlewares/auth.js';
import { validarEstado, validarSuscripcion } from '../middlewares/validaciones.js';

// Rutas de suscripciones. Se montan en /api/suscripciones (ver app.js).
const router = Router();

// Todas requieren sesión: verificarToken se ejecuta antes de cada ruta.
router.use(verificarToken);

router.get('/', listar);
router.post('/', validarSuscripcion, crear);
router.get('/:id', obtener);
router.put('/:id', validarSuscripcion, actualizar);
router.delete('/:id', eliminar);
router.patch('/:id/estado', validarEstado, cambiarEstado);

export default router;
