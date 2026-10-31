import { Router } from 'express';

import { listarGuias } from '../controllers/guias.controller.js';
import { verificarToken } from '../middlewares/auth.js';

const router = Router();

router.get('/', verificarToken, listarGuias);

export default router;
