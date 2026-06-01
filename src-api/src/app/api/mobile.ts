import { Hono } from 'hono';
import type { Context } from 'hono';

import { createUserScopedSupabase } from '@/shared/supabase/client';
import {
  confirmIdeaNote,
  createIdeaNote,
  listMobileActions,
} from '@/shared/services/mobile-actions';
import { getMobileDashboard } from '@/shared/services/mobile-dashboard';

export const mobileRoutes = new Hono();

/**
 * 用户态上下文：从 localOnlyMiddleware 注入的 userId + Bearer JWT 派生出
 * user-scoped supabase client（RLS 强制 auth.uid()=user_id）。
 * 共享 SAGE_API_TOKEN（server-to-server）无用户身份，访问这些接口返回 401。
 */
function userContext(c: Context): { userId: string; accessToken: string } | null {
  const userId = c.get('userId');
  const authHeader = c.req.header('authorization');
  const accessToken = authHeader?.startsWith('Bearer ') ? authHeader.slice(7) : '';
  if (!userId || !accessToken) return null;
  return { userId, accessToken };
}

mobileRoutes.get('/dashboard', async (c) => {
  const dashboard = await getMobileDashboard();
  return c.json({ ok: true, dashboard });
});

mobileRoutes.get('/actions', async (c) => {
  const ctx = userContext(c);
  if (!ctx) return c.json({ ok: false, error: 'User authentication required' }, 401);

  const db = createUserScopedSupabase(ctx.accessToken);
  const actions = await listMobileActions(db, ctx.userId);
  return c.json({ ok: true, actions });
});

mobileRoutes.post('/notes', async (c) => {
  const ctx = userContext(c);
  if (!ctx) return c.json({ ok: false, error: 'User authentication required' }, 401);

  const body = await c.req
    .json<Partial<{ transcript: string; symbol: string; intent: string }>>()
    .catch(() => ({}));

  const db = createUserScopedSupabase(ctx.accessToken);
  const result = await createIdeaNote(db, ctx.userId, body);
  return c.json({ ok: true, ...result }, 201);
});

mobileRoutes.post('/notes/:id/confirm', async (c) => {
  const ctx = userContext(c);
  if (!ctx) return c.json({ ok: false, error: 'User authentication required' }, 401);

  const id = c.req.param('id');
  const db = createUserScopedSupabase(ctx.accessToken);
  const result = await confirmIdeaNote(db, ctx.userId, id);
  if (!result) {
    return c.json({ ok: false, error: 'note not found' }, 404);
  }
  return c.json({ ok: true, ...result });
});
