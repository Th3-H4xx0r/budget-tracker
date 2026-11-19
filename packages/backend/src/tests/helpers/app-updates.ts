import { app } from '@root/app';
import { API_PREFIX } from '@root/config';
import type { getLatestAppUpdate as apiGetLatestAppUpdate } from '@services/app-updates/get-latest.service';
import type { getInstallStatus as apiGetInstallStatus } from '@services/app-updates/install-status.service';
import type { rollbackAppUpdate as apiRollbackAppUpdate } from '@services/app-updates/rollback.service';
import type { uploadAppUpdate as apiUploadAppUpdate } from '@services/app-updates/upload.service';
import JSZip from 'jszip';
import request from 'supertest';

import { makeRequest } from './common';

/** A minimal IPA: a zip holding Payload/MoneyMatter.app/Info.plist (XML plist). */
export const buildFakeIpa = async ({
  build,
  version = '1.0',
  bundleId = 'app.moneymatter.test',
  extra = '',
}: {
  build: number;
  version?: string;
  bundleId?: string;
  /** Appended to the archive so two IPAs of one build can differ. */
  extra?: string;
}): Promise<Buffer> => {
  const zip = new JSZip();
  zip.file(
    'Payload/MoneyMatter.app/Info.plist',
    `<?xml version="1.0" encoding="UTF-8"?>
<plist version="1.0"><dict>
<key>CFBundleIdentifier</key><string>${bundleId}</string>
<key>CFBundleVersion</key><string>${build}</string>
<key>CFBundleShortVersionString</key><string>${version}</string>
</dict></plist>`,
  );
  if (extra) zip.file('Payload/MoneyMatter.app/extra.bin', extra);
  return zip.generateAsync({ type: 'nodebuffer' });
};

export function getLatestAppUpdate<R extends boolean | undefined = false>({
  build,
  platform = 'ios',
  raw,
}: {
  build: number;
  platform?: string;
  raw?: R;
}) {
  return makeRequest<Awaited<ReturnType<typeof apiGetLatestAppUpdate>>, R>({
    method: 'get',
    url: '/app-updates/latest',
    payload: { platform, build: String(build) },
    raw,
  });
}

export function getAppUpdateInstallStatus<R extends boolean | undefined = false>({
  token,
  raw,
}: {
  token: string;
  raw?: R;
}) {
  return makeRequest<ReturnType<typeof apiGetInstallStatus>, R>({
    method: 'get',
    url: '/app-updates/install-status',
    payload: { token },
    raw,
  });
}

/** Uploads through the real endpoint with the raw IPA bytes; `token` defaults to the configured upload token. */
export async function uploadAppUpdate({
  ipa,
  build,
  token = process.env.APP_UPDATE_UPLOAD_TOKEN,
  platform = 'ios',
  notes,
  commit,
  contentLength,
}: {
  ipa: Buffer;
  build: number;
  token?: string;
  platform?: string;
  notes?: string;
  commit?: string;
  /** Overrides the declared Content-Length, to exercise the size limit without sending that many bytes. */
  contentLength?: number;
}) {
  const query = new URLSearchParams({ platform, build: String(build) });
  if (notes) query.set('notes', notes);
  if (commit) query.set('commit', commit);
  const req = request(app)
    .post(`${API_PREFIX}/app-updates/upload?${query.toString()}`)
    .set('Content-Type', 'application/octet-stream');
  if (token) req.set('Authorization', `Bearer ${token}`);
  if (contentLength !== undefined) req.set('Content-Length', String(contentLength));
  const res = await req.send(ipa);
  return res as typeof res & { body: { response: Awaited<ReturnType<typeof apiUploadAppUpdate>> } };
}

export async function rollbackAppUpdate({
  token = process.env.APP_UPDATE_UPLOAD_TOKEN,
  platform = 'ios',
}: { token?: string; platform?: string } = {}) {
  const req = request(app).post(`${API_PREFIX}/app-updates/rollback?platform=${platform}`);
  if (token) req.set('Authorization', `Bearer ${token}`);
  const res = await req;
  return res as typeof res & { body: { response: Awaited<ReturnType<typeof apiRollbackAppUpdate>> } };
}

/** Public OTA routes sit outside the API prefix and need no session. */
export const getOtaManifest = ({ token }: { token: string }) => request(app).get(`/ota/m/${token}.plist`);

export const downloadOtaPackage = ({ token, fileName = 'MoneyMatter.ipa' }: { token: string; fileName?: string }) =>
  request(app)
    .get(`/ota/d/${token}/${fileName}`)
    .buffer(true)
    .parse((res, callback) => {
      const chunks: Buffer[] = [];
      res.on('data', (chunk: Buffer) => chunks.push(chunk));
      res.on('end', () => callback(null, Buffer.concat(chunks)));
    });

export const headOtaPackage = ({ token, fileName = 'MoneyMatter.ipa' }: { token: string; fileName?: string }) =>
  request(app).head(`/ota/d/${token}/${fileName}`);

/** The token embedded in an itms-services install URL. */
export const extractOtaToken = ({ installUrl }: { installUrl: string }): string => {
  const manifestUrl = new URL(installUrl.replace('itms-services://', 'https://x/')).searchParams.get('url')!;
  return /\/ota\/m\/(.+)\.plist$/.exec(manifestUrl)![1]!;
};
