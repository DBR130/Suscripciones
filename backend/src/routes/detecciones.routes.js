import { Router } from 'express';

import {
  confirmarCandidato, descartarCandidato, listarCandidatos, registrarPagos,
} from '../controllers/detecciones.controller.js';
import { verificarToken } from '../middlewares/auth.js';
import { validarPagosDetectados } from '../middlewares/validaciones.js';

// Detección automática de suscripciones. Se monta en /api/detecciones (ver app.js).
const router = Router();

router.use(verificarToken);

router.post('/pagos', validarPagosDetectados, registrarPagos);
router.get('/candidatos', listarCandidatos);
router.post('/candidatos/:id/confirmar', confirmarCandidato);
router.post('/candidatos/:id/descartar', descartarCandidato);

export default router;
