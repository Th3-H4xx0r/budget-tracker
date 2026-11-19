import { api } from '@/api/_api';
import type { CloudflareAccessDeviceSetup } from '@bt/shared/types';

export const getCloudflareAccessDeviceSetup = async (): Promise<CloudflareAccessDeviceSetup | null> => {
  return api.get('/admin/cloudflare-access');
};
