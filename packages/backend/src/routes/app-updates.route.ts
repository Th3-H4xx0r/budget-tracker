import { getLatest, installStatus, rollback, upload } from '@controllers/app-updates.controller';
import { adminOnly } from '@middlewares/admin-only';
import { requireAppUpdateUploadToken } from '@middlewares/app-update-upload-token';
import { authenticateSession } from '@middlewares/better-auth';
import { validateEndpoint } from '@middlewares/validations';
import { Router } from 'express';

const router = Router({});

// Install links are minted per request, so only the owner (ADMIN_USERS) may ask for them.
router.get('/latest', authenticateSession, adminOnly, validateEndpoint(getLatest.schema), getLatest.handler);

router.get(
  '/install-status',
  authenticateSession,
  adminOnly,
  validateEndpoint(installStatus.schema),
  installStatus.handler,
);

// Authenticated by the upload token, not a session. The body is the raw IPA and is streamed
// to disk by the service: the global JSON/urlencoded parsers ignore application/octet-stream.
router.post('/upload', requireAppUpdateUploadToken, validateEndpoint(upload.schema), upload.handler);

router.post('/rollback', requireAppUpdateUploadToken, validateEndpoint(rollback.schema), rollback.handler);

export default router;
