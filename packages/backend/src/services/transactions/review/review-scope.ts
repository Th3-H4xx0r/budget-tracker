/**
 * Query policies shared by every review read and write. Access is the caller's own rows
 * (`userId`), so transactions on accounts shared with them never enter their queue.
 * `reviewStatus` alone decides what is listed: planned and balance-adjustment rows start
 * `not_required`, and a row the user moved into a review status by hand stays where they put it.
 */
export const reviewScope = ({ userId }: { userId: number }) => ({
  planned: 'include' as const,
  access: { creator: userId },
  balanceAdjustments: 'include' as const,
});
