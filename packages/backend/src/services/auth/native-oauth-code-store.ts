import { redisClient } from '@root/redis-client';
import { randomBytes } from 'node:crypto';

export const NATIVE_OAUTH_CODE_TTL_SECONDS = 60;

export const nativeOAuthCodeRedisKey = ({ code }: { code: string }) => `native-oauth:code:${code}`;

interface NativeOAuthCodePayload {
  sessionToken: string;
  challenge: string;
}

/** Stores the payload under a fresh one-time code and returns the code. */
export async function storeNativeOAuthCode(payload: NativeOAuthCodePayload): Promise<string> {
  const code = randomBytes(32).toString('base64url');

  await redisClient.set(
    nativeOAuthCodeRedisKey({ code }),
    JSON.stringify(payload),
    'EX',
    NATIVE_OAUTH_CODE_TTL_SECONDS,
  );

  return code;
}

/**
 * Reads and deletes the code in one GETDEL, so a code is redeemable once even
 * under concurrent requests. Null for an unknown, expired, or already-used code.
 */
export async function consumeNativeOAuthCode({ code }: { code: string }): Promise<NativeOAuthCodePayload | null> {
  const raw = await redisClient.getdel(nativeOAuthCodeRedisKey({ code }));
  return raw ? (JSON.parse(raw) as NativeOAuthCodePayload) : null;
}
