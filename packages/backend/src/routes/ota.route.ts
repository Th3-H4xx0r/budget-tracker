import { downloadHandler, manifestHandler } from '@controllers/ota.controller';
import { Router } from 'express';

const router = Router({});

// Public: iOS's installer fetches these with no cookie. Each URL carries its own signed,
// expiring token, checked by the service.
router.get(/^\/m\/([^/]+)\.plist$/, manifestHandler);
router.get('/d/:token/:fileName', downloadHandler);

export default router;
