import { Router } from 'express';

import { analisis } from '../controllers/analisis.controller.js';
import { verificarToken } from '../middlewares/auth.js';

const router = Router();

router.get('/', verificarToken, analisis);

export default router;
