/**
 * Mock implementation of better-auth/plugins for Jest tests.
 */

/**
 * Creates a JWT plugin for better-auth.
 * This is a simplified mock that provides the essential API shape.
 */
export function jwt() {
  return {
    id: 'jwt',
    init: () => ({}),
  };
}

/**
 * Creates a bearer plugin for better-auth. The mocked `betterAuth` looks it up by
 * id and emulates its behaviour: `set-auth-token` on sign-in, and session
 * resolution from `Authorization: Bearer <signed token>`.
 */
export function bearer(options?: { requireSignature?: boolean }) {
  return {
    id: 'bearer',
    options,
  };
}
