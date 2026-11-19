import type { AppUpdateLatest, AppUpdatePlatform } from '@bt/shared/types';

import { getSlot } from './storage';
import { buildInstallUrl, createToken, publicBaseUrl } from './tokens';

/** Builds below 2 are unstamped dev builds; they may be newer than anything published, so they are never offered an update. */
const MIN_UPDATABLE_CLIENT_BUILD = 2;

export const getLatestAppUpdate = async ({
  platform,
  clientBuild,
}: {
  platform: AppUpdatePlatform;
  clientBuild: number;
}): Promise<AppUpdateLatest> => {
  const { current } = await getSlot({ platform });

  if (!current || clientBuild < MIN_UPDATABLE_CLIENT_BUILD || current.build <= clientBuild) {
    return {
      available: false,
      platform,
      build: null,
      version: null,
      notes: null,
      commit: null,
      size: null,
      uploadedAt: null,
      installUrl: null,
      sha256: null,
    };
  }

  const base = publicBaseUrl();
  return {
    available: true,
    platform,
    build: current.build,
    version: current.version,
    notes: current.notes,
    commit: current.commit,
    size: current.size,
    uploadedAt: current.uploadedAt,
    installUrl: base.startsWith('https://')
      ? buildInstallUrl({ token: createToken({ build: current.build }), base })
      : null,
    sha256: current.sha256,
  };
};
