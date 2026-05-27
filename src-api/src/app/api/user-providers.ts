/**
 * User Providers API Routes (Phase 1C)
 *
 * 云端化 provider 管理：CRUD + 设默认 + 服务端代测连通性
 * 所有端点需要 Bearer JWT 鉴权（auth.uid()）
 */

import { Hono } from 'hono';

import {
  listProviders,
  createProvider,
  updateProvider,
  deleteProvider,
  setDefaultProvider,
  getProviderWithKey,
  type CreateProviderInput,
  type UpdateProviderInput,
} from '@/shared/provider/user-store';

// ============================================================================
// Constants
// ============================================================================

const TEST_TIMEOUT_MS = 15000;

// ============================================================================
// Route Setup
// ============================================================================

const userProvidersRoutes = new Hono();

// ============================================================================
// Middleware: 提取 user_id from JWT
// ============================================================================

async function getUserId(c: any): Promise<string | null> {
  // 从 Authorization header 解析 JWT 获取 user_id
  // Railway 模式下，中间件已验证 token，user_id 在 c.get('userId') 或需要解 JWT
  const userId = c.get('userId') as string | undefined;
  if (userId) return userId;

  // fallback: 从 JWT payload 解析
  const authHeader = c.req.header('Authorization');
  if (!authHeader?.startsWith('Bearer ')) return null;

  const token = authHeader.slice(7);
  try {
    // 解析 JWT payload（不验签，验签由上游中间件完成）
    const payload = JSON.parse(
      Buffer.from(token.split('.')[1], 'base64').toString()
    );
    return payload.sub || null;
  } catch {
    return null;
  }
}

// ============================================================================
// GET /user-providers — 列出所有（不含明文 key）
// ============================================================================

userProvidersRoutes.get('/', async (c) => {
  const userId = await getUserId(c);
  if (!userId) return c.json({ error: 'Unauthorized' }, 401);

  try {
    const providers = await listProviders(userId);
    return c.json({ providers });
  } catch (error) {
    console.error('[UserProviders] list error:', error);
    return c.json({ error: 'Failed to list providers' }, 500);
  }
});

// ============================================================================
// POST /user-providers — 创建（apiKey 写 Vault）
// ============================================================================

userProvidersRoutes.post('/', async (c) => {
  const userId = await getUserId(c);
  if (!userId) return c.json({ error: 'Unauthorized' }, 401);

  try {
    const body = await c.req.json<CreateProviderInput>();

    // 基本校验
    if (!body.provider_kind || !body.display_name || !body.api_type || !body.base_url || !body.endpoint_path || !body.api_key) {
      return c.json({ error: 'Missing required fields: provider_kind, display_name, api_type, base_url, endpoint_path, api_key' }, 400);
    }

    if (!['anthropic-messages', 'openai-completions'].includes(body.api_type)) {
      return c.json({ error: 'api_type must be "anthropic-messages" or "openai-completions"' }, 400);
    }

    const provider = await createProvider(userId, body);
    return c.json({ provider }, 201);
  } catch (error) {
    console.error('[UserProviders] create error:', error);
    return c.json({ error: error instanceof Error ? error.message : 'Failed to create provider' }, 500);
  }
});

// ============================================================================
// PATCH /user-providers/:id — 字段级更新
// ============================================================================

userProvidersRoutes.patch('/:id', async (c) => {
  const userId = await getUserId(c);
  if (!userId) return c.json({ error: 'Unauthorized' }, 401);

  const providerId = c.req.param('id');

  try {
    const body = await c.req.json<UpdateProviderInput>();
    const provider = await updateProvider(userId, providerId, body);
    return c.json({ provider });
  } catch (error) {
    console.error('[UserProviders] update error:', error);
    return c.json({ error: error instanceof Error ? error.message : 'Failed to update provider' }, 500);
  }
});

// ============================================================================
// DELETE /user-providers/:id — 删除
// ============================================================================

userProvidersRoutes.delete('/:id', async (c) => {
  const userId = await getUserId(c);
  if (!userId) return c.json({ error: 'Unauthorized' }, 401);

  const providerId = c.req.param('id');

  try {
    await deleteProvider(userId, providerId);
    return c.json({ success: true });
  } catch (error) {
    console.error('[UserProviders] delete error:', error);
    return c.json({ error: error instanceof Error ? error.message : 'Failed to delete provider' }, 500);
  }
});

// ============================================================================
// POST /user-providers/:id/default — 设为默认
// ============================================================================

userProvidersRoutes.post('/:id/default', async (c) => {
  const userId = await getUserId(c);
  if (!userId) return c.json({ error: 'Unauthorized' }, 401);

  const providerId = c.req.param('id');

  try {
    await setDefaultProvider(userId, providerId);
    return c.json({ success: true });
  } catch (error) {
    console.error('[UserProviders] setDefault error:', error);
    return c.json({ error: error instanceof Error ? error.message : 'Failed to set default provider' }, 500);
  }
});

// ============================================================================
// POST /user-providers/:id/test — 服务端代测连通性
// ============================================================================

userProvidersRoutes.post('/:id/test', async (c) => {
  const userId = await getUserId(c);
  if (!userId) return c.json({ error: 'Unauthorized' }, 401);

  const providerId = c.req.param('id');

  try {
    const provider = await getProviderWithKey(userId, providerId);
    if (!provider) {
      return c.json({ error: 'Provider not found' }, 404);
    }

    if (!provider.api_key) {
      return c.json({ success: false, error: 'API Key not configured' });
    }

    // 构建测试请求
    const url = provider.base_url.replace(/\/$/, '') + provider.endpoint_path;
    const controller = new AbortController();
    const timeoutId = setTimeout(() => controller.abort(), TEST_TIMEOUT_MS);

    let response: Response;

    if (provider.api_type === 'anthropic-messages') {
      // Anthropic Messages 协议测试
      response = await fetch(url, {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          'x-api-key': provider.api_key,
          'anthropic-version': '2023-06-01',
        },
        body: JSON.stringify({
          model: provider.default_model || 'test',
          max_tokens: 1,
          messages: [{ role: 'user', content: 'hi' }],
        }),
        signal: controller.signal,
      });
    } else {
      // OpenAI Completions 协议测试
      response = await fetch(url, {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          'Authorization': `Bearer ${provider.api_key}`,
        },
        body: JSON.stringify({
          model: provider.default_model || 'test',
          max_tokens: 1,
          messages: [{ role: 'user', content: 'hi' }],
        }),
        signal: controller.signal,
      });
    }

    clearTimeout(timeoutId);

    if (response.ok || response.status === 200) {
      return c.json({ success: true, status: response.status });
    }

    // 非 2xx 但不是网络错误 — 可能是模型不存在等，但连通性 OK
    const body = await response.text().catch(() => '');
    if (response.status === 401 || response.status === 403) {
      return c.json({ success: false, error: 'Authentication failed (invalid API Key)', status: response.status });
    }

    // 4xx/5xx 但能连上 = 连通性 OK，可能是模型问题
    return c.json({ success: true, status: response.status, warning: `Server responded with ${response.status}` });
  } catch (error) {
    if (error instanceof Error && error.name === 'AbortError') {
      return c.json({ success: false, error: `Connection timeout (${TEST_TIMEOUT_MS / 1000}s)` });
    }
    return c.json({ success: false, error: error instanceof Error ? error.message : 'Connection failed' });
  }
});

export { userProvidersRoutes };
