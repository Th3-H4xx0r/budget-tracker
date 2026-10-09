import { TRANSACTION_REVIEW_ACTION } from '@bt/shared/types';
import { describe, expect, it } from 'vitest';

import { type ReviewShortcutTarget, resolveReviewShortcut } from './review-shortcuts';

const press = ({
  key,
  repeat = false,
  metaKey = false,
  ctrlKey = false,
  altKey = false,
  shiftKey = false,
  target = 'other',
  hasCard = true,
}: {
  key: string;
  repeat?: boolean;
  metaKey?: boolean;
  ctrlKey?: boolean;
  altKey?: boolean;
  shiftKey?: boolean;
  target?: ReviewShortcutTarget;
  hasCard?: boolean;
}) => resolveReviewShortcut({ key, repeat, metaKey, ctrlKey, altKey, shiftKey, target, hasCard });

describe('resolveReviewShortcut', () => {
  it.each([
    { key: 'ArrowRight', action: TRANSACTION_REVIEW_ACTION.reviewed },
    { key: 'Enter', action: TRANSACTION_REVIEW_ACTION.reviewed },
    { key: 'ArrowLeft', action: TRANSACTION_REVIEW_ACTION.checkLater },
    { key: 'f', action: TRANSACTION_REVIEW_ACTION.fraud },
    { key: 'F', action: TRANSACTION_REVIEW_ACTION.fraud },
  ])('maps $key to $action', ({ key, action }) => {
    expect(press({ key })).toEqual({ kind: 'act', action });
  });

  it('maps Cmd+Z and Ctrl+Z to undo, even without a card', () => {
    expect(press({ key: 'z', metaKey: true, hasCard: false })).toEqual({ kind: 'undo' });
    expect(press({ key: 'z', ctrlKey: true })).toEqual({ kind: 'undo' });
    expect(press({ key: 'z', metaKey: true, shiftKey: true })).toBeNull();
  });

  it('leaves Enter to a focused control', () => {
    expect(press({ key: 'Enter', target: 'interactive' })).toBeNull();
  });

  it('ignores everything typed into a text field', () => {
    expect(press({ key: 'f', target: 'editable' })).toBeNull();
    expect(press({ key: 'z', metaKey: true, target: 'editable' })).toBeNull();
  });

  it('ignores decisions when there is no card', () => {
    expect(press({ key: 'ArrowRight', hasCard: false })).toBeNull();
  });

  it('ignores decision keys combined with modifiers', () => {
    expect(press({ key: 'ArrowRight', metaKey: true })).toBeNull();
    expect(press({ key: 'f', ctrlKey: true })).toBeNull();
  });

  describe('held keys', () => {
    it('swallows a repeated Enter, so a focused button cannot click on every repeat', () => {
      expect(press({ key: 'Enter', repeat: true, target: 'interactive' })).toEqual({ kind: 'swallow' });
      expect(press({ key: 'Enter', repeat: true })).toEqual({ kind: 'swallow' });
    });

    it('never repeats a decision or an undo', () => {
      expect(press({ key: 'ArrowRight', repeat: true })).toEqual({ kind: 'swallow' });
      expect(press({ key: 'f', repeat: true })).toEqual({ kind: 'swallow' });
      expect(press({ key: 'z', metaKey: true, repeat: true })).toEqual({ kind: 'swallow' });
    });

    it('leaves unrelated held keys alone', () => {
      expect(press({ key: 'ArrowDown', repeat: true })).toBeNull();
    });
  });
});
