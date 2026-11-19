import { buildCloudflareAccessQrPayload } from './cloudflare-access-qr-payload';

describe('js/helpers/cloudflare-access-qr-payload', () => {
  describe('buildCloudflareAccessQrPayload', () => {
    it('serializes the setup into the versioned payload', () => {
      const result = buildCloudflareAccessQrPayload({
        serverUrl: 'https://budget.example.com',
        clientId: 'abc.access',
        clientSecret: 's3cret',
      });

      expect(JSON.parse(result)).toEqual({
        v: 1,
        server: 'https://budget.example.com',
        cfClientId: 'abc.access',
        cfClientSecret: 's3cret',
      });
    });

    it('strips trailing slashes from the server url', () => {
      const result = buildCloudflareAccessQrPayload({
        serverUrl: 'https://budget.example.com//',
        clientId: 'abc.access',
        clientSecret: 's3cret',
      });

      expect(JSON.parse(result).server).toBe('https://budget.example.com');
    });
  });
});
