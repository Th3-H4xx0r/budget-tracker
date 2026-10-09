import { API_ERROR_CODES } from '@bt/shared/types';
import { afterEach, beforeEach, describe, expect, it } from '@jest/globals';
import { redisClient } from '@root/redis-client';
import { NATIVE_OAUTH_COMPLETE_ERRORS } from '@services/auth/complete-native-oauth.service';
import { NATIVE_OAUTH_CODE_TTL_SECONDS, nativeOAuthCodeRedisKey } from '@services/auth/native-oauth-code-store';
import * as helpers from '@tests/helpers';
import { backdateMockSession } from '@tests/mocks/better-auth';

/**
 * Native app OAuth: start → (provider) → complete → exchange.
 *
 * better-auth is mocked under Jest, so `signInSocial` stands in for the provider
 * redirect and the provider callback is represented by the session cookie from
 * the suite's email sign-in. GitHub is configured through env for these tests;
 * Google stays unconfigured.
 */
const PROVIDER_ENV_KEYS = ['GITHUB_CLIENT_ID', 'GITHUB_CLIENT_SECRET', 'GOOGLE_CLIENT_ID', 'GOOGLE_CLIENT_SECRET'];
const DEFAULT_SESSION_TOKEN = 'test-token';

const errorOf = ({ res }: { res: { body: { response: unknown } } }) => res.body.response as helpers.ErrorResponse;

const setCookieHeaders = ({ res }: { res: { headers: Record<string, unknown> } }): string[] =>
  (res.headers['set-cookie'] as string[] | undefined) ?? [];

