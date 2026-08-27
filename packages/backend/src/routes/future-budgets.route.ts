import * as controller from '@controllers/future-budgets/future-budgets';
import { authenticateSession } from '@middlewares/better-auth';
import { blockDemoUsers } from '@middlewares/block-demo-users';
import { checkBaseCurrencyLock } from '@middlewares/check-base-currency-lock';
import { validateEndpoint } from '@middlewares/validations';
import { Router } from 'express';

const router = Router();
router.get(
  '/salary-settings',
  authenticateSession,
  validateEndpoint(controller.getSalarySettings.schema),
  controller.getSalarySettings.handler,
);
router.put(
  '/salary-settings',
  authenticateSession,
  blockDemoUsers,
  checkBaseCurrencyLock,
  validateEndpoint(controller.updateSalarySettings.schema),
  controller.updateSalarySettings.handler,
);
router.get('/', authenticateSession, validateEndpoint(controller.listPlans.schema), controller.listPlans.handler);
router.post(
  '/',
  authenticateSession,
  blockDemoUsers,
  checkBaseCurrencyLock,
  validateEndpoint(controller.createPlan.schema),
  controller.createPlan.handler,
);
router.get(
  '/:id',
  authenticateSession,
  validateEndpoint(controller.getPlanDetails.schema),
  controller.getPlanDetails.handler,
);
router.put(
  '/:id',
  authenticateSession,
  blockDemoUsers,
  checkBaseCurrencyLock,
  validateEndpoint(controller.updatePlan.schema),
  controller.updatePlan.handler,
);
router.post(
  '/:id/salary-profile',
  authenticateSession,
  blockDemoUsers,
  checkBaseCurrencyLock,
  validateEndpoint(controller.applyCurrentSalary.schema),
  controller.applyCurrentSalary.handler,
);
router.post(
  '/:id/entries',
  authenticateSession,
  blockDemoUsers,
  checkBaseCurrencyLock,
  validateEndpoint(controller.createEntry.schema),
  controller.createEntry.handler,
);
router.delete(
  '/:id/entries/:entryId',
  authenticateSession,
  blockDemoUsers,
  checkBaseCurrencyLock,
  validateEndpoint(controller.deleteEntry.schema),
  controller.deleteEntry.handler,
);
router.put(
  '/:id/entries/:entryId',
  authenticateSession,
  blockDemoUsers,
  checkBaseCurrencyLock,
  validateEndpoint(controller.updateEntry.schema),
  controller.updateEntry.handler,
);
router.delete(
  '/:id',
  authenticateSession,
  blockDemoUsers,
  checkBaseCurrencyLock,
  validateEndpoint(controller.deletePlan.schema),
  controller.deletePlan.handler,
);
router.put(
  '/:id/recurring/:subscriptionId',
  authenticateSession,
  blockDemoUsers,
  checkBaseCurrencyLock,
  validateEndpoint(controller.updateRecurringOverride.schema),
  controller.updateRecurringOverride.handler,
);
export default router;
