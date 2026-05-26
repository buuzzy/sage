/**
 * Authenticated fetch wrapper.
 *
 * All API calls to the backend must use this instead of raw `fetch()`.
 * It automatically injects the Supabase JWT Bearer token for Railway auth.
 */

import { API_BASE_URL } from '@/config';
import { getCurrentAccessToken } from '@/shared/lib/supabase';

/**
 * Fetch with automatic Bearer token injection.
 * Accepts a path (relative to API_BASE_URL) or full URL.
 */
export async function apiFetch(
  path: string,
  init?: RequestInit
): Promise<Response> {
  const url = path.startsWith('http') ? path : `${API_BASE_URL}${path}`;

  const headers = new Headers(init?.headers);

  // Inject auth token if not already present
  if (!headers.has('Authorization')) {
    const token = await getCurrentAccessToken();
    if (token) {
      headers.set('Authorization', `Bearer ${token}`);
    }
  }

  // Default Content-Type for JSON
  if (!headers.has('Content-Type') && init?.body) {
    headers.set('Content-Type', 'application/json');
  }

  return fetch(url, { ...init, headers });
}
