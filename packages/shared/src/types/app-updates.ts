export const APP_UPDATE_PLATFORMS = ['ios'] as const;
export type AppUpdatePlatform = (typeof APP_UPDATE_PLATFORMS)[number];

/** Largest build archive the server accepts. */
export const APP_UPDATE_MAX_BYTES = 1024 * 1024 * 1024;

export interface AppUpdateLatest {
  available: boolean;
  platform: AppUpdatePlatform;
  build: number | null;
  version: string | null;
  notes: string | null;
  commit: string | null;
  size: number | null;
  /** ISO 8601 */
  uploadedAt: string | null;
  /** `itms-services://` link; null unless a build is available and the public base URL is https. */
  installUrl: string | null;
  sha256: string | null;
}

export interface AppUpdateInstallStatus {
  /** True once the install link's IPA has been fetched. */
  started: boolean;
}

export interface AppUpdateUploadResult {
  build: number;
  version: string;
  bundleId: string;
  size: number;
  sha256: string;
}

export interface AppUpdateRollbackResult {
  build: number;
}
