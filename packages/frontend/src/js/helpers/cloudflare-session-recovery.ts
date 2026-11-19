const RELOAD_AT_STORAGE_KEY = 'cf-access-reload-at';
const RELOAD_COOLDOWN_MS = 60_000;
const PROBE_INTERVAL_MS = 10_000;

let inFlightRecovery: Promise<boolean> | null = null;
let lastProbeAt: number | null = null;

/** Clears the module-level dedupe and throttle state; for tests. */
export function resetCloudflareSessionRecoveryState(): void {
  inFlightRecovery = null;
  lastProbeAt = null;
}

/**
 * Cloudflare Access answers an expired session with a cross-origin redirect to
 * its login page, which the browser reports to fetch() as a bare network
 * failure. A same-origin static asset probed with `redirect: 'manual'` shows
 * that redirect as an `opaqueredirect` response, so the page can be reloaded
 * and let Cloudflare render its login. Any other outcome (offline, backend
 * down, probe error) is left alone. Concurrent calls share one probe, probes
 * run at most once per 10 s, and reloads are rate-limited so a persistent
 * failure cannot loop.
 *
 * @returns whether a reload was triggered
 */
export function recoverFromExpiredCloudflareSession({
  fetchImpl = (input, init) => fetch(input, init),
  storage = window.sessionStorage,
  reload = () => window.location.reload(),
  now = Date.now(),
  isOnline = navigator.onLine,
}: {
  fetchImpl?: (input: string, init?: RequestInit) => Promise<Response>;
  storage?: Pick<Storage, 'getItem' | 'setItem'>;
  reload?: () => void;
  now?: number;
  isOnline?: boolean;
} = {}): Promise<boolean> {
  if (inFlightRecovery) return inFlightRecovery;

  if (!isOnline) return Promise.resolve(false);

  const lastReloadAt = Number(storage.getItem(RELOAD_AT_STORAGE_KEY));
  if (lastReloadAt && Math.abs(now - lastReloadAt) < RELOAD_COOLDOWN_MS) return Promise.resolve(false);

  if (lastProbeAt !== null && Math.abs(now - lastProbeAt) < PROBE_INTERVAL_MS) return Promise.resolve(false);
  lastProbeAt = now;

  inFlightRecovery = probeAndReload({ fetchImpl, storage, reload, now }).finally(() => {
    inFlightRecovery = null;
  });
  return inFlightRecovery;
}

async function probeAndReload({
  fetchImpl,
  storage,
  reload,
  now,
}: {
  fetchImpl: (input: string, init?: RequestInit) => Promise<Response>;
  storage: Pick<Storage, 'getItem' | 'setItem'>;
  reload: () => void;
  now: number;
}): Promise<boolean> {
  try {
    const response = await fetchImpl('/site.webmanifest', {
      redirect: 'manual',
      credentials: 'include',
      cache: 'no-store',
    });

    if (response.type !== 'opaqueredirect') return false;

    storage.setItem(RELOAD_AT_STORAGE_KEY, String(now));
    reload();
    return true;
  } catch {
    return false;
  }
}
