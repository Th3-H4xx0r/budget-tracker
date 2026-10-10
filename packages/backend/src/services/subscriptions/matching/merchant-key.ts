import { normalizePayeeName } from '@services/payees/normalize-name';
import Fuse, { type IFuseOptions } from 'fuse.js';

/**
 * Card-network, terminal and legal-form words that bank descriptors wrap around the merchant name.
 * `migrations/20261010000000-smart-recurring-matching.ts` holds a frozen copy for its backfill.
 */
const MERCHANT_NOISE_TOKENS: ReadonlySet<string> = new Set([
  'pos',
  'purchase',
  'card',
  'visa',
  'mastercard',
  'mc',
  'debit',
  'credit',
  'payment',
  'pmt',
  'recurring',
  'rec',
  'txn',
  'ref',
  'online',
  'www',
  'com',
  'net',
  'org',
  'inc',
  'ltd',
  'llc',
  'gmbh',
  'sa',
  'bv',
]);

const KEY_TOKEN_COUNT = 3;
const FUZZY_THRESHOLD = 0.4;
const FUZZY_MIN_PATTERN_LENGTH = 4;
/** Fuse's bitap search only handles patterns up to 32 characters. */
const FUZZY_MAX_PATTERN_LENGTH = 32;

interface MerchantKey {
  /** First three surviving tokens joined by a space; '' when nothing survives. */
  key: string;
  /** All surviving tokens, deduplicated, in descriptor order. */
  tokens: string[];
}

const countDigits = (token: string): number => token.replace(/\D/g, '').length;

/** Store numbers, terminal ids, card tails and reference codes ("8822", "p1234", "a4b2c9"). */
const isNoiseToken = (token: string): boolean => {
  if (token.length < 2) return true;
  if (MERCHANT_NOISE_TOKENS.has(token)) return true;
  const digits = countDigits(token);
  if (digits >= 4) return true;
  const hasNonDigit = digits < token.length;
  return hasNonDigit && digits >= 3;
};

/**
 * Canonical merchant identity of a bank descriptor, payee name or subscription name, so that
 * `NETFLIX.COM 8822 AMSTERDAM` and `Netflix.com 1931 Los Gatos` share the tokens `netflix`.
 */
export function buildMerchantKey({ raw }: { raw: string | null | undefined }): MerchantKey {
  if (!raw) return { key: '', tokens: [] };

  const tokens = [
    ...new Set(
      normalizePayeeName({ raw })
        .split(' ')
        .filter((token) => token && !isNoiseToken(token)),
    ),
  ];

  return { key: tokens.slice(0, KEY_TOKEN_COUNT).join(' '), tokens };
}

type TokenInput = MerchantKey | string[];

const toTokens = (input: TokenInput): string[] => (Array.isArray(input) ? input : input.tokens);

const FUSE_OPTIONS: IFuseOptions<string> = {
  threshold: FUZZY_THRESHOLD,
  includeScore: true,
  isCaseSensitive: false,
  ignoreLocation: true,
  minMatchCharLength: 3,
};

/** 1 − Fuse score of the shorter joined token string searched inside the longer one; 0 when no hit. */
const fuzzySimilarity = ({ a, b }: { a: string[]; b: string[] }): number => {
  const [pattern, text] = [a.join(' '), b.join(' ')].sort((x, y) => x.length - y.length) as [string, string];
  if (pattern.length < FUZZY_MIN_PATTERN_LENGTH || pattern.length > FUZZY_MAX_PATTERN_LENGTH) return 0;

  const [hit] = new Fuse([text], FUSE_OPTIONS).search(pattern);
  return hit?.score === undefined ? 0 : 1 - hit.score;
};

/**
 * Similarity in [0, 1] of two merchant token sets: max(Jaccard, containment), where containment is
 * |A∩B| / min(|A|,|B|) so a short subscription name fully inside a long descriptor scores 1.
 * Token overlap misses typos and concatenations ("netflixcom"), so a Fuse score (1 − score) is the
 * fallback when overlap alone stays below 1.
 */
export function tokenSimilarity({ a, b }: { a: TokenInput; b: TokenInput }): number {
  const tokensA = toTokens(a);
  const tokensB = toTokens(b);
  if (tokensA.length === 0 || tokensB.length === 0) return 0;

  const setA = new Set(tokensA);
  const setB = new Set(tokensB);
  let intersection = 0;
  for (const token of setA) {
    if (setB.has(token)) intersection += 1;
  }

  const union = setA.size + setB.size - intersection;
  const jaccard = intersection / union;
  const containment = intersection / Math.min(setA.size, setB.size);
  const overlap = Math.max(jaccard, containment);
  if (overlap >= 1) return 1;

  return Math.max(overlap, fuzzySimilarity({ a: [...setA], b: [...setB] }));
}