describe('Native OAuth', () => {
  let savedEnv: Record<string, string | undefined> = {};

  beforeEach(() => {
    savedEnv = Object.fromEntries(PROVIDER_ENV_KEYS.map((key) => [key, process.env[key]]));
    for (const key of PROVIDER_ENV_KEYS) delete process.env[key];
    process.env.GITHUB_CLIENT_ID = 'test-github-client-id';
    process.env.GITHUB_CLIENT_SECRET = 'test-github-client-secret';
  });

  afterEach(() => {
    for (const key of PROVIDER_ENV_KEYS) {
      if (savedEnv[key] === undefined) delete process.env[key];
      else process.env[key] = savedEnv[key];
    }
  });

  describe('GET /auth/native/oauth/start', () => {
    it('sets the challenge and state cookies, then redirects to the provider', async () => {
      const { codeChallenge } = helpers.createPkcePair();

      const res = await helpers.startNativeOAuth({ provider: 'github', codeChallenge });

      expect(res.statusCode).toBe(302);
      expect(res.headers.location).toMatch(/^https:\/\/oauth\.mock\/github\/authorize\?state=/);

      const cookies = setCookieHeaders({ res });
      const challengeCookie = cookies.find((cookie) => cookie.includes('.native_oauth_challenge='));
      expect(challengeCookie).toBeDefined();
      expect(challengeCookie).toContain('HttpOnly');
      expect(challengeCookie).toContain('SameSite=Lax');
      expect(challengeCookie).toContain('Path=/api/v1/auth/native/oauth');
      expect(challengeCookie).toContain('Max-Age=300');
      expect(cookies.some((cookie) => cookie.startsWith('bt_auth.state='))).toBe(true);
    });

    it('returns a validation error for an unconfigured provider', async () => {
      const { codeChallenge } = helpers.createPkcePair();

      const res = await helpers.startNativeOAuth({ provider: 'google', codeChallenge });

      expect(res.statusCode).toBe(422);
      expect(errorOf({ res }).code).toBe(API_ERROR_CODES.validationError);
      expect(errorOf({ res }).message).toContain('Google');
      expect(setCookieHeaders({ res })).toHaveLength(0);
    });

    it('returns a validation error for an unknown provider or a malformed challenge', async () => {
      const { codeChallenge } = helpers.createPkcePair();

      const unknownProviderRes = await helpers.startNativeOAuth({ provider: 'facebook', codeChallenge });
      const badChallengeRes = await helpers.startNativeOAuth({ provider: 'github', codeChallenge: 'too-short' });

      expect(unknownProviderRes.statusCode).toBe(422);
      expect(badChallengeRes.statusCode).toBe(422);
    });
  });

  describe('GET /auth/native/oauth/complete', () => {
    it('redirects into the app with a one-time code and clears the challenge cookie', async () => {
      const { code, completeRes } = await helpers.obtainNativeOAuthCode();

      expect(completeRes.statusCode).toBe(302);
      const callback = helpers.readAppCallback({ location: completeRes.headers.location });
      expect(callback.scheme).toBe('moneymatter');
      expect(callback.host).toBe('auth-callback');
      expect(callback.error).toBeNull();
      expect(code).toMatch(/^[A-Za-z0-9_-]{43}$/);

      const clearedCookie = setCookieHeaders({ res: completeRes }).find((cookie) =>
        cookie.includes('.native_oauth_challenge='),
      );
      expect(clearedCookie).toContain('Expires=Thu, 01 Jan 1970');
    });

    it('forwards a provider error to the app and sanitises unexpected values', async () => {
      const deniedRes = await helpers.completeNativeOAuth({ cookies: '', error: 'access_denied' });
      const junkRes = await helpers.completeNativeOAuth({ cookies: '', error: '<script>alert(1)</script>' });

      expect(deniedRes.statusCode).toBe(302);
      expect(helpers.readAppCallback({ location: deniedRes.headers.location })).toMatchObject({
        scheme: 'moneymatter',
        code: null,
        error: 'access_denied',
      });
      expect(helpers.readAppCallback({ location: junkRes.headers.location }).error).toBe('unknown_error');
    });

    it('redirects with an error when the challenge cookie is missing or tampered with', async () => {
      const { codeChallenge } = helpers.createPkcePair();
      const startRes = await helpers.startNativeOAuth({ provider: 'github', codeChallenge });
      const tamperedCookies = helpers
        .extractCookies(startRes)
        .replace(
          /(\.native_oauth_challenge=)([A-Za-z0-9])/,
          (_match, name: string, first: string) => `${name}${first === 'A' ? 'B' : 'A'}`,
        );

      const sessionCookies = global.APP_AUTH_COOKIES!;
      const missingRes = await helpers.completeNativeOAuth({ cookies: sessionCookies });
      const tamperedRes = await helpers.completeNativeOAuth({ cookies: `${sessionCookies}; ${tamperedCookies}` });

      expect(helpers.readAppCallback({ location: missingRes.headers.location }).error).toBe(
        NATIVE_OAUTH_COMPLETE_ERRORS.invalidChallenge,
      );
      expect(helpers.readAppCallback({ location: tamperedRes.headers.location }).error).toBe(
        NATIVE_OAUTH_COMPLETE_ERRORS.invalidChallenge,
      );
    });

    it('redirects with an error without a session, or with one older than two minutes', async () => {
      const { codeChallenge } = helpers.createPkcePair();
      const startRes = await helpers.startNativeOAuth({ provider: 'github', codeChallenge });
      const challengeCookies = helpers.extractCookies(startRes);

      const noSessionRes = await helpers.completeNativeOAuth({ cookies: challengeCookies });

      backdateMockSession({ sessionToken: DEFAULT_SESSION_TOKEN, createdAt: new Date(Date.now() - 3 * 60 * 1000) });
      const staleSessionRes = await helpers.completeNativeOAuth({
        cookies: `${global.APP_AUTH_COOKIES}; ${challengeCookies}`,
      });

      expect(helpers.readAppCallback({ location: noSessionRes.headers.location }).error).toBe(
        NATIVE_OAUTH_COMPLETE_ERRORS.invalidSession,
      );
      expect(helpers.readAppCallback({ location: staleSessionRes.headers.location }).error).toBe(
        NATIVE_OAUTH_COMPLETE_ERRORS.invalidSession,
      );
    });
  });

  describe('POST /auth/native/oauth/exchange', () => {
    it('exchanges the code for the signed bearer token', async () => {
      const { code, codeVerifier } = await helpers.obtainNativeOAuthCode();

      const res = await helpers.exchangeNativeOAuthCode({ code, codeVerifier });

      expect(res.statusCode).toBe(200);
      const { token } = res.body.response;

      // The same value the bearer plugin returns from an email sign-in for this session.
      const signInRes = await helpers.signInWithEmail();
      expect(token).toBe(signInRes.headers['set-auth-token']);

      const userRes = await helpers.getUserInfoWithBearer({ token });
      expect(userRes.statusCode).toBe(200);
      expect(userRes.body.response.id).toBe((await helpers.getUserInfo({ raw: true })).id);
    });

    it('returns 401 for an unknown code', async () => {
      const { codeVerifier } = helpers.createPkcePair();

      const res = await helpers.exchangeNativeOAuthCode({ code: 'not-a-real-code', codeVerifier });

      expect(res.statusCode).toBe(401);
      expect(errorOf({ res }).code).toBe(API_ERROR_CODES.unauthorized);
      expect(errorOf({ res }).message).toBeTruthy();
    });

    it('returns 401 for an expired code', async () => {
      const { code, codeVerifier } = await helpers.obtainNativeOAuthCode();
      const key = nativeOAuthCodeRedisKey({ code });

      const ttl = await redisClient.ttl(key);
      expect(ttl).toBeGreaterThan(0);
      expect(ttl).toBeLessThanOrEqual(NATIVE_OAUTH_CODE_TTL_SECONDS);

      // Fast-forward the TTL instead of waiting a minute.
      await redisClient.pexpire(key, 1);
      await helpers.sleep(20);

      const res = await helpers.exchangeNativeOAuthCode({ code, codeVerifier });

      expect(res.statusCode).toBe(401);
      expect(errorOf({ res }).code).toBe(API_ERROR_CODES.unauthorized);
    });

    it('returns 401 for a wrong verifier, which also burns the code', async () => {
      const { code, codeVerifier } = await helpers.obtainNativeOAuthCode();
      const { codeVerifier: otherVerifier } = helpers.createPkcePair();

      const wrongRes = await helpers.exchangeNativeOAuthCode({ code, codeVerifier: otherVerifier });
      const retryRes = await helpers.exchangeNativeOAuthCode({ code, codeVerifier });

      expect(wrongRes.statusCode).toBe(401);
      expect(errorOf({ res: wrongRes }).code).toBe(API_ERROR_CODES.unauthorized);
      expect(retryRes.statusCode).toBe(401);
    });

    it('returns 401 when a code is reused', async () => {
      const { code, codeVerifier } = await helpers.obtainNativeOAuthCode();

      const firstRes = await helpers.exchangeNativeOAuthCode({ code, codeVerifier });
      const secondRes = await helpers.exchangeNativeOAuthCode({ code, codeVerifier });

      expect(firstRes.statusCode).toBe(200);
      expect(secondRes.statusCode).toBe(401);
      expect(errorOf({ res: secondRes }).code).toBe(API_ERROR_CODES.unauthorized);
    });

    it('returns 422 for a malformed verifier', async () => {
      const { code } = await helpers.obtainNativeOAuthCode();

      const res = await helpers.exchangeNativeOAuthCode({ code, codeVerifier: 'short' });

      expect(res.statusCode).toBe(422);
    });
  });
});
