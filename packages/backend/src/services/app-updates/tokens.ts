import type { AppUpdatePlatform } from '@bt/shared/types';
import crypto from 'node:crypto';

import { findStoredBuild, type StoredBuild } from './storage';

export const LINK_TTL_SECONDS = 600;

const TOKEN_PATTERN = /^ios\.(\d{1,12})\.(\d{1,12})\.([0-9a-f]{32})$/;

const MIN_SIGNING_KEY_LENGTH = 32;

const signingKey = (): string | Buffer => {
  const configured = process.env.APP_UPDATES_SIGNING_KEY;
  if (configured) {
    if (configured.length < MIN_SIGNING_KEY_LENGTH) {
      throw new Error(`APP_UPDATES_SIGNING_KEY must be at least ${MIN_SIGNING_KEY_LENGTH} characters.`);
    }
    return configured;
  }
  const secret = process.env.BETTER_AUTH_SECRET;
  if (!secret) throw new Error('APP_UPDATES_SIGNING_KEY or BETTER_AUTH_SECRET must be set to sign app update links.');
  return crypto.createHmac('sha256', secret).update('moneymatter-app-updates').digest();
};

const sign = ({ build, exp }: { build: number; exp: number }) =>
  crypto.createHmac('sha256', signingKey()).update(`ios.${build}.${exp}`).digest('hex').slice(0, 32);

export const createToken = ({ build, now = Date.now() }: { build: number; now?: number }): string => {
  const exp = Math.floor(now / 1000) + LINK_TTL_SECONDS;
  return `ios.${build}.${exp}.${sign({ build, exp })}`;
};

/** The stored build a token grants; null when it is malformed, forged, expired or names a build no longer kept. */
export const resolveToken = async ({
  token,
  now = Date.now(),
}: {
  token: string;
  now?: number;
}): Promise<(StoredBuild & { platform: AppUpdatePlatform }) | null> => {
  const match = TOKEN_PATTERN.exec(token);
  if (!match) return null;
  const build = Number(match[1]);
  const exp = Number(match[2]);
  const expected = Buffer.from(sign({ build, exp }));
  const given = Buffer.from(match[3]!);
  if (given.length !== expected.length || !crypto.timingSafeEqual(given, expected)) return null;
  if (exp < now / 1000) return null;
  const record = await findStoredBuild({ platform: 'ios', build });
  return record ? { ...record, platform: 'ios' } : null;
};

/** Origin the install links point at, without a trailing slash. */
export const publicBaseUrl = (): string =>
  (process.env.APP_UPDATES_PUBLIC_URL || process.env.AUTH_ORIGIN || '').replace(/\/+$/, '');

export const buildInstallUrl = ({ token, base }: { token: string; base: string }) =>
  `itms-services://?action=download-manifest&url=${encodeURIComponent(`${base}/ota/m/${token}.plist`)}`;
