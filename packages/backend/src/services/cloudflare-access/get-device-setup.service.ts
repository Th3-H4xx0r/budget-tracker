import type { CloudflareAccessDeviceSetup } from '@bt/shared/types';
import { EnvVar, isEnvConfigured } from '@common/utils/env';

/**
 * The Cloudflare Access service token (from `CF_ACCESS_CLIENT_ID` / `CF_ACCESS_CLIENT_SECRET`)
 * plus the server origin, for provisioning a device. `null` unless both values are configured
 * (non-blank, not a template placeholder). Reads `process.env` at call time.
 */
export const getCloudflareAccessDeviceSetup = (): CloudflareAccessDeviceSetup | null => {
  const clientId = (process.env.CF_ACCESS_CLIENT_ID || '').trim();
  const clientSecret = (process.env.CF_ACCESS_CLIENT_SECRET || '').trim();
  if (
    !isEnvConfigured(EnvVar.CF_ACCESS_CLIENT_ID, clientId) ||
    !isEnvConfigured(EnvVar.CF_ACCESS_CLIENT_SECRET, clientSecret)
  ) {
    return null;
  }

  const serverUrl = (process.env.AUTH_ORIGIN || 'https://localhost:8100').replace(/\/+$/, '');
  return { serverUrl, clientId, clientSecret };
};
