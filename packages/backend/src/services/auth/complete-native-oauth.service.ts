import { auth } from '@config/auth';
import { NATIVE_APP_URL_SCHEME } from '@root/config';
import { APIError } from 'better-auth';

import { readChallengeCookie } from './native-oauth-challenge-cookie';
import { storeNativeOAuthCode } from './native-oauth-code-store';

/**
 * The provider callback creates the session moments before this runs. An older
 * session means the browser carried a pre-existing login, not the one this flow
 * produced, so it is not handed to the app.
 */
const MAX_SESSION_AGE_MS = 2 * 60 * 1000;

/** Error codes this service adds on top of the ones better-auth forwards. */
export const NATIVE_OAUTH_COMPLETE_ERRORS = {
  invalidChallenge: 'invalid_challenge',
  invalidSession: 'invalid_session',
} as const;

const buildAppCallbackUrl = ({ params }: { params: Record<string, string> }) =>
  `${NATIVE_APP_URL_SCHEME}://auth-callback?${new URLSearchParams(params).toString()}`;

/** better-auth error codes are snake_case identifiers; anything else is replaced, not echoed into the app URL. */
const sanitizeErrorCode = ({ error }: { error: string }) =>
  /^[a-z0-9_]{1,64}$/i.test(error) ? error : 'unknown_error';

async function getFreshSessionToken({ headers }: { headers: Headers }): Promise<string | null> {
  try {
    const result = await auth.api.getSession({ headers });
    if (!result) return null;

    const ageMs = Date.now() - new Date(result.session.createdAt).getTime();
    return ageMs <= MAX_SESSION_AGE_MS ? result.session.token : null;
  } catch (error) {
    // A malformed or undecryptable session cookie is a missing session, not a server error.
    if (error instanceof APIError) return null;
    throw error;
  }
}

/**
 * Hands a just-created OAuth session to the native app. The session token stays
 * on the server: the app receives a one-time code, redeemable only with the PKCE
 * verifier matching the challenge cookie set by `start`. Every outcome is a
 * redirect into the app, so the in-app browser sheet always closes.
 */
export async function completeNativeOAuth({
  error,
  headers,
  cookieHeader,
}: {
  error: string | undefined;
  headers: Headers;
  cookieHeader: string | undefined;
}): Promise<{ redirectUrl: string }> {
  if (error) {
    return { redirectUrl: buildAppCallbackUrl({ params: { error: sanitizeErrorCode({ error }) } }) };
  }

  const challenge = await readChallengeCookie({ cookieHeader });
  if (!challenge) {
    return { redirectUrl: buildAppCallbackUrl({ params: { error: NATIVE_OAUTH_COMPLETE_ERRORS.invalidChallenge } }) };
  }

  const sessionToken = await getFreshSessionToken({ headers });
  if (!sessionToken) {
    return { redirectUrl: buildAppCallbackUrl({ params: { error: NATIVE_OAUTH_COMPLETE_ERRORS.invalidSession } }) };
  }

  const code = await storeNativeOAuthCode({ sessionToken, challenge });

  return { redirectUrl: buildAppCallbackUrl({ params: { code } }) };
}
