import { getDefaultValue } from '@common/helpers/get-default-value-from-zod-schema';
import UserSettings, { DEFAULT_MONTHLY_SPENDING_BUDGET, ZodSettingsSchema } from '@models/user-settings.model';

import { withTransaction } from '../common/with-transaction';
import { type RedactedSettingsSchema, redactKeyMaterial } from './redact-key-material';

export const getUserSettings = withTransaction(
  async ({ userId }: { userId: number }): Promise<RedactedSettingsSchema> => {
    const userSettings = await UserSettings.findOne({
      where: { userId },
      attributes: ['settings'],
    });

    // `getDefaultValue` skips optional keys, so optional keys with a reported default are listed here.
    const defaults = {
      ...getDefaultValue(ZodSettingsSchema),
      monthlySpendingBudget: { ...DEFAULT_MONTHLY_SPENDING_BUDGET },
    };

    if (!userSettings) {
      return defaults;
    }

    // Merge defaults with stored settings to include any new fields
    return redactKeyMaterial({ settings: { ...defaults, ...userSettings.settings } });
  },
);
