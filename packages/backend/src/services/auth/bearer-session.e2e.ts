import { API_ERROR_CODES } from '@bt/shared/types';
import { describe, expect, it } from '@jest/globals';
import * as helpers from '@tests/helpers';

/**
 * Bearer sessions for native clients (better-auth `bearer` plugin).
 *
 * better-auth is mocked under Jest (ESM-only). The mock emulates the plugin –
 * `set-auth-token` on sign-in and `Authorization: Bearer` resolution with
 * signature checks – so these tests cover the app's wiring: the plugin is
 * registered, `authenticateSession` accepts bearer tokens without a cookie, and
 * sign-out revokes them.
 */
const signInForToken = async () => {
  const res = await helpers.signInWithEmail();
  const token = res.headers['set-auth-token'] as string | undefined;
  if (!token) throw new Error('sign-in returned no set-auth-token header');
  return { token, sessionToken: res.body.session.token };
};

const flipFirstChar = ({ value }: { value: string }) => `${value.startsWith('A') ? 'B' : 'A'}${value.slice(1)}`;

describe('Bearer sessions', () => {
  it('returns the signed session token in set-auth-token on email sign-in', async () => {
    const res = await helpers.signInWithEmail();

    expect(res.statusCode).toBe(200);
    // `<session token>.<signature>`, the same value the session cookie carries.
    expect(res.headers['set-auth-token']).toMatch(new RegExp(`^${res.body.session.token}\\.[A-Za-z0-9+/]+=*$`));
  });

  it('omits set-auth-token for browser requests, detected by Sec-Fetch-* headers', async () => {
    const browserRes = await helpers.signInWithEmail({ headers: { 'Sec-Fetch-Mode': 'cors' } });
    const nativeRes = await helpers.signInWithEmail();

    expect(browserRes.statusCode).toBe(200);
    expect(browserRes.headers['set-auth-token']).toBeUndefined();
    expect(browserRes.headers['access-control-expose-headers'] ?? '').not.toMatch(/set-auth-token/i);

    expect(nativeRes.statusCode).toBe(200);
    expect(nativeRes.headers['set-auth-token']).toEqual(expect.any(String));
  });

  it('authenticates GET /user with only a bearer token', async () => {
    const { token } = await signInForToken();
    const cookieUser = await helpers.getUserInfo({ raw: true });

    const res = await helpers.getUserInfoWithBearer({ token });

    expect(res.statusCode).toBe(200);
    expect(res.body.response.id).toBe(cookieUser.id);
  });

  it('returns 401 without a cookie or bearer token', async () => {
    const res = await helpers.withoutSession(() => helpers.getUserInfo());

    expect(res.statusCode).toBe(401);
    expect((res.body.response as unknown as helpers.ErrorResponse).code).toBe(API_ERROR_CODES.unauthorized);
  });

  it('returns 401 for a tampered token', async () => {
    const { token } = await signInForToken();
    const [value = '', signature = ''] = token.split('.');

    const tamperedSignature = `${value}.${flipFirstChar({ value: signature })}`;
    const tamperedValue = `${flipFirstChar({ value })}.${signature}`;

    const signatureRes = await helpers.getUserInfoWithBearer({ token: tamperedSignature });
    const valueRes = await helpers.getUserInfoWithBearer({ token: tamperedValue });

    expect(signatureRes.statusCode).toBe(401);
    expect(valueRes.statusCode).toBe(401);
  });

  it('returns 401 for an unsigned session token', async () => {
    const { sessionToken } = await signInForToken();

    const res = await helpers.getUserInfoWithBearer({ token: sessionToken });

    expect(res.statusCode).toBe(401);
  });

  it('returns 401 for the token after signing out with it', async () => {
    const { token } = await signInForToken();
    expect((await helpers.getUserInfoWithBearer({ token })).statusCode).toBe(200);

    const signOutRes = await helpers.signOutWithBearer({ token });
    expect(signOutRes.statusCode).toBe(200);

    const res = await helpers.getUserInfoWithBearer({ token });
    expect(res.statusCode).toBe(401);
  });
});
