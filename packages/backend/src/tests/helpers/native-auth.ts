import { UserInfoResponse } from '@bt/shared/types';
import type { exchangeNativeOAuthCode as apiExchangeNativeOAuthCode } from '@services/auth/exchange-native-oauth-code.service';
import { createHash, randomBytes } from 'node:crypto';

import { extractCookies, makeAuthRequest, makeRequest } from './common';
import { asUser, withoutSession } from './share';

/** Credentials of the suite's default user, seeded in setupIntegrationTests. */
const DEFAULT_USER = { email: 'test1@test.local', password: 'testpassword123' };

const bearerHeaders = ({ token }: { token: string }) => ({ Authorization: `Bearer ${token}` });

/**
 * Email sign-in the way a native client does it: no cookies sent, response headers kept.
 * `headers` adds request headers, e.g. the `Sec-Fetch-*` headers a browser sends.
 */
export function signInWithEmail({
  email = DEFAULT_USER.email,
  password = DEFAULT_USER.password,
  headers,
}: { email?: string; password?: string; headers?: Record<string, string> } = {}) {
  return withoutSession(() =>
    makeAuthRequest<{ session: { token: string } }>({
      method: 'post',
      url: '/auth/sign-in/email',
      payload: { email, password },
      headers,
    }),
  );
}

/** `GET /user` authenticated by the bearer token alone: no session cookie is sent. */
export function getUserInfoWithBearer<R extends boolean | undefined = undefined>({
  token,
  raw,
}: {
  token: string;
  raw?: R;
}) {
  return withoutSession(() =>
    makeRequest<UserInfoResponse, R>({ method: 'get', url: '/user', headers: bearerHeaders({ token }), raw }),
  );
}

export function signOutWithBearer({ token }: { token: string }) {
  return withoutSession(() =>
    makeAuthRequest({ method: 'post', url: '/auth/sign-out', headers: bearerHeaders({ token }) }),
  );
}

/** A PKCE pair as the native app generates it: random verifier, S256 challenge. */
export function createPkcePair() {
  const codeVerifier = randomBytes(32).toString('base64url');
  return { codeVerifier, codeChallenge: createHash('sha256').update(codeVerifier).digest('base64url') };
}

/** Opens the start URL like the app's in-app browser does: no cookies, no bearer token. */
export function startNativeOAuth({ provider, codeChallenge }: { provider: string; codeChallenge: string }) {
  const query = new URLSearchParams({ provider, code_challenge: codeChallenge });
  return withoutSession(() => makeAuthRequest({ method: 'get', url: `/auth/native/oauth/start?${query}` }));
}

/** Requests `complete` as the browser does after the provider callback, carrying `cookies`. */
export function completeNativeOAuth({ cookies, error }: { cookies: string; error?: string }) {
  const query = error ? `?${new URLSearchParams({ error })}` : '';
  return asUser({
    cookies,
    fn: () => makeAuthRequest({ method: 'get', url: `/auth/native/oauth/complete${query}` }),
  });
}

export function exchangeNativeOAuthCode<R extends boolean | undefined = undefined>({
  code,
  codeVerifier,
  raw,
}: {
  code: string;
  codeVerifier: string;
  raw?: R;
}) {
  return withoutSession(() =>
    makeRequest<Awaited<ReturnType<typeof apiExchangeNativeOAuthCode>>, R>({
      method: 'post',
      url: '/auth/native/oauth/exchange',
      payload: { code, codeVerifier },
      raw,
    }),
  );
}

/** Parses a redirect into the app (`<scheme>://auth-callback?code=…` or `?error=…`). */
export function readAppCallback({ location }: { location: string | undefined }) {
  const url = new URL(location ?? '');
  return {
    scheme: url.protocol.replace(/:$/, ''),
    host: url.host,
    code: url.searchParams.get('code'),
    error: url.searchParams.get('error'),
  };
}

/**
 * Runs the browser half of native OAuth for the suite's default user: `start`
 * sets the challenge cookie, then `complete` receives it together with the
 * session cookie the provider callback would have set. The provider must be
 * configured in the test's env.
 */
export async function obtainNativeOAuthCode({ provider = 'github' }: { provider?: string } = {}) {
  const { codeVerifier, codeChallenge } = createPkcePair();
  const startRes = await startNativeOAuth({ provider, codeChallenge });
  const completeRes = await completeNativeOAuth({
    cookies: [global.APP_AUTH_COOKIES, extractCookies(startRes)].filter(Boolean).join('; '),
  });

  const { code } = readAppCallback({ location: completeRes.headers.location });
  if (!code) throw new Error(`complete did not issue a code, redirected to: ${completeRes.headers.location}`);

  return { code, codeVerifier, codeChallenge, startRes, completeRes };
}
