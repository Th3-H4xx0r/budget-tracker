import { describe, expect, it } from '@jest/globals';

import { daysBetween, occurrences } from './occurrences';

describe('occurrences', () => {
  it('walks a monthly schedule from an anchor before the range into the range', () => {
    expect(
      occurrences({
        startDate: '2026-03-01',
        endDate: '2026-05-31',
        anchorDate: '2026-01-15',
        frequency: 'monthly',
      }),
    ).toEqual(['2026-03-15', '2026-04-15', '2026-05-15']);
  });

  it('caps a finite schedule at maxCount counted from the anchor', () => {
    expect(
      occurrences({
        startDate: '2026-03-01',
        endDate: '2026-12-31',
        anchorDate: '2026-01-15',
        frequency: 'monthly',
        maxCount: 4,
      }),
    ).toEqual(['2026-03-15', '2026-04-15']);
  });

  it('yields a one-off date only when it falls in the range', () => {
    expect(
      occurrences({
        startDate: '2026-03-01',
        endDate: '2026-03-31',
        anchorDate: '2026-03-10',
        frequency: 'once',
      }),
    ).toEqual(['2026-03-10']);
    expect(
      occurrences({
        startDate: '2026-03-01',
        endDate: '2026-03-31',
        anchorDate: '2026-04-10',
        frequency: 'once',
      }),
    ).toEqual([]);
  });
});

describe('daysBetween', () => {
  it('is the absolute day distance', () => {
    expect(daysBetween({ from: '2026-03-10', to: '2026-03-04' })).toBe(6);
  });
});
