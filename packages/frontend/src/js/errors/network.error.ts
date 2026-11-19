import { ApiBaseError } from '@/common/types';

// Chrome, Safari and Firefox each word the TypeError for a failed fetch differently.
export const FETCH_NETWORK_FAILURE_MESSAGES = [
  'Failed to fetch',
  'Load failed',
  'NetworkError when attempting to fetch resource',
];

export const isFetchNetworkFailure = ({ error }: { error: unknown }): boolean =>
  error instanceof TypeError && FETCH_NETWORK_FAILURE_MESSAGES.some((msg) => error.message.includes(msg));

/**
 * Network error.
 *
 * @class
 */
export class NetworkError extends Error {
  data;

  constructor(message: string, data?: ApiBaseError) {
    super(message);

    this.name = 'NetworkError';
    this.data = data;
  }
}
