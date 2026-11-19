import { APP_UPDATE_MAX_BYTES, APP_UPDATE_PLATFORMS } from '@bt/shared/types';
import { createController } from '@controllers/helpers/controller-factory';
import { getLatestAppUpdate } from '@services/app-updates/get-latest.service';
import { getInstallStatus } from '@services/app-updates/install-status.service';
import { rollbackAppUpdate } from '@services/app-updates/rollback.service';
import { uploadAppUpdate } from '@services/app-updates/upload.service';
import { z } from 'zod';

const platform = z.enum(APP_UPDATE_PLATFORMS);

export const getLatest = createController(
  z.object({
    query: z.object({
      platform,
      build: z.coerce.number().int().min(0).max(999_999_999_999).default(0),
    }),
  }),
  async ({ query }) => ({ data: await getLatestAppUpdate({ platform: query.platform, clientBuild: query.build }) }),
);

export const installStatus = createController(
  z.object({ query: z.object({ token: z.string().min(1) }) }),
  async ({ query }) => ({ data: getInstallStatus({ token: query.token }) }),
);

export const upload = createController(
  z.object({
    query: z.object({
      platform,
      build: z.coerce.number().int().positive().max(999_999_999_999),
      notes: z.string().default(''),
      commit: z.string().default(''),
    }),
  }),
  async ({ query, req, res }) => {
    const declaredLength = Number(req.headers['content-length']);
    // A rejected upload leaves most of its body unread; closing the connection after the reply
    // stops the server waiting for (or draining) the rest of it.
    if (declaredLength > APP_UPDATE_MAX_BYTES) res.set('Connection', 'close');
    res.on('finish', () => {
      if (!req.complete) req.destroy();
    });
    return {
      data: await uploadAppUpdate({
        platform: query.platform,
        build: query.build,
        commit: query.commit,
        notes: query.notes,
        body: req,
        contentLength: Number.isFinite(declaredLength) ? declaredLength : null,
      }),
    };
  },
);

export const rollback = createController(z.object({ query: z.object({ platform }) }), async ({ query }) => ({
  data: await rollbackAppUpdate({ platform: query.platform }),
}));
