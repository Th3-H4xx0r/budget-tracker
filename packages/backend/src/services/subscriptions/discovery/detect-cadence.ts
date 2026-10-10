import { SUBSCRIPTION_FREQUENCIES } from '@bt/shared/types';

import type { CadenceFit } from './types';

const DAY_MS = 24 * 60 * 60 * 1000;

const NOMINAL_PERIOD_DAYS: Record<SUBSCRIPTION_FREQUENCIES, number> = {
  [SUBSCRIPTION_FREQUENCIES.weekly]: 7,
  [SUBSCRIPTION_FREQUENCIES.biweekly]: 14,
  [SUBSCRIPTION_FREQUENCIES.monthly]: 30.44,
  [SUBSCRIPTION_FREQUENCIES.quarterly]: 91.31,
  [SUBSCRIPTION_FREQUENCIES.semiAnnual]: 182.62,
  [SUBSCRIPTION_FREQUENCIES.annual]: 365.25,
};

/** Calendar months per period for monthly and longer frequencies (used for day-of-month and next-date math). */
export const PERIOD_MONTHS: Partial<Record<SUBSCRIPTION_FREQUENCIES, number>> = {
  [SUBSCRIPTION_FREQUENCIES.monthly]: 1,
  [SUBSCRIPTION_FREQUENCIES.quarterly]: 3,
  [SUBSCRIPTION_FREQUENCIES.semiAnnual]: 6,
  [SUBSCRIPTION_FREQUENCIES.annual]: 12,
};

/** Up to quarterly a pattern needs 3 occurrences; semi-annual and annual charges need 2. */
const minOccurrencesFor = ({ frequency }: { frequency: SUBSCRIPTION_FREQUENCIES }): number =>
  NOMINAL_PERIOD_DAYS[frequency] > NOMINAL_PERIOD_DAYS[SUBSCRIPTION_FREQUENCIES.quarterly] ? 2 : 3;

const DAY_OF_MONTH_SPREAD_BONUS_MAX_DAYS = 5;
const DAY_OF_MONTH_SPREAD_BONUS = 0.1;

/** Smallest arc of the 31-day circle covering every day of month, so 30, 31, 1, 2 spreads 3 days. */
function circularDayOfMonthSpread({ dates }: { dates: Date[] }): number {
  const days = [...new Set(dates.map((date) => date.getUTCDate()))].sort((a, b) => a - b);
  if (days.length <= 1) return 0;

  let largestGap = days[0]! + 31 - days[days.length - 1]!;
  for (let i = 1; i < days.length; i++) {
    largestGap = Math.max(largestGap, days[i]! - days[i - 1]!);
  }
  return 31 - largestGap;
}

function fitFrequency({ dates, frequency }: { dates: Date[]; frequency: SUBSCRIPTION_FREQUENCIES }): CadenceFit {
  const periodDays = NOMINAL_PERIOD_DAYS[frequency];
  const tolerance = Math.max(2, 0.15 * periodDays);

  // Slots are measured from the last fitted occurrence, so day-of-month drift never accumulates
  // and an off-cadence outlier costs only itself. `k >= 1` keeps two occurrences off one slot.
  let anchorTime = dates[0]!.getTime();
  let anchorSlot = 0;
  let fitted = 0;
  let maxFittedErrorDays = 0;

  for (let i = 1; i < dates.length; i++) {
    const deltaDays = (dates[i]!.getTime() - anchorTime) / DAY_MS;
    const slots = Math.max(1, Math.round(deltaDays / periodDays));
    const error = Math.abs(deltaDays - slots * periodDays);
    if (error <= tolerance) {
      fitted += 1;
      anchorSlot += slots;
      anchorTime = dates[i]!.getTime();
      maxFittedErrorDays = Math.max(maxFittedErrorDays, error);
    }
  }

  const spanDays = (dates[dates.length - 1]!.getTime() - dates[0]!.getTime()) / DAY_MS;
  const totalSlots = Math.max(anchorSlot, Math.round(spanDays / periodDays)) + 1;
  const fit = dates.length > 1 ? fitted / (dates.length - 1) : 0;
  const coverage = Math.min(1, (fitted + 1) / totalSlots);

  const dayOfMonthSpread = PERIOD_MONTHS[frequency] ? circularDayOfMonthSpread({ dates }) : null;
  const bonus =
    dayOfMonthSpread !== null && dayOfMonthSpread <= DAY_OF_MONTH_SPREAD_BONUS_MAX_DAYS ? DAY_OF_MONTH_SPREAD_BONUS : 0;

  return {
    frequency,
    periodDays,
    fit,
    coverage,
    dayOfMonthSpread,
    score: 0.6 * fit + 0.4 * coverage + bonus,
    maxFittedErrorDays,
  };
}

/**
 * Best-fitting frequency for occurrence dates sorted ascending. Each candidate frequency maps the
 * occurrences onto slots of its nominal period with a tolerance of max(2, 15%) days, so skipped
 * periods and a few days of jitter don't break the pattern. Returns null when no frequency has
 * enough occurrences.
 */
export function detectCadence({ dates }: { dates: Date[] }): CadenceFit | null {
  let best: CadenceFit | null = null;

  for (const frequency of Object.values(SUBSCRIPTION_FREQUENCIES)) {
    if (dates.length < minOccurrencesFor({ frequency })) continue;
    const candidate = fitFrequency({ dates, frequency });
    if (!best || candidate.score > best.score) best = candidate;
  }

  return best;
}
