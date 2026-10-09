import { t } from '@i18n/index';
import { Unauthorized } from '@js/errors';
import { createHash, timingSafeEqual } from 'node:crypto';

import { consumeNativeOAuthCode } from './native-oauth-code-store';
import { signValue } from './signed-value';

/** PKCE S256 (RFC 7636): base64url(SHA-256(verifier)), unpadded. */
const toS256Challenge = ({ codeVerifier }: { codeVerifier: string }) =>
  createHash('sha256').update(codeVerifier).digest('base64url');

const isSameString = ({ a, b }: { a: string; b: string }) => {
  const bufferA = Buffer.from(a);
  const bufferB = Buffer.from(b);
  return bufferA.length === bufferB.length && timingSafeEqual(bufferA, bufferB);
};

/**
 * Redeems a one-time code from `complete` for the signed bearer token. The code
 * is consumed before the verifier is checked, so a wrong verifier also burns it.
 * Every failure gets the same 401, telling the caller nothing about which check failed.
 */
export async function exchangeNativeOAuthCode({
  code,
  codeVerifier,
}: {
  code: string;
  codeVerifier: string;
}): Promise<{ token: string }> {
  const payload = await consumeNativeOAuthCode({ code });

  if (!payload || !isSameString({ a: toS256Challenge({ codeVerifier }), b: payload.challenge })) {
    throw new Unauthorized({ message: t({ key: 'auth.nativeOAuth.invalidCode' }) });
  }

  return { token: await signValue({ value: payload.sessionToken }) };
}
