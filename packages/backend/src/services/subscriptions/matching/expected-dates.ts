import { SUBSCRIPTION_FREQUENCIES } from '@bt/shared/types';
import { addDays, addMonths, differenceInCalendarDays, getDaysInMonth } from 'date-fns';

/** Half-width (days) of the window around an expected date in which a payment counts as "on time". */
export const MATCH_WINDOW_DAYS: Record<SUBSCRIPTION_FREQUENCIES, number> = {
  [SUBSCRIPTION_FREQUENCIES.weekly]: 2,
  [SUBSCRIPTION_FREQUENCIES.biweekly]: 4,
  [SUBSCRIPTION_FREQUENCIES.monthly]: 6,
  [SUBSCRIPTION_FREQUENCIES.quarterly]: 10,
  [SUBSCRIPTION_FREQUENCIES.semiAnnual]: 15,
  [SUBSCRIPTION_FREQUENCIES.annual]: 20,
};

const STEP: Record<SUBSCRIPTION_FREQUENCIES, { days?: number; months?: number }> = {
  [SUBSCRIPTION_FREQUENCIES.weekly]: { days: 7 },
  [SUBSCRIPTION_FREQUENCIES.biweekly]: { days: 14 },
  [SUBSCRIPTION_FREQUENCIES.monthly]: { months: 1 },
  [SUBSCRIPTION_FREQUENCIES.quarterly]: { months: 3 },
  [SUBSCRIPTION_FREQUENCIES.semiAnnual]: { months: 6 },
  [SUBSCRIPTION_FREQUENCIES.annual]: { months: 12 },
};

export const toDateOnly = ({ date }: { date: Date }): string => date.toISOString().slice(0, 10);

const parseDateOnly = ({ value }: { value: string }): Date => new Date(`${value}T00:00:00Z`);

/** The k-th occurrence from the anchor (k may be negative), month-end clamped to `anchorDay`. */
const occurrence = ({
  anchor,
  anchorDay,
  frequency,
  k,
}: {
  anchor: Date;
  anchorDay: number;
  frequency: SUBSCRIPTION_FREQUENCIES;
  k: number;
}): Date => {
  const step = STEP[frequency];
  if (step.days) return addDays(anchor, step.days * k);

  const shifted = addMonths(new Date(Date.UTC(anchor.getUTCFullYear(), anchor.getUTCMonth(), 1)), step.months! * k);
  const day = Math.min(anchorDay, getDaysInMonth(shifted));
  return new Date(Date.UTC(shifted.getUTCFullYear(), shifted.getUTCMonth(), day));
};

/**
 * Expected payment dates near `around`: the schedule projected from the anchor (both directions)
 * plus every stored period due date within `windowDays` of it.
 */
export function expectedDatesAround({
  anchor,
  anchorDay,
  frequency,
  periodDueDates,
  around,
  windowDays,
}: {
  anchor: string | null;
  anchorDay: number | null;
  frequency: SUBSCRIPTION_FREQUENCIES;
  periodDueDates: string[];
  around: Date;
  windowDays: number;
}): string[] {
  const dates = new Set<string>();
  const aroundDay = parseDateOnly({ value: toDateOnly({ date: around }) });

  for (const dueDate of periodDueDates) {
    if (Math.abs(differenceInCalendarDays(parseDateOnly({ value: dueDate }), aroundDay)) <= windowDays * 3) {
      dates.add(dueDate);
    }
  }

  if (anchor) {
    const anchorDate = parseDateOnly({ value: anchor });
    const day = anchorDay ?? anchorDate.getUTCDate();
    const step = STEP[frequency];
    const periodDays = step.days ?? step.months! * 30.44;
    const k0 = Math.round(differenceInCalendarDays(aroundDay, anchorDate) / periodDays);
    for (const k of [k0 - 1, k0, k0 + 1]) {
      dates.add(toDateOnly({ date: occurrence({ anchor: anchorDate, anchorDay: day, frequency, k }) }));
    }
  }

  return [...dates];
}

/** Nearest expected date to `date` and its absolute distance in days; null when nothing is scheduled. */
export function nearestExpectedDate({
  dates,
  date,
}: {
  dates: string[];
  date: Date;
}): { dueDate: string; days: number } | null {
  const day = parseDateOnly({ value: toDateOnly({ date }) });
  let best: { dueDate: string; days: number } | null = null;

  for (const dueDate of dates) {
    const days = Math.abs(differenceInCalendarDays(parseDateOnly({ value: dueDate }), day));
    if (!best || days < best.days) best = { dueDate, days };
  }

  return best;
}

/** Absolute day distance between a YYYY-MM-DD date and a timestamp. */
export const daysBetween = ({ dueDate, date }: { dueDate: string; date: Date }): number =>
  Math.abs(differenceInCalendarDays(parseDateOnly({ value: dueDate }), parseDateOnly({ value: toDateOnly({ date }) })));
