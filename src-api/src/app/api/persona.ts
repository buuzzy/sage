import { Hono } from 'hono';

import { createUserScopedSupabase } from '@/shared/supabase/client';

export const personaRoutes = new Hono();

/**
 * GET /persona/memory
 *
 * Returns the signed-in user's persona_memory row. The route intentionally
 * relies on the caller's Supabase JWT instead of a query userId, so RLS keeps
 * the response scoped to the current user.
 */
personaRoutes.get('/memory', async (c) => {
  const authHeader = c.req.header('authorization');
  const accessToken = authHeader?.startsWith('Bearer ')
    ? authHeader.slice(7)
    : '';

  if (!accessToken) {
    return c.json({ ok: false, error: 'Missing bearer token' }, 401);
  }

  try {
    const supabase = createUserScopedSupabase(accessToken);
    const { data, error } = await supabase
      .from('persona_memory')
      .select('*')
      .maybeSingle();

    if (error) {
      return c.json({ ok: false, error: error.message }, 500);
    }

    return c.json({ ok: true, row: data ?? null });
  } catch (err) {
    return c.json(
      {
        ok: false,
        error: err instanceof Error ? err.message : 'Failed to fetch persona',
      },
      500
    );
  }
});
