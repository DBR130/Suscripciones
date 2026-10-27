import { Router } from 'express';

import { avisos } from '../controllers/avisos.controller.js';
import { verificarToken } from '../middlewares/auth.js';

const router = Router();

router.get('/', verificarToken, avisos);

export default router;
