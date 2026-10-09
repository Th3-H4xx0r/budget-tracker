import { auth } from '@config/auth';
import { createHmac, timingSafeEqual } from 'node:crypto';

/**
 * Signs `value` as `<value>.<base64 HMAC-SHA256>` with better-auth's own secret –
 * the format better-call uses for signed cookies. A session token signed this way
 * is exactly what the bearer plugin returns in `set-auth-token` and accepts in
 * `Authorization: Bearer`.
 */
export async function signValue({ value }: { value: string }): Promise<string> {
  const { secret } = await auth.$context;
  return `${value}.${createHmac('sha256', secret).update(value).digest('base64')}`;
}

/** Returns the original value when the signature matches, otherwise null. */
export async function readSignedValue({ signedValue }: { signedValue: string }): Promise<string | null> {
  const separator = signedValue.lastIndexOf('.');
  if (separator < 1) return null;

  const value = signedValue.slice(0, separator);
  const expected = Buffer.from(await signValue({ value }));
  const received = Buffer.from(signedValue);

  return expected.length === received.length && timingSafeEqual(expected, received) ? value : null;
}
