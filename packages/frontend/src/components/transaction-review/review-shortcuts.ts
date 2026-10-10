import { TRANSACTION_REVIEW_ACTION } from '@bt/shared/types';

import type { ReviewDecision } from './use-review-session';

/** Where the keydown landed: a text field, a focusable control, or anything else. */
export type ReviewShortcutTarget = 'editable' | 'interactive' | 'other';

type ReviewShortcut =
  | { kind: 'act'; action: ReviewDecision }
  | { kind: 'undo' }
  /** Only cancel the browser default; nothing else happens. */
  | { kind: 'swallow' };

const DECISION_BY_KEY: Record<string, ReviewDecision> = {
  ArrowRight: TRANSACTION_REVIEW_ACTION.reviewed,
  ArrowLeft: TRANSACTION_REVIEW_ACTION.checkLater,
  f: TRANSACTION_REVIEW_ACTION.fraud,
  F: TRANSACTION_REVIEW_ACTION.fraud,
};

/**
 * Maps a keydown in the review stack to what should happen. `null` leaves the event
 * alone. A held key never repeats a decision: repeated Enter is swallowed because a
 * focused button would otherwise click once per auto-repeat and sweep the queue.
 */
export const resolveReviewShortcut = ({
  key,
  repeat,
  metaKey,
  ctrlKey,
  altKey,
  shiftKey,
  target,
  hasCard,
}: {
  key: string;
  repeat: boolean;
  metaKey: boolean;
  ctrlKey: boolean;
  altKey: boolean;
  shiftKey: boolean;
  target: ReviewShortcutTarget;
  hasCard: boolean;
}): ReviewShortcut | null => {
  if (target === 'editable') return null;

  const isUndoChord = (metaKey || ctrlKey) && !shiftKey && !altKey && key.toLowerCase() === 'z';
  const isHandledKey = isUndoChord || key === 'Enter' || key in DECISION_BY_KEY;

  if (repeat) return isHandledKey ? { kind: 'swallow' } : null;
  if (isUndoChord) return { kind: 'undo' };
  if (metaKey || ctrlKey || altKey || !hasCard) return null;

  if (key === 'Enter') {
    // A focused control keeps its own Enter, so a keyboard user who tabbed to Fraud or
    // Undo gets that button. "Looks good" holds focus by default, so Enter confirms.
    if (target === 'interactive') return null;
    return { kind: 'act', action: TRANSACTION_REVIEW_ACTION.reviewed };
  }

  const action = DECISION_BY_KEY[key];
  return action ? { kind: 'act', action } : null;
};
