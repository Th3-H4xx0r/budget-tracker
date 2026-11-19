import { afterEach, beforeEach, describe, expect, it } from '@jest/globals';
import * as helpers from '@tests/helpers';

const ENV_KEYS = ['ADMIN_USERS', 'CF_ACCESS_CLIENT_ID', 'CF_ACCESS_CLIENT_SECRET'] as const;

describe('Cloudflare Access device setup (GET /admin/cloudflare-access)', () => {
  const originals: Partial<Record<(typeof ENV_KEYS)[number], string | undefined>> = {};

  beforeEach(() => {
    for (const key of ENV_KEYS) originals[key] = process.env[key];
    process.env.ADMIN_USERS = 'test1';
    delete process.env.CF_ACCESS_CLIENT_ID;
    delete process.env.CF_ACCESS_CLIENT_SECRET;
  });

  afterEach(() => {
    for (const key of ENV_KEYS) {
      if (originals[key] === undefined) delete process.env[key];
      else process.env[key] = originals[key];
    }
  });

  it('returns the server URL and token to an admin when configured', async () => {
    process.env.CF_ACCESS_CLIENT_ID = 'abc.access';
    process.env.CF_ACCESS_CLIENT_SECRET = 's3cret';
    const expectedServerUrl = (process.env.AUTH_ORIGIN || 'https://localhost:8100').replace(/\/+$/, '');

    const setup = await helpers.getCloudflareAccessDeviceSetup({ raw: true });
    expect(setup).toEqual({ serverUrl: expectedServerUrl, clientId: 'abc.access', clientSecret: 's3cret' });

    const res = await helpers.getCloudflareAccessDeviceSetup();
    expect(res.get('cache-control')).toContain('no-store');
  });

  it('returns null when the token is not configured', async () => {
    const setup = await helpers.getCloudflareAccessDeviceSetup({ raw: true });
    expect(setup).toBeNull();
  });

  it('returns null when only one value is set or a value is blank', async () => {
    process.env.CF_ACCESS_CLIENT_ID = 'abc.access';
    process.env.CF_ACCESS_CLIENT_SECRET = '   ';
    expect(await helpers.getCloudflareAccessDeviceSetup({ raw: true })).toBeNull();

    delete process.env.CF_ACCESS_CLIENT_SECRET;
    expect(await helpers.getCloudflareAccessDeviceSetup({ raw: true })).toBeNull();
  });

  it('rejects a non-admin with 401', async () => {
    process.env.CF_ACCESS_CLIENT_ID = 'abc.access';
    process.env.CF_ACCESS_CLIENT_SECRET = 's3cret';
    process.env.ADMIN_USERS = 'someone-else';

    const res = await helpers.getCloudflareAccessDeviceSetup();
    expect(res.statusCode).toBe(401);
    expect(JSON.stringify(res.body)).not.toContain('s3cret');
  });

  it('rejects a signed-out request with 401', async () => {
    process.env.CF_ACCESS_CLIENT_ID = 'abc.access';
    process.env.CF_ACCESS_CLIENT_SECRET = 's3cret';

    const res = await helpers.withoutSession(() => helpers.getCloudflareAccessDeviceSetup());
    expect(res.statusCode).toBe(401);
    expect(JSON.stringify(res.body)).not.toContain('s3cret');
  });
});
