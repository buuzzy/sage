/**
 * Local-Only / Token Auth Middleware
 *
 * Three modes based on environment:
 *
 * 1. **Cloud mode — API Token** (SAGE_API_TOKEN is set):
 *    Validates `Authorization: Bearer <SAGE_API_TOKEN>` header.
 *    Used for server-to-server / internal calls on Railway.
 *
 * 2. **Cloud mode — Supabase JWT** (SAGE_API_TOKEN is set, token doesn't match):
 *    Falls back to validating the Bearer token as a Supabase JWT.
 *    Used by iOS / Web frontend clients that send their user JWT.
 *
 * 3. **Local mode** (SAGE_API_TOKEN is NOT set):
 *    Restricts access to loopback addresses (127.x.x.x / ::1).
 *    Used when sage-api runs as Tauri desktop sidecar.
 *
 * Applied to execution-capable routes:
 *   /agent, /sandbox, /preview, /files, /mcp, /skills
 *
 * NOT applied to channel/ingress routes (/v1, /channels/*) which
 * intentionally accept external network connections (WeChat, Feishu).
 * Those routes enforce their own HTCLAW_CHANNEL_API_KEY auth.
 */

import type { Context, Next } from 'hono';
import { getConnInfo } from '@hono/node-server/conninfo';
import { createClient } from '@supabase/supabase-js';

const API_TOKEN = process.env.SAGE_API_TOKEN;

// Supabase client for JWT verification (only needed in cloud mode)
const supabaseUrl = process.env.SUPABASE_URL || 'https://wymqgwtagpsjuonsclye.supabase.co';
const supabaseServiceKey = process.env.SUPABASE_SERVICE_ROLE_KEY || '';
const supabaseAdmin = supabaseServiceKey
  ? createClient(supabaseUrl, supabaseServiceKey, { auth: { persistSession: false, autoRefreshToken: false } })
  : null;

/**
 * Returns true if the address is a loopback (local) address.
 */
function isLoopback(addr: string | undefined): boolean {
  if (!addr) return false;
  // Strip IPv6-mapped IPv4 prefix and brackets
  const clean = addr.replace(/^::ffff:/i, '').replace(/^\[|\]$/g, '').trim();
  return (
    clean === '127.0.0.1' ||
    clean === '::1' ||
    clean === 'localhost' ||
    clean.startsWith('127.')
  );
}

/**
 * Middleware that guards sensitive routes.
 *
 * Cloud mode:  checks Authorization: Bearer <SAGE_API_TOKEN> first,
 *              then falls back to Supabase JWT verification.
 * Local mode:  checks source IP is loopback
 */
export async function localOnlyMiddleware(c: Context, next: Next): Promise<Response | void> {
  // ── Cloud mode: token-based auth ──────────────────────────────────────────
  if (API_TOKEN) {
    const authHeader = c.req.header('authorization');
    const token = authHeader?.startsWith('Bearer ')
      ? authHeader.slice(7)
      : undefined;

    // Priority 1: exact match with SAGE_API_TOKEN (server-to-server)
    if (token === API_TOKEN) {
      await next();
      return;
    }

    // Priority 2: validate as Supabase JWT (iOS / Web user clients)
    if (token && supabaseAdmin) {
      try {
        const { data, error } = await supabaseAdmin.auth.getUser(token);
        if (!error && data.user) {
          // Valid Supabase user — allow request
          await next();
          return;
        }
      } catch {
        // JWT verification failed — fall through to reject
      }
    }

    // Neither token matched
    return c.json({ error: 'Unauthorized' }, 401);
  }

  // ── Local mode: loopback check (desktop sidecar) ──────────────────────────
  let remoteAddr: string | undefined;

  try {
    const info = getConnInfo(c);
    remoteAddr = info.remote.address;
  } catch {
    // getConnInfo may throw in non-node environments; fall back to header heuristics
  }

  // Fallback: X-Forwarded-For is present only when behind a reverse proxy; in
  // direct node server mode it should be absent for local requests.
  if (!remoteAddr) {
    remoteAddr = c.req.header('x-real-ip') || c.req.header('x-forwarded-for')?.split(',')[0]?.trim();
  }

  if (!isLoopback(remoteAddr)) {
    console.warn(
      `[Security] Blocked non-local request to ${c.req.path} from ${remoteAddr ?? 'unknown'}`
    );
    return c.json(
      { error: 'Forbidden: this endpoint is only accessible from localhost' },
      403
    );
  }

  await next();
}
