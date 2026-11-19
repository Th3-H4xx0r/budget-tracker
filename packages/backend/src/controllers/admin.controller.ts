import { PLANS } from '@bt/shared/types';
import { createController } from '@controllers/helpers/controller-factory';
import { updateUserPlan } from '@services/admin/user-plan.service';
import { getCloudflareAccessDeviceSetup } from '@services/cloudflare-access/get-device-setup.service';
import { z } from 'zod';

export const adminGetCloudflareAccessDeviceSetup = createController(z.object({}), async ({ res }) => {
  res.set('Cache-Control', 'no-store');
  return { data: getCloudflareAccessDeviceSetup() };
});

export const adminUpdateUserPlan = createController(
  z.object({
    params: z.object({ id: z.coerce.number().int().positive() }),
    body: z
      .object({
        plan: z.enum([PLANS.essential, PLANS.plus, PLANS.early_adopter]).nullable().optional(),
        trialEndsAt: z.coerce.date().nullable().optional(),
      })
      .strict(),
  }),
  async ({ params, body, user }) => ({
    data: await updateUserPlan({ userId: params.id, actorId: user.id, ...body }),
  }),
);
