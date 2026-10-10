import { buildMerchantKey, tokenSimilarity } from '../matching/merchant-key';
import type { ClusterOccurrence, DiscoveryTransaction, MerchantCluster } from './types';

const MERGE_MIN_SIMILARITY = 0.75;
const DUPLICATE_WINDOW_DAYS = 3;
const DAY_MS = 24 * 60 * 60 * 1000;
/** Clusters are compared only when they share a token or this long a prefix of one ("netflixcom" ~ "netflix"). */
const BLOCKING_PREFIX_LENGTH = 4;
const MAX_BLOCK_SIZE = 200;

export interface PayeeIdentity {
  name: string;
  /** Raw alias names the payee namespace resolves to this payee. */
  aliases: string[];
}

interface WorkingCluster {
  merchantKey: string;
  payeeId: string | null;
  payeeName: string | null;
  /** Name and alias token sets (payee clusters) or the descriptor token sets (note clusters). */
  tokenSets: string[][];
  transactions: DiscoveryTransaction[];
}

const payeeKey = ({ payeeId }: { payeeId: string }) => `payee:${payeeId}`;

function collapseDuplicates({ transactions }: { transactions: DiscoveryTransaction[] }): ClusterOccurrence[] {
  const sorted = transactions.toSorted((a, b) => a.time.getTime() - b.time.getTime());
  const occurrences: ClusterOccurrence[] = [];

  for (const tx of sorted) {
    const last = occurrences[occurrences.length - 1];
    if (last && tx.time.getTime() - last.time.getTime() <= DUPLICATE_WINDOW_DAYS * DAY_MS) {
      last.amountCents = Math.max(last.amountCents, tx.amountCents);
      last.transactionIds.push(tx.id);
      continue;
    }
    occurrences.push({ time: tx.time, amountCents: tx.amountCents, transactionIds: [tx.id] });
  }

  return occurrences;
}

function mostFrequent({ values }: { values: string[] }): string {
  const counts = new Map<string, number>();
  let best = values[0]!;
  for (const value of values) {
    const count = (counts.get(value) ?? 0) + 1;
    counts.set(value, count);
    if (count > (counts.get(best) ?? 0)) best = value;
  }
  return best;
}

function clusterSimilarity({ a, b }: { a: WorkingCluster; b: WorkingCluster }): number {
  let best = 0;
  for (const tokensA of a.tokenSets) {
    for (const tokensB of b.tokenSets) {
      best = Math.max(best, tokenSimilarity({ a: tokensA, b: tokensB }));
      if (best >= 1) return best;
    }
  }
  return best;
}

function blockingKeys({ cluster }: { cluster: WorkingCluster }): Set<string> {
  const keys = new Set<string>();
  for (const tokens of cluster.tokenSets) {
    for (const token of tokens) {
      keys.add(`t:${token}`);
      if (token.length >= BLOCKING_PREFIX_LENGTH) keys.add(`p:${token.slice(0, BLOCKING_PREFIX_LENGTH)}`);
    }
  }
  return keys;
}

