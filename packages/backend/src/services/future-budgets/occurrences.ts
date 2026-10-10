const DAY_MS = 24 * 60 * 60 * 1000;

const toUtcDay = ({ value }: { value: string }): Date => new Date(`${value}T00:00:00.000Z`);

const toDateString = ({ value }: { value: Date }): string => value.toISOString().slice(0, 10);

const addOccurrence = ({
  date,
  frequency,
  intervalDays,
}: {
  date: Date;
  frequency: string;
  intervalDays?: number | null;
}): Date => {
  const next = new Date(date);
  if (frequency === 'weekly') next.setUTCDate(next.getUTCDate() + 7);
  else if (frequency === 'biweekly') next.setUTCDate(next.getUTCDate() + 14);
  else if (frequency === 'quarterly') next.setUTCMonth(next.getUTCMonth() + 3);
  else if (frequency === 'semi_annual') next.setUTCMonth(next.getUTCMonth() + 6);
  else if (frequency === 'annual') next.setUTCFullYear(next.getUTCFullYear() + 1);
  else if (frequency === 'custom') next.setUTCDate(next.getUTCDate() + (intervalDays ?? 30));
  else next.setUTCMonth(next.getUTCMonth() + 1);
  return next;
};

/**
 * Dates (`YYYY-MM-DD`) of a schedule that fall in `[startDate, endDate]`. The schedule starts at
 * `anchorDate` (or `startDate`) and repeats by `frequency`; `'once'` yields at most the anchor.
 * `maxCount` caps the schedule as a whole, counted from the anchor, so a finite schedule (an
 * installment plan) never projects past its last payment.
 */
export const occurrences = ({
  startDate,
  endDate,
  anchorDate,
  frequency,
  intervalDays,
  maxCount,
}: {
  startDate: string;
  endDate: string;
  anchorDate: string | null;
  frequency: string;
  intervalDays?: number | null;
  maxCount?: number | null;
}): string[] => {
  const rangeStart = toUtcDay({ value: startDate });
  const rangeEnd = toUtcDay({ value: endDate });
  let current = toUtcDay({ value: anchorDate ?? startDate });
  if (frequency === 'once') {
    return current >= rangeStart && current <= rangeEnd ? [toDateString({ value: current })] : [];
  }

  let index = 0;
  while (current < rangeStart) {
    current = addOccurrence({ date: current, frequency, intervalDays });
    index += 1;
  }
  const result: string[] = [];
  while (current <= rangeEnd && (maxCount == null || index < maxCount)) {
    result.push(toDateString({ value: current }));
    current = addOccurrence({ date: current, frequency, intervalDays });
    index += 1;
  }
  return result;
};

export const daysBetween = ({ from, to }: { from: string; to: string }): number =>
  Math.abs(toUtcDay({ value: to }).getTime() - toUtcDay({ value: from }).getTime()) / DAY_MS;
