import { getCurrentAccessToken } from './supabase';

const isTauri =
  typeof window !== 'undefined' && '__TAURI_INTERNALS__' in window;

export async function getApiRequestHeaders(
  headers?: HeadersInit
): Promise<Headers> {
  const next = new Headers(headers);

  if (!isTauri && !next.has('Authorization')) {
    const supabaseToken = await getCurrentAccessToken();
    const fallbackToken = import.meta.env.VITE_RAILWAY_API_TOKEN;
    const token = supabaseToken || fallbackToken;

    if (token) {
      next.set('Authorization', `Bearer ${token}`);
    }
  }

  return next;
}

export async function apiFetch(
  input: RequestInfo | URL,
  init: RequestInit = {}
): Promise<Response> {
  return fetch(input, {
    ...init,
    headers: await getApiRequestHeaders(init.headers),
  });
}
