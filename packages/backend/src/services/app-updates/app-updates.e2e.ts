import { afterEach, beforeEach, describe, expect, it } from '@jest/globals';
import * as helpers from '@tests/helpers';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';

const ENV_KEYS = [
  'APP_UPDATES_DIR',
  'APP_UPDATE_UPLOAD_TOKEN',
  'APP_UPDATES_SIGNING_KEY',
  'APP_UPDATES_PUBLIC_URL',
  'ADMIN_USERS',
] as const;
const PUBLIC_URL = 'https://updates.example.test';
const BUNDLE_ID = 'app.moneymatter.test';

const upload = async ({
  build,
  version = '1.2',
  bundleId = BUNDLE_ID,
}: {
  build: number;
  version?: string;
  bundleId?: string;
}) => helpers.uploadAppUpdate({ ipa: await helpers.buildFakeIpa({ build, version, bundleId }), build });

describe('App updates (OTA)', () => {
  const originals: Partial<Record<(typeof ENV_KEYS)[number], string | undefined>> = {};
  let dir: string;

  beforeEach(() => {
    for (const key of ENV_KEYS) originals[key] = process.env[key];
    dir = fs.mkdtempSync(path.join(os.tmpdir(), 'bt-app-updates-e2e-'));
    process.env.APP_UPDATES_DIR = dir;
    process.env.APP_UPDATE_UPLOAD_TOKEN = 'upload-secret-0123456789abcdef0123456789';
    process.env.APP_UPDATES_SIGNING_KEY = 'signing-secret-0123456789abcdef0123456789';
    process.env.APP_UPDATES_PUBLIC_URL = PUBLIC_URL;
    process.env.ADMIN_USERS = 'test1';
  });

  afterEach(() => {
    fs.rmSync(dir, { recursive: true, force: true });
    for (const key of ENV_KEYS) {
      if (originals[key] === undefined) delete process.env[key];
      else process.env[key] = originals[key];
    }
  });

  describe('GET /app-updates/latest', () => {
    it('reports nothing available when no build was uploaded', async () => {
      const latest = await helpers.getLatestAppUpdate({ build: 5, raw: true });

      expect(latest).toEqual({
        available: false,
        platform: 'ios',
        build: null,
        version: null,
        notes: null,
        commit: null,
        size: null,
        uploadedAt: null,
        installUrl: null,
        sha256: null,
      });
    });

    it('offers a newer build with an itms-services install URL', async () => {
      const ipa = await helpers.buildFakeIpa({ build: 10, version: '2.0', bundleId: BUNDLE_ID });
      const uploaded = await helpers.uploadAppUpdate({ ipa, build: 10, notes: 'Fixes', commit: 'abc123' });
      expect(uploaded.statusCode).toBe(200);
      expect(uploaded.body.response).toMatchObject({
        build: 10,
        version: '2.0',
        bundleId: BUNDLE_ID,
        size: ipa.length,
      });

      const latest = await helpers.getLatestAppUpdate({ build: 9, raw: true });

      expect(latest).toMatchObject({
        available: true,
        build: 10,
        version: '2.0',
        notes: 'Fixes',
        commit: 'abc123',
        size: ipa.length,
        sha256: uploaded.body.response.sha256,
      });
      expect(latest.installUrl).toMatch(/^itms-services:\/\/\?action=download-manifest&url=/);
      expect(decodeURIComponent(latest.installUrl!)).toContain(`${PUBLIC_URL}/ota/m/`);
      expect(new Date(latest.uploadedAt!).toString()).not.toBe('Invalid Date');
    });

    it('offers nothing when the client build is equal or higher', async () => {
      await upload({ build: 10 });

      expect((await helpers.getLatestAppUpdate({ build: 10, raw: true })).available).toBe(false);
      expect((await helpers.getLatestAppUpdate({ build: 11, raw: true })).available).toBe(false);
    });

    it('never offers an update to an unstamped dev build (build 1)', async () => {
      await upload({ build: 10 });

      expect((await helpers.getLatestAppUpdate({ build: 1, raw: true })).available).toBe(false);
    });

    it('withholds the install URL when the public base URL is not https', async () => {
      process.env.APP_UPDATES_PUBLIC_URL = 'http://updates.example.test';
      await upload({ build: 10 });

      const latest = await helpers.getLatestAppUpdate({ build: 9, raw: true });

      expect(latest.available).toBe(true);
      expect(latest.installUrl).toBeNull();
    });

    it('rejects a non-admin with 401', async () => {
      process.env.ADMIN_USERS = 'someone-else';

      const res = await helpers.getLatestAppUpdate({ build: 5 });

      expect(res.statusCode).toBe(401);
    });

    it('rejects a signed-out request with 401', async () => {
      const res = await helpers.withoutSession(() => helpers.getLatestAppUpdate({ build: 5 }));

      expect(res.statusCode).toBe(401);
    });

    it('rejects an unsupported platform with 422', async () => {
      const res = await helpers.getLatestAppUpdate({ build: 2, platform: 'android' });

      expect(res.statusCode).toBe(422);
    });
  });

  describe('POST /app-updates/upload', () => {
    it('rejects a wrong token with 401', async () => {
      const res = await helpers.uploadAppUpdate({
        ipa: await helpers.buildFakeIpa({ build: 10 }),
        build: 10,
        token: 'nope',
      });

      expect(res.statusCode).toBe(401);
    });

    it('rejects a missing token with 401', async () => {
      const res = await helpers.uploadAppUpdate({
        ipa: await helpers.buildFakeIpa({ build: 10 }),
        build: 10,
        token: '',
      });

      expect(res.statusCode).toBe(401);
    });

    it('answers 404 when no upload token is configured', async () => {
      delete process.env.APP_UPDATE_UPLOAD_TOKEN;

      const res = await helpers.uploadAppUpdate({
        ipa: await helpers.buildFakeIpa({ build: 10 }),
        build: 10,
        token: 'anything',
      });

      expect(res.statusCode).toBe(404);
    });

    it('rejects an archive whose build differs from the build param with 400', async () => {
      const res = await helpers.uploadAppUpdate({ ipa: await helpers.buildFakeIpa({ build: 11 }), build: 10 });

      expect(res.statusCode).toBe(400);
      expect((await helpers.getLatestAppUpdate({ build: 2, raw: true })).available).toBe(false);
    });

    it('answers 404 when the upload token is shorter than 32 characters', async () => {
      process.env.APP_UPDATE_UPLOAD_TOKEN = 'too-short';

      const res = await helpers.uploadAppUpdate({
        ipa: await helpers.buildFakeIpa({ build: 10 }),
        build: 10,
        token: 'too-short',
      });

      expect(res.statusCode).toBe(404);
    });

    it('rejects an empty body with 400', async () => {
      const res = await helpers.uploadAppUpdate({ ipa: Buffer.alloc(0), build: 10 });

      expect(res.statusCode).toBe(400);
    });

    it('rejects a body that is not an IPA with 400', async () => {
      const res = await helpers.uploadAppUpdate({ ipa: Buffer.from('not a zip'), build: 10 });

      expect(res.statusCode).toBe(400);
    });

    it('rejects a build that is not newer than the current one with 409', async () => {
      await upload({ build: 10 });

      expect((await upload({ build: 10 })).statusCode).toBe(409);
      expect((await upload({ build: 9 })).statusCode).toBe(409);
    });

    it('rejects a different bundle id with 409', async () => {
      await upload({ build: 10 });

      const res = await upload({ build: 11, bundleId: 'app.other' });

      expect(res.statusCode).toBe(409);
      expect((await helpers.getLatestAppUpdate({ build: 2, raw: true })).build).toBe(10);
    });

    it('keeps only the current and previous build files', async () => {
      await upload({ build: 10 });
      await upload({ build: 11 });
      await upload({ build: 12 });

      expect(
        fs
          .readdirSync(dir)
          .filter((name) => name.endsWith('.ipa'))
          .toSorted(),
      ).toEqual(['ios-11.ipa', 'ios-12.ipa']);
    });
  });

  describe('OTA install links', () => {
    const installTokenFor = async ({ build, clientBuild }: { build: number; clientBuild: number }) => {
      const ipa = await helpers.buildFakeIpa({ build, version: '3.1', bundleId: BUNDLE_ID });
      await helpers.uploadAppUpdate({ ipa, build });
      const latest = await helpers.getLatestAppUpdate({ build: clientBuild, raw: true });
      return { ipa, token: helpers.extractOtaToken({ installUrl: latest.installUrl! }) };
    };

    it('serves the manifest, then the IPA, and flags the install as started', async () => {
      const { ipa, token } = await installTokenFor({ build: 10, clientBuild: 9 });

      const manifest = await helpers.getOtaManifest({ token });
      expect(manifest.statusCode).toBe(200);
      expect(manifest.headers['content-type']).toContain('xml');
      expect(manifest.text).toContain(BUNDLE_ID);
      expect(manifest.text).toContain('<string>3.1</string>');
      expect(manifest.text).toContain(`${PUBLIC_URL}/ota/d/${token}/MoneyMatter.ipa`);

      expect((await helpers.getAppUpdateInstallStatus({ token, raw: true })).started).toBe(false);

      const download = await helpers.downloadOtaPackage({ token });
      expect(download.statusCode).toBe(200);
      expect(download.headers['content-type']).toContain('application/octet-stream');
      expect(Number(download.headers['content-length'])).toBe(ipa.length);
      expect(Buffer.compare(download.body as Buffer, ipa)).toBe(0);

      expect((await helpers.getAppUpdateInstallStatus({ token, raw: true })).started).toBe(true);
    });

    it('answers HEAD on the IPA without flagging the install as started', async () => {
      // A build of its own, so the token differs from the one the GET test already marked as started.
      const { ipa, token } = await installTokenFor({ build: 31, clientBuild: 30 });

      const head = await helpers.headOtaPackage({ token });

      expect(head.statusCode).toBe(200);
      expect(Number(head.headers['content-length'])).toBe(ipa.length);
      expect((await helpers.getAppUpdateInstallStatus({ token, raw: true })).started).toBe(false);
    });

    it('answers a tampered token with a bare 403', async () => {
      const { token } = await installTokenFor({ build: 10, clientBuild: 9 });
      const tampered = token.slice(0, -1) + (token.endsWith('0') ? '1' : '0');

      const manifest = await helpers.getOtaManifest({ token: tampered });
      const download = await helpers.downloadOtaPackage({ token: tampered });

      expect(manifest.statusCode).toBe(403);
      expect(download.statusCode).toBe(403);
      expect((await helpers.getAppUpdateInstallStatus({ token: tampered, raw: true })).started).toBe(false);
    });

    it('answers 403 for a wrong file name', async () => {
      const { token } = await installTokenFor({ build: 10, clientBuild: 9 });

      const download = await helpers.downloadOtaPackage({ token, fileName: 'Other.ipa' });

      expect(download.statusCode).toBe(403);
    });

    it('answers 403 once the build the token names is no longer kept', async () => {
      const { token } = await installTokenFor({ build: 10, clientBuild: 9 });
      await upload({ build: 11 });
      await upload({ build: 12 });

      expect((await helpers.getOtaManifest({ token })).statusCode).toBe(403);
    });
  });

  describe('POST /app-updates/rollback', () => {
    it('makes the previous build current again', async () => {
      await upload({ build: 10, version: '1.0' });
      await upload({ build: 11, version: '1.1' });

      const res = await helpers.rollbackAppUpdate();

      expect(res.statusCode).toBe(200);
      expect(res.body.response).toEqual({ build: 10 });
      const latest = await helpers.getLatestAppUpdate({ build: 2, raw: true });
      expect(latest).toMatchObject({ build: 10, version: '1.0' });
      expect(fs.readdirSync(dir).filter((name) => name.endsWith('.ipa'))).toEqual(['ios-10.ipa']);
    });

    it('answers 404 when there is no previous build', async () => {
      await upload({ build: 10 });

      expect((await helpers.rollbackAppUpdate()).statusCode).toBe(404);
    });

    it('rejects a wrong token with 401', async () => {
      expect((await helpers.rollbackAppUpdate({ token: 'nope' })).statusCode).toBe(401);
    });
  });
});
