import type { CloudflareAccessDeviceSetup } from '@bt/shared/types';

const QR_PAYLOAD_VERSION = 1;

/** JSON the iPhone app scans to learn the server origin and its Cloudflare Access service token. */
export const buildCloudflareAccessQrPayload = ({
  serverUrl,
  clientId,
  clientSecret,
}: CloudflareAccessDeviceSetup): string => {
  return JSON.stringify({
    v: QR_PAYLOAD_VERSION,
    server: serverUrl.replace(/\/+$/, ''),
    cfClientId: clientId,
    cfClientSecret: clientSecret,
  });
};
