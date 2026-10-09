import { OAUTH_PROVIDER } from '@bt/shared/types';
import { auth } from '@config/auth';
import { getOAuthProviderConfig } from '@config/oauth-providers';
import { t } from '@i18n/index';
import { UnexpectedError, ValidationError } from '@js/errors';
import { API_PREFIX, BETTER_AUTH_BASE_URL } from '@root/config';

import { signChallenge } from './native-oauth-challenge-cookie';

/** better-auth sends the browser here after the provider callback, on success and on error. */
const NATIVE_OAUTH_COMPLETE_URL = `${BETTER_AUTH_BASE_URL}${API_PREFIX}/auth/native/oauth/complete`;

const PROVIDER_DISPLAY_NAMES: Record<OAUTH_PROVIDER, string> = {
  [OAUTH_PROVIDER.google]: 'Google',
  [OAUTH_PROVIDER.github]: 'GitHub',
};

/**
 * Begins a provider sign-in for the native app. better-auth creates the OAuth
 * state (DB row plus signed `state` cookie) exactly as for a web sign-in; the
 * caller forwards those cookies, sets the signed challenge cookie, and redirects
 * the browser to the provider.
 */
export async function startNativeOAuth({
  provider,
  codeChallenge,
  headers,
}: {
  provider: OAUTH_PROVIDER;
  codeChallenge: string;
  headers: Headers;
}) {
  if (!getOAuthProviderConfig({ provider }).enabled) {
    throw new ValidationError({
      message: t({
        key: 'auth.nativeOAuth.providerNotConfigured',
        variables: { provider: PROVIDER_DISPLAY_NAMES[provider] },
      }),
    });
  }

  const { headers: authResponseHeaders, response } = await auth.api.signInSocial({
    body: {
      provider,
      callbackURL: NATIVE_OAUTH_COMPLETE_URL,
      errorCallbackURL: NATIVE_OAUTH_COMPLETE_URL,
      disableRedirect: true,
    },
    headers,
    returnHeaders: true,
  });

  if (!response.url) {
    throw new UnexpectedError({ message: `signInSocial returned no authorization URL for ${provider}` });
  }

  return {
    providerUrl: response.url,
    stateCookies: authResponseHeaders.getSetCookie(),
    signedChallenge: await signChallenge({ challenge: codeChallenge }),
  };
}
