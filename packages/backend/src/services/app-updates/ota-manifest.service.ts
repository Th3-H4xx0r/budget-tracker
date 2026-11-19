import fsp from 'node:fs/promises';

import { markInstallStarted } from './install-status.service';
import { buildFilePath } from './storage';
import { publicBaseUrl, resolveToken } from './tokens';

const IPA_DOWNLOAD_NAME = 'MoneyMatter.ipa';

const escapeXml = ({ value }: { value: string }) =>
  value.replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;');

/** The iOS over-the-air install manifest for the build the token names; null for an invalid token. */
export const getOtaManifest = async ({ token }: { token: string }): Promise<string | null> => {
  const record = await resolveToken({ token });
  if (!record) return null;
  const url = `${publicBaseUrl()}/ota/d/${token}/${IPA_DOWNLOAD_NAME}`;
  return `<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>items</key>
  <array>
    <dict>
      <key>assets</key>
      <array>
        <dict>
          <key>kind</key><string>software-package</string>
          <key>url</key><string>${escapeXml({ value: url })}</string>
        </dict>
      </array>
      <key>metadata</key>
      <dict>
        <key>bundle-identifier</key><string>${escapeXml({ value: record.bundleId })}</string>
        <key>bundle-version</key><string>${escapeXml({ value: record.version || '1.0' })}</string>
        <key>kind</key><string>software</string>
        <key>title</key><string>MoneyMatter</string>
      </dict>
    </dict>
  </array>
</dict>
</plist>
`;
};

/** Opens the IPA the token names; a GET (not a HEAD probe) marks the install as started. */
export const openOtaPackage = async ({
  token,
  fileName,
  markStarted,
}: {
  token: string;
  fileName: string;
  markStarted: boolean;
}): Promise<{ filePath: string } | null> => {
  const record = await resolveToken({ token });
  if (!record || fileName !== IPA_DOWNLOAD_NAME) return null;
  const filePath = buildFilePath({ file: record.file });
  try {
    await fsp.access(filePath);
    if (markStarted) markInstallStarted({ token });
    return { filePath };
  } catch {
    return null;
  }
};
