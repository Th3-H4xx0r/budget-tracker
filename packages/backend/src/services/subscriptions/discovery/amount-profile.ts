import type { AmountVariabilityClass } from '@bt/shared/types';

import { computeMedian } from '../detect-candidates-utils';
import type { AmountProfile } from './types';

const FIXED_MAX_VARIABILITY = 0.03;
const STABLE_MAX_VARIABILITY = 0.15;
const STEP_PAIR_MAX_DIFF = 0.03;
const STEP_MIN_SHIFT = 0.1;

export const classifyVariability = ({ variability }: { variability: number }): AmountVariabilityClass => {
  if (variability <= FIXED_MAX_VARIABILITY) return 'fixed';
  if (variability <= STABLE_MAX_VARIABILITY) return 'stable';
  return 'variable';
};

/**
 * Median/MAD profile of a cluster's amounts (absolute cents, chronological order). A clear step
 * change (the last two amounts within 3% of each other and more than 10% off the earlier median)
 * makes the latest level the expected amount, so a price increase predicts the new price.
 */
export function buildAmountProfile({ amounts }: { amounts: number[] }): AmountProfile {
  const medianCents = computeMedian({ values: amounts });
  const madCents = computeMedian({ values: amounts.map((amount) => Math.abs(amount - medianCents)) });
  const variability = medianCents > 0 ? madCents / medianCents : 0;

  let expectedCents = medianCents;
  if (amounts.length >= 3) {
    const last = amounts[amounts.length - 1]!;
    const previous = amounts[amounts.length - 2]!;
    const earlierMedian = computeMedian({ values: amounts.slice(0, -2) });
    const pairDiff = Math.abs(last - previous) / Math.max(last, previous, 1);
    const shift = earlierMedian > 0 ? Math.abs(last - earlierMedian) / earlierMedian : 0;
    if (pairDiff <= STEP_PAIR_MAX_DIFF && shift > STEP_MIN_SHIFT) expectedCents = last;
  }

  return {
    medianCents: Math.round(medianCents),
    madCents: Math.round(madCents),
    variability,
    variabilityClass: classifyVariability({ variability }),
    expectedCents: Math.round(expectedCents),
  };
}
