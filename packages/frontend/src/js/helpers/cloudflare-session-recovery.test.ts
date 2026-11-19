import {
  recoverFromExpiredCloudflareSession,
  resetCloudflareSessionRecoveryState,
} from './cloudflare-session-recovery';

const createStorage = (initial: Record<string, string> = {}) => {
  const data = { ...initial };
  return {
    getItem: (key: string) => data[key] ?? null,
    setItem: (key: string, value: string) => {
      data[key] = value;
    },
  };
};

const respondWith = ({ type }: { type: ResponseType }) => vi.fn().mockResolvedValue({ type } as Response);

describe('js/helpers/cloudflare-session-recovery', () => {
  const now = 1_000_000;

  beforeEach(() => {
    resetCloudflareSessionRecoveryState();
  });

  it('reloads when the probe is redirected', async () => {
    const fetchImpl = respondWith({ type: 'opaqueredirect' });
    const reload = vi.fn();
    const storage = createStorage();

    const result = await recoverFromExpiredCloudflareSession({ fetchImpl, storage, reload, now, isOnline: true });

    expect(result).toBe(true);
    expect(reload).toHaveBeenCalledTimes(1);
    expect(storage.getItem('cf-access-reload-at')).toBe(String(now));
    expect(fetchImpl).toHaveBeenCalledWith('/site.webmanifest', {
      redirect: 'manual',
      credentials: 'include',
      cache: 'no-store',
    });
  });

  it('does not reload when the probe is not a redirect', async () => {
    const reload = vi.fn();

    const result = await recoverFromExpiredCloudflareSession({
      fetchImpl: respondWith({ type: 'basic' }),
      storage: createStorage(),
      reload,
      now,
      isOnline: true,
    });

    expect(result).toBe(false);
    expect(reload).not.toHaveBeenCalled();
  });

  it('does not reload when offline', async () => {
    const fetchImpl = respondWith({ type: 'opaqueredirect' });
    const reload = vi.fn();

    const result = await recoverFromExpiredCloudflareSession({
      fetchImpl,
      storage: createStorage(),
      reload,
      now,
      isOnline: false,
    });

    expect(result).toBe(false);
    expect(fetchImpl).not.toHaveBeenCalled();
    expect(reload).not.toHaveBeenCalled();
  });

  it('does not reload twice within 60 s', async () => {
    const fetchImpl = respondWith({ type: 'opaqueredirect' });
    const reload = vi.fn();
    const storage = createStorage({ 'cf-access-reload-at': String(now - 59_999) });

    const result = await recoverFromExpiredCloudflareSession({ fetchImpl, storage, reload, now, isOnline: true });

    expect(result).toBe(false);
    expect(fetchImpl).not.toHaveBeenCalled();
    expect(reload).not.toHaveBeenCalled();
  });

  it('reloads again once 60 s have passed', async () => {
    const reload = vi.fn();
    const storage = createStorage({ 'cf-access-reload-at': String(now - 60_000) });

    const result = await recoverFromExpiredCloudflareSession({
      fetchImpl: respondWith({ type: 'opaqueredirect' }),
      storage,
      reload,
      now,
      isOnline: true,
    });

    expect(result).toBe(true);
    expect(reload).toHaveBeenCalledTimes(1);
  });

  it('shares one probe between concurrent calls', async () => {
    const fetchImpl = respondWith({ type: 'opaqueredirect' });
    const reload = vi.fn();
    const storage = createStorage();

    const results = await Promise.all([
      recoverFromExpiredCloudflareSession({ fetchImpl, storage, reload, now, isOnline: true }),
      recoverFromExpiredCloudflareSession({ fetchImpl, storage, reload, now, isOnline: true }),
    ]);

    expect(results).toEqual([true, true]);
    expect(fetchImpl).toHaveBeenCalledTimes(1);
    expect(reload).toHaveBeenCalledTimes(1);
  });

  it('does not probe again within 10 s', async () => {
    const fetchImpl = respondWith({ type: 'basic' });
    const options = { fetchImpl, storage: createStorage(), reload: vi.fn(), isOnline: true };

    await recoverFromExpiredCloudflareSession({ ...options, now });
    const within = await recoverFromExpiredCloudflareSession({ ...options, now: now + 9_999 });
    expect(within).toBe(false);
    expect(fetchImpl).toHaveBeenCalledTimes(1);

    await recoverFromExpiredCloudflareSession({ ...options, now: now + 10_000 });
    expect(fetchImpl).toHaveBeenCalledTimes(2);
  });

  it('returns false when the probe itself throws', async () => {
    const reload = vi.fn();

    const result = await recoverFromExpiredCloudflareSession({
      fetchImpl: vi.fn().mockRejectedValue(new TypeError('Failed to fetch')),
      storage: createStorage(),
      reload,
      now,
      isOnline: true,
    });

    expect(result).toBe(false);
    expect(reload).not.toHaveBeenCalled();
  });
});
