import { OAUTH_PROVIDER } from '@bt/shared/types';
import { EnvVar, isEnvConfigured } from '@common/utils/env';

const PROVIDER_ENV_VARS: Record<OAUTH_PROVIDER, { clientId: EnvVar; clientSecret: EnvVar }> = {
  [OAUTH_PROVIDER.google]: { clientId: EnvVar.GOOGLE_CLIENT_ID, clientSecret: EnvVar.GOOGLE_CLIENT_SECRET },
  [OAUTH_PROVIDER.github]: { clientId: EnvVar.GITHUB_CLIENT_ID, clientSecret: EnvVar.GITHUB_CLIENT_SECRET },
};

/**
 * Credentials and enabled state for one social sign-in provider. Single source
 * for better-auth's `socialProviders` config and the native OAuth start check,
 * so both agree on whether a provider is usable.
 */
export function getOAuthProviderConfig({ provider }: { provider: OAUTH_PROVIDER }) {
  const envVars = PROVIDER_ENV_VARS[provider];
  const clientId = process.env[envVars.clientId];
  const clientSecret = process.env[envVars.clientSecret];

  return {
    clientId: clientId || '',
    clientSecret: clientSecret || '',
    enabled: isEnvConfigured(envVars.clientId, clientId) && isEnvConfigured(envVars.clientSecret, clientSecret),
  };
}
