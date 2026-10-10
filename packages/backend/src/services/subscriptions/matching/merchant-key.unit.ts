import { describe, expect, it } from '@jest/globals';

import { buildMerchantKey, tokenSimilarity } from './merchant-key';

describe('buildMerchantKey', () => {
  it('strips store numbers, domains and city suffix noise into a shared merchant token', () => {
    const amsterdam = buildMerchantKey({ raw: 'NETFLIX.COM 8822 AMSTERDAM' });
    const losGatos = buildMerchantKey({ raw: 'NETFLIX.COM 1931 LOS GATOS' });

    expect(amsterdam).toEqual({ key: 'netflix amsterdam', tokens: ['netflix', 'amsterdam'] });
    expect(losGatos.key).toBe('netflix los gatos');
    expect(losGatos.tokens[0]).toBe('netflix');
  });

  it('drops card and terminal words, single characters and reference codes', () => {
    expect(buildMerchantKey({ raw: 'POS PURCHASE VISA DEBIT SPOTIFY P1234 X' })).toEqual({
      key: 'spotify',
      tokens: ['spotify'],
    });
  });

  it('keeps short numbers that are part of a brand name', () => {
    expect(buildMerchantKey({ raw: '24 Hour Fitness' }).tokens).toEqual(['24', 'hour', 'fitness']);
  });

  it('caps the key at three tokens but keeps every token', () => {
    const result = buildMerchantKey({ raw: 'Acme Cloud Storage Premium Plan' });

    expect(result.key).toBe('acme cloud storage');
    expect(result.tokens).toEqual(['acme', 'cloud', 'storage', 'premium', 'plan']);
  });

  it('deduplicates repeated tokens', () => {
    expect(buildMerchantKey({ raw: 'GYMCO GYMCO 4411' })).toEqual({ key: 'gymco', tokens: ['gymco'] });
  });

  it('returns an empty key for empty or all-noise input', () => {
    expect(buildMerchantKey({ raw: null })).toEqual({ key: '', tokens: [] });
    expect(buildMerchantKey({ raw: '' })).toEqual({ key: '', tokens: [] });
    expect(buildMerchantKey({ raw: 'POS 123456 CARD' })).toEqual({ key: '', tokens: [] });
  });
});

describe('tokenSimilarity', () => {
  it('is 1 when one token set is contained in the other', () => {
    expect(
      tokenSimilarity({
        a: buildMerchantKey({ raw: 'Netflix' }),
        b: buildMerchantKey({ raw: 'NETFLIX.COM 8822 AMSTERDAM' }),
      }),
    ).toBe(1);
  });

  it('is 0 for unrelated merchants', () => {
    expect(tokenSimilarity({ a: ['spotify'], b: ['gymco'] })).toBe(0);
  });

  it('is 0 when either side is empty', () => {
    expect(tokenSimilarity({ a: [], b: ['netflix'] })).toBe(0);
  });

  it('uses partial overlap for partially shared names', () => {
    const similarity = tokenSimilarity({ a: ['apple', 'music'], b: ['apple', 'tv', 'plus'] });

    expect(similarity).toBeGreaterThanOrEqual(0.5);
    expect(similarity).toBeLessThan(1);
  });

  it('falls back to fuzzy matching for concatenated descriptors', () => {
    expect(tokenSimilarity({ a: ['netflix'], b: ['netflixcom'] })).toBeGreaterThan(0.8);
  });

  it('falls back to fuzzy matching for typos', () => {
    expect(tokenSimilarity({ a: ['spotify'], b: ['spotfy'] })).toBeGreaterThan(0.6);
  });
});
