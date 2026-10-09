import { AUTH_COOKIE_PREFIX } from '@config/auth';
import { shouldUseSecureCookies } from '@config/should-use-secure-cookies';
import { API_PREFIX } from '@root/config';
import type { CookieOptions } from 'express';

import { readSignedValue, signValue } from './signed-value';

export const NATIVE_OAUTH_CHALLENGE_COOKIE_NAME = `${AUTH_COOKIE_PREFIX}.native_oauth_challenge`;

/**
 * Attributes shared by setting and clearing the cookie (a clear only matches a
 * cookie with the same path). SameSite=Lax, not Strict: the cookie has to ride
 * along on the provider's cross-site redirect back into the callback chain.
 */
export const NATIVE_OAUTH_CHALLENGE_COOKIE_ATTRIBUTES: CookieOptions = {
  httpOnly: true,
  sameSite: 'lax',
  secure: shouldUseSecureCookies({ nodeEnv: process.env.NODE_ENV, betterAuthUrl: process.env.BETTER_AUTH_URL }),
  path: `${API_PREFIX}/auth/native/oauth`,
};

/** Matches better-auth's OAuth state cookie, after which the flow cannot complete anyway. */
export const NATIVE_OAUTH_CHALLENGE_COOKIE_MAX_AGE_MS = 5 * 60 * 1000;

/**
 * Prefixed before signing so a signed challenge can never double as a signed
 * session token: the bearer plugin verifies with the same secret and format.
 */
const SIGNING_PURPOSE = 'native-oauth-challenge:';

export function signChallenge({ challenge }: { challenge: string }): Promise<string> {
  return signValue({ value: `${SIGNING_PURPOSE}${challenge}` });
}

/** Reads and verifies the challenge cookie from a raw `Cookie` header. Null when absent or tampered with. */
export async function readChallengeCookie({ cookieHeader }: { cookieHeader: string | undefined }) {
  const rawValue = readCookie({ cookieHeader, name: NATIVE_OAUTH_CHALLENGE_COOKIE_NAME });
  if (!rawValue) return null;

  const value = await readSignedValue({ signedValue: rawValue });
  if (!value?.startsWith(SIGNING_PURPOSE)) return null;

  return value.slice(SIGNING_PURPOSE.length) || null;
}

function readCookie({ cookieHeader, name }: { cookieHeader: string | undefined; name: string }): string | null {
  for (const pair of (cookieHeader ?? '').split(';')) {
    const separator = pair.indexOf('=');
    if (separator === -1 || pair.slice(0, separator).trim() !== name) continue;

    try {
      return decodeURIComponent(pair.slice(separator + 1).trim());
    } catch {
      return null;
    }
  }
  return null;
}
