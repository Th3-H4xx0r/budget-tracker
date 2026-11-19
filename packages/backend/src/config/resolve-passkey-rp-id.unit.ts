import { describe, expect, it } from '@jest/globals';

import { resolvePasskeyRpId } from './resolve-passkey-rp-id';

describe('resolvePasskeyRpId', () => {
  it('uses AUTH_RP_ID when it is set', () => {
    expect(resolvePasskeyRpId({ rpId: 'example.com', authOrigin: 'https://budget.example.com' })).toBe('example.com');
  });

  it('falls back to the AUTH_ORIGIN hostname when AUTH_RP_ID is unset', () => {
    expect(resolvePasskeyRpId({ rpId: undefined, authOrigin: 'https://budget.example.com' })).toBe(
      'budget.example.com',
    );
  });

  it('treats an empty or whitespace AUTH_RP_ID as unset', () => {
    expect(resolvePasskeyRpId({ rpId: '', authOrigin: 'https://budget.example.com' })).toBe('budget.example.com');
    expect(resolvePasskeyRpId({ rpId: '   ', authOrigin: 'https://budget.example.com' })).toBe('budget.example.com');
  });

  it('drops the port and path from AUTH_ORIGIN', () => {
    expect(resolvePasskeyRpId({ rpId: undefined, authOrigin: 'https://localhost:8100' })).toBe('localhost');
    expect(resolvePasskeyRpId({ rpId: undefined, authOrigin: 'https://budget.example.com:8443/app' })).toBe(
      'budget.example.com',
    );
  });
});
