/**
 * Decides the WebAuthn relying-party ID that passkeys are bound to.
 *
 * Browsers and iOS reject a passkey ceremony whose rpID is not the page's host
 * (or a parent domain of it), so the fallback is the hostname of AUTH_ORIGIN,
 * the URL the site is served from, rather than a fixed value.
 */
export function resolvePasskeyRpId({ rpId, authOrigin }: { rpId: string | undefined; authOrigin: string }): string {
  const configured = rpId?.trim();
  if (configured) return configured;

  try {
    return new URL(authOrigin).hostname;
  } catch {
    throw new Error('AUTH_ORIGIN must be a full URL such as https://budget.example.com (needed to derive AUTH_RP_ID)');
  }
}