/** Merges similar clusters of one (transactionType, currencyCode) partition. Two payees never merge. */
function mergeSimilar({ clusters }: { clusters: WorkingCluster[] }): WorkingCluster[] {
  const parent = clusters.map((_, index) => index);
  const find = (index: number): number => {
    while (parent[index] !== index) {
      parent[index] = parent[parent[index]!]!;
      index = parent[index]!;
    }
    return index;
  };

  const byBlockingKey = new Map<string, number[]>();
  clusters.forEach((cluster, index) => {
    for (const key of blockingKeys({ cluster })) {
      const indexes = byBlockingKey.get(key) ?? [];
      indexes.push(index);
      byBlockingKey.set(key, indexes);
    }
  });

  const compared = new Set<string>();
  for (const indexes of byBlockingKey.values()) {
    // A token shared by hundreds of merchants ("store") carries no identity and would make this quadratic.
    if (indexes.length > MAX_BLOCK_SIZE) continue;
    for (let i = 0; i < indexes.length; i++) {
      for (let j = i + 1; j < indexes.length; j++) {
        const [a, b] = [indexes[i]!, indexes[j]!];
        const pairKey = `${a}:${b}`;
        if (compared.has(pairKey)) continue;
        compared.add(pairKey);

        const rootA = find(a);
        const rootB = find(b);
        if (rootA === rootB) continue;
        if (clusters[rootA]!.payeeId && clusters[rootB]!.payeeId) continue;
        if (clusterSimilarity({ a: clusters[a]!, b: clusters[b]! }) < MERGE_MIN_SIMILARITY) continue;

        // The payee-keyed side gives the merged cluster its identity.
        if (clusters[rootB]!.payeeId) parent[rootA] = rootB;
        else parent[rootB] = rootA;
      }
    }
  }

  const merged = new Map<number, WorkingCluster>();
  clusters.forEach((cluster, index) => {
    const root = find(index);
    const target = merged.get(root);
    if (!target) {
      merged.set(root, { ...clusters[root]!, tokenSets: [...clusters[root]!.tokenSets], transactions: [] });
    }
    const into = merged.get(root)!;
    into.transactions.push(...cluster.transactions);
    if (index !== root) into.tokenSets.push(...cluster.tokenSets);
  });

  return [...merged.values()];
}

/**
 * Groups transactions into merchant clusters. A transaction with a payee is keyed `payee:<payeeId>`;
 * otherwise its note's merchant key is used. Clusters whose token sets (including payee aliases) are
 * at least 0.75 similar merge. Clusters split by transaction type and currency but not by account,
 * and charges within 3 days of each other collapse into one occurrence (the larger amount wins).
 */
export function clusterMerchants({
  transactions,
  payees,
}: {
  transactions: DiscoveryTransaction[];
  payees: Map<string, PayeeIdentity>;
}): MerchantCluster[] {
  const partitions = new Map<string, Map<string, WorkingCluster>>();

  for (const tx of transactions) {
    const payee = tx.payeeId ? payees.get(tx.payeeId) : undefined;
    let key: string;
    let tokenSets: string[][];

    if (tx.payeeId && payee) {
      key = payeeKey({ payeeId: tx.payeeId });
      tokenSets = [payee.name, ...payee.aliases]
        .map((raw) => buildMerchantKey({ raw }).tokens)
        .filter((tokens) => tokens.length > 0);
    } else {
      const merchant = buildMerchantKey({ raw: tx.note });
      if (!merchant.key) continue;
      key = merchant.key;
      tokenSets = [merchant.tokens];
    }

    const partitionKey = `${tx.transactionType}|${tx.currencyCode}`;
    const partition = partitions.get(partitionKey) ?? new Map<string, WorkingCluster>();
    partitions.set(partitionKey, partition);

    const existing = partition.get(key);
    if (existing) {
      existing.transactions.push(tx);
      continue;
    }
    partition.set(key, {
      merchantKey: key,
      payeeId: payee ? tx.payeeId : null,
      payeeName: payee?.name ?? null,
      tokenSets,
      transactions: [tx],
    });
  }

  const result: MerchantCluster[] = [];
  for (const partition of partitions.values()) {
    for (const cluster of mergeSimilar({ clusters: [...partition.values()] })) {
      const first = cluster.transactions[0]!;
      const accountIds = cluster.transactions.map((tx) => tx.accountId);
      result.push({
        merchantKey: cluster.merchantKey,
        tokens: [...new Set(cluster.tokenSets.flat())],
        payeeId: cluster.payeeId,
        payeeName: cluster.payeeName,
        transactionType: first.transactionType,
        currencyCode: first.currencyCode,
        accountId: mostFrequent({ values: accountIds }),
        accountIds: [...new Set(accountIds)],
        transactions: cluster.transactions.toSorted((a, b) => a.time.getTime() - b.time.getTime()),
        occurrences: collapseDuplicates({ transactions: cluster.transactions }),
      });
    }
  }

  return result;
}
