import type { getCloudflareAccessDeviceSetup as apiGetCloudflareAccessDeviceSetup } from '@services/cloudflare-access/get-device-setup.service';

import { makeRequest } from './common';

export function getCloudflareAccessDeviceSetup<R extends boolean | undefined = false>({
  raw,
}: {
  raw?: R;
} = {}) {
  return makeRequest<ReturnType<typeof apiGetCloudflareAccessDeviceSetup>, R>({
    method: 'get',
    url: '/admin/cloudflare-access',
    raw,
  });
}
