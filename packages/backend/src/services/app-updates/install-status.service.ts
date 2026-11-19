import type { AppUpdateInstallStatus } from '@bt/shared/types';

import { LINK_TTL_SECONDS } from './tokens';

// Install links whose package iOS has started fetching. iOS fetches it only after the user
// confirms the install prompt, so the app reads this to know it should step aside.
const startedInstalls = new Map<string, number>();

export const markInstallStarted = ({ token, now = Date.now() }: { token: string; now?: number }) => {
  for (const [known, at] of startedInstalls) {
    if (now - at > 2 * LINK_TTL_SECONDS * 1000) startedInstalls.delete(known);
  }
  startedInstalls.set(token, now);
};

export const getInstallStatus = ({ token }: { token: string }): AppUpdateInstallStatus => ({
  started: startedInstalls.has(token),
});
