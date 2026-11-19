import type { AppUpdatePlatform } from '@bt/shared/types';
import fsp from 'node:fs/promises';
import os from 'node:os';
import path from 'node:path';

export interface StoredBuild {
  build: number;
  version: string;
  bundleId: string;
  commit: string;
  notes: string;
  size: number;
  sha256: string;
  /** ISO 8601 */
  uploadedAt: string;
  /** File name inside the storage directory. */
  file: string;
}

interface BuildSlot {
  current: StoredBuild | null;
  previous: StoredBuild | null;
}

const STALE_PART_MS = 60 * 60 * 1000;

type Index = Partial<Record<AppUpdatePlatform, BuildSlot>>;

export const storageRoot = (): string => {
  if (process.env.APP_UPDATES_DIR) return path.resolve(process.env.APP_UPDATES_DIR);
  if (process.env.NODE_ENV === 'test') {
    return path.join(os.tmpdir(), `bt-app-updates-test-${process.env.JEST_WORKER_ID ?? '0'}`);
  }
  return path.join(process.cwd(), 'data', 'app-updates');
};

export const buildFileName = ({ platform, build }: { platform: AppUpdatePlatform; build: number }) =>
  `${platform}-${build}.ipa`;

export const buildFilePath = ({ file }: { file: string }) => path.join(storageRoot(), file);

const indexPath = () => path.join(storageRoot(), 'index.json');

const loadIndex = async (): Promise<Index> => {
  try {
    const data = JSON.parse(await fsp.readFile(indexPath(), 'utf8'));
    return data && typeof data === 'object' ? data : {};
  } catch (error) {
    // Only a missing index means no builds yet; any other failure must not look like an empty index, or prune would delete every build.
    if ((error as NodeJS.ErrnoException).code === 'ENOENT') return {};
    throw error;
  }
};

export const getSlot = async ({ platform }: { platform: AppUpdatePlatform }): Promise<BuildSlot> => {
  const slot = (await loadIndex())[platform];
  return { current: slot?.current ?? null, previous: slot?.previous ?? null };
};

/** The stored build with this number, if it is the current or the previous one. */
export const findStoredBuild = async ({
  platform,
  build,
}: {
  platform: AppUpdatePlatform;
  build: number;
}): Promise<StoredBuild | null> => {
  const { current, previous } = await getSlot({ platform });
  return [current, previous].find((rec) => rec?.build === build) ?? null;
};

// Index read-modify-write cycles run one at a time within this process.
let queue: Promise<unknown> = Promise.resolve();

/**
 * Runs `fn` with exclusive access to the platform's slot; whatever it returns
 * as `slot` is persisted and files no longer referenced by any slot are deleted.
 */
export const updateSlot = <T>({
  platform,
  fn,
}: {
  platform: AppUpdatePlatform;
  fn: (params: { slot: BuildSlot }) => Promise<{ slot: BuildSlot; result: T }>;
}): Promise<T> => {
  const run = queue.then(async () => {
    const index = await loadIndex();
    const existing = index[platform];
    const { slot, result } = await fn({
      slot: { current: existing?.current ?? null, previous: existing?.previous ?? null },
    });
    index[platform] = slot;
    await fsp.mkdir(storageRoot(), { recursive: true });
    const tmp = `${indexPath()}.tmp`;
    await fsp.writeFile(tmp, JSON.stringify(index, null, 2), 'utf8');
    await fsp.rename(tmp, indexPath());
    await prune({ index });
    return result;
  });
  queue = run.catch(() => undefined);
  return run;
};

const prune = async ({ index }: { index: Index }) => {
  const keep = new Set(
    Object.values(index).flatMap((slot) => [slot?.current?.file, slot?.previous?.file].filter(Boolean) as string[]),
  );
  const now = Date.now();
  for (const name of await fsp.readdir(storageRoot())) {
    const filePath = path.join(storageRoot(), name);
    if (name.endsWith('.ipa') && !keep.has(name)) await fsp.rm(filePath, { force: true });
    // Leftovers of interrupted uploads; the hour spares uploads still streaming.
    if (name.endsWith('.part')) {
      const stat = await fsp.stat(filePath).catch(() => null);
      if (stat && now - stat.mtimeMs > STALE_PART_MS) await fsp.rm(filePath, { force: true });
    }
  }
};
