/** What the iPhone app needs to pass a Cloudflare Access gate in front of the server. */
export interface CloudflareAccessDeviceSetup {
  serverUrl: string;
  clientId: string;
  clientSecret: string;
}
