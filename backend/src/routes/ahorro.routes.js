import { Router } from 'express';

import { ahorro } from '../controllers/ahorro.controller.js';
import { verificarToken } from '../middlewares/auth.js';

const router = Router();

router.get('/', verificarToken, ahorro);

export default router;
