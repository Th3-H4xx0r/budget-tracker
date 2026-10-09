export const API_PREFIX = '/api/v1';
export const BETTER_AUTH_BASE_URL = (process.env.BETTER_AUTH_URL || 'https://localhost:8081').replace(/\/+$/, '');

export const MCP_BASE_URL = process.env.MCP_BASE_URL || BETTER_AUTH_BASE_URL;
/** The frontend's own origin; Stripe-hosted pages are sent back to it. */
const FRONTEND_BASE_URL = (process.env.AUTH_ORIGIN || 'https://localhost:8100').replace(/\/+$/, '');

/** Where Stripe-hosted checkout and portal send the buyer back; must match the frontend plan-billing route. */
export const PLAN_BILLING_URL = `${FRONTEND_BASE_URL}/settings/plan-billing`;

/**
 * URL scheme the native iOS app registers for its OAuth callback
 * (`<scheme>://auth-callback`). Read from config only, never from a request, so
 * a crafted sign-in link cannot send the one-time code to another app.
 */
export const NATIVE_APP_URL_SCHEME = (process.env.NATIVE_APP_URL_SCHEME || 'moneymatter').trim().toLowerCase();

// RFC 3986 scheme syntax. A malformed value would produce redirects the app never receives.
if (!/^[a-z][a-z0-9+.-]*$/.test(NATIVE_APP_URL_SCHEME)) {
  throw new Error(`NATIVE_APP_URL_SCHEME="${NATIVE_APP_URL_SCHEME}" is not a valid URL scheme.`);
}
