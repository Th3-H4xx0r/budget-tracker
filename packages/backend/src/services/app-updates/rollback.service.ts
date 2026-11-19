import type { AppUpdatePlatform, AppUpdateRollbackResult } from '@bt/shared/types';
import { NotFoundError } from '@js/errors';

import { updateSlot } from './storage';

/** Makes the previous build current again; the build it replaces is dropped. */
export const rollbackAppUpdate = ({ platform }: { platform: AppUpdatePlatform }): Promise<AppUpdateRollbackResult> =>
  updateSlot({
    platform,
    fn: async ({ slot }) => {
      if (!slot.previous) throw new NotFoundError({ message: 'There is no previous build to roll back to.' });
      return { slot: { current: slot.previous, previous: null }, result: { build: slot.previous.build } };
    },
  });
