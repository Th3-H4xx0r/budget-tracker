import type { CustomResponse } from '@common/types';
import { errorHandler } from '@controllers/helpers';
import { NotFoundError, Unauthorized } from '@js/errors';
import type { NextFunction, Request } from 'express';
import crypto from 'node:crypto';

const MIN_TOKEN_LENGTH = 32;

const digest = ({ value }: { value: string }) => crypto.createHash('sha256').update(value).digest();

/**
 * Guards the build upload and rollback endpoints with the shared `APP_UPDATE_UPLOAD_TOKEN`
 * (`Authorization: Bearer <token>`). The endpoints do not exist while the variable is unset or
 * shorter than 32 characters.
 */
export const requireAppUpdateUploadToken = (req: Request, res: CustomResponse, next: NextFunction) => {
  const expected = (process.env.APP_UPDATE_UPLOAD_TOKEN || '').trim();
  if (expected.length < MIN_TOKEN_LENGTH) return errorHandler(res, new NotFoundError({ message: 'Not found.' }));

  const match = /^Bearer (.+)$/.exec(req.headers.authorization || '');
  const given = match?.[1] ?? '';
  // Hashing first gives timingSafeEqual equal-length inputs whatever the caller sent.
  if (!crypto.timingSafeEqual(digest({ value: given }), digest({ value: expected }))) {
    // The body is up to 1 GiB; closing the connection after the reply stops the server draining it for a caller that failed auth.
    res.set('Connection', 'close');
    res.on('finish', () => req.destroy());
    return errorHandler(res, new Unauthorized({ message: 'Invalid upload token.' }));
  }
  next();
};
