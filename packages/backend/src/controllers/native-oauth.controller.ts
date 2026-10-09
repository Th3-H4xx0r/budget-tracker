/**
 * Native app (iOS) OAuth: the app opens `start` in an in-app browser, `complete`
 * redirects back into the app with a one-time code, and `exchange` trades that
 * code plus the PKCE verifier for a bearer token.
 */
import { OAUTH_PROVIDER } from '@bt/shared/types';
import { createController } from '@controllers/helpers/controller-factory';
import { completeNativeOAuth } from '@services/auth/complete-native-oauth.service';
import { exchangeNativeOAuthCode } from '@services/auth/exchange-native-oauth-code.service';
import {
  NATIVE_OAUTH_CHALLENGE_COOKIE_ATTRIBUTES,
  NATIVE_OAUTH_CHALLENGE_COOKIE_MAX_AGE_MS,
  NATIVE_OAUTH_CHALLENGE_COOKIE_NAME,
} from '@services/auth/native-oauth-challenge-cookie';
import { startNativeOAuth } from '@services/auth/start-native-oauth.service';
import { fromNodeHeaders } from 'better-auth/node';
import { z } from 'zod';

/** base64url SHA-256 digest, unpadded (RFC 7636 S256). */
const S256_CHALLENGE = /^[A-Za-z0-9_-]{43}$/;
/** RFC 7636 code_verifier: 43–128 unreserved characters. */
const CODE_VERIFIER = /^[A-Za-z0-9._~-]{43,128}$/;

export const startNativeOAuthController = createController(
  z.object({
    query: z.object({
      provider: z.enum(OAUTH_PROVIDER),
      code_challenge: z.string().regex(S256_CHALLENGE),
    }),
  }),
  async ({ query, req, res }) => {
    const { providerUrl, stateCookies, signedChallenge } = await startNativeOAuth({
      provider: query.provider,
      codeChallenge: query.code_challenge,
      headers: fromNodeHeaders(req.headers),
    });

    if (stateCookies.length) res.append('Set-Cookie', stateCookies);
    res.cookie(NATIVE_OAUTH_CHALLENGE_COOKIE_NAME, signedChallenge, {
      ...NATIVE_OAUTH_CHALLENGE_COOKIE_ATTRIBUTES,
      maxAge: NATIVE_OAUTH_CHALLENGE_COOKIE_MAX_AGE_MS,
    });
    res.redirect(302, providerUrl);
  },
);

export const completeNativeOAuthController = createController(
  z.object({
    query: z.object({
      error: z.string().optional(),
    }),
  }),
  async ({ query, req, res }) => {
    const { redirectUrl } = await completeNativeOAuth({
      error: query.error,
      headers: fromNodeHeaders(req.headers),
      cookieHeader: req.headers.cookie,
    });

    res.clearCookie(NATIVE_OAUTH_CHALLENGE_COOKIE_NAME, NATIVE_OAUTH_CHALLENGE_COOKIE_ATTRIBUTES);
    res.redirect(302, redirectUrl);
  },
);

export const exchangeNativeOAuthCodeController = createController(
  z.object({
    body: z.object({
      code: z.string().min(1).max(256),
      codeVerifier: z.string().regex(CODE_VERIFIER),
    }),
  }),
  async ({ body }) => {
    const data = await exchangeNativeOAuthCode({ code: body.code, codeVerifier: body.codeVerifier });
    return { data };
  },
);
