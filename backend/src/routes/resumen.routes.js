import { Router } from 'express';

import { resumen } from '../controllers/resumen.controller.js';
import { verificarToken } from '../middlewares/auth.js';

const router = Router();

router.get('/', verificarToken, resumen);

export default router;
