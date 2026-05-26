/**
 * Global fetch interceptor for API authentication.
 *
 * Patches window.fetch to automatically inject Bearer token for all
 * requests to the Railway backend. This ensures all API calls (settings,
 * skills, MCP, cron, providers, etc.) are authenticated without needing
 * to modify each individual fetch call.
 *
 * Must be called once at app startup (before any API requests).
 */

import { API_BASE_URL } from '@/config';
import { getCurrentAccessToken } from '@/shared/lib/supabase';

let installed = false;

export function installFetchInterceptor(): void {
  if (installed) return;
  installed = true;

  const originalFetch = window.fetch;

  window.fetch = async function (
    input: RequestInfo | URL,
    init?: RequestInit
  ): Promise<Response> {
    const url =
      typeof input === 'string'
        ? input
        : input instanceof URL
          ? input.href
          : input instanceof Request
            ? input.url
            : '';

    // Only intercept requests to our backend
    if (url.startsWith(API_BASE_URL)) {
      const headers = new Headers(init?.headers);

      // Inject auth token if not already present
      if (!headers.has('Authorization')) {
        const token = await getCurrentAccessToken();
        if (token) {
          headers.set('Authorization', `Bearer ${token}`);
        }
      }

      return originalFetch.call(window, input, { ...init, headers });
    }

    // Pass through all other requests unchanged
    return originalFetch.call(window, input, init);
  };
}
