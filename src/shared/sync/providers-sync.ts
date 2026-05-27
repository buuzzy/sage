/**
 * Providers Sync — 云端 user_providers CRUD 客户端层
 *
 * 数据源：user_providers 表（通过 /user-providers REST API）
 *
 * 职责：
 *   • 拉取用户所有 provider 配置（不含明文 key）
 *   • 创建 / 更新 / 删除 provider
 *   • 设置默认 provider
 *   • 服务端代测连通性
 *
 * 与旧 settings.providers[] 的关系：
 *   • 本模块完全替代 settings.providers[] 作为数据源
 *   • settings.ts 中的 defaultProviders 常量仅作为"添加 provider"时的模板
 */

import { API_BASE_URL } from '@/config';
import { supabase } from '@/shared/lib/supabase';

// ============================================================================
// Types
// ============================================================================

export interface CloudProvider {
  id: string;
  user_id: string;
  provider_kind: string;
  display_name: string;
  api_type: 'anthropic-messages' | 'openai-completions';
  base_url: string;
  endpoint_path: string;
  models: string[];
  default_model: string | null;
  enabled: boolean;
  is_default: boolean;
  sort_order: number;
  created_at: string;
  updated_at: string;
}

export interface CreateProviderPayload {
  provider_kind: string;
  display_name: string;
  api_type: 'anthropic-messages' | 'openai-completions';
  base_url: string;
  endpoint_path: string;
  models?: string[];
  default_model?: string;
  api_key: string;
  enabled?: boolean;
  is_default?: boolean;
  sort_order?: number;
}

export interface UpdateProviderPayload {
  display_name?: string;
  api_type?: 'anthropic-messages' | 'openai-completions';
  base_url?: string;
  endpoint_path?: string;
  models?: string[];
  default_model?: string | null;
  api_key?: string;
  enabled?: boolean;
  is_default?: boolean;
  sort_order?: number;
}

export interface TestResult {
  success: boolean;
  status?: number;
  error?: string;
  warning?: string;
}

// ============================================================================
// Auth Helper
// ============================================================================

async function getAuthHeaders(): Promise<Record<string, string>> {
  const { data: { session } } = await supabase.auth.getSession();
  if (!session?.access_token) {
    throw new Error('Not authenticated');
  }
  return {
    'Content-Type': 'application/json',
    'Authorization': `Bearer ${session.access_token}`,
  };
}

// ============================================================================
// API Functions
// ============================================================================

/**
 * 列出当前用户所有 provider（不含明文 key）
 */
export async function fetchProviders(): Promise<CloudProvider[]> {
  const headers = await getAuthHeaders();
  const res = await fetch(`${API_BASE_URL}/user-providers`, { headers });

  if (!res.ok) {
    throw new Error(`Failed to fetch providers: ${res.status}`);
  }

  const data = await res.json() as { providers: CloudProvider[] };
  return data.providers;
}

/**
 * 创建 provider
 */
export async function createCloudProvider(payload: CreateProviderPayload): Promise<CloudProvider> {
  const headers = await getAuthHeaders();
  const res = await fetch(`${API_BASE_URL}/user-providers`, {
    method: 'POST',
    headers,
    body: JSON.stringify(payload),
  });

  if (!res.ok) {
    const err = await res.json().catch(() => ({})) as { error?: string };
    throw new Error(err.error || `Failed to create provider: ${res.status}`);
  }

  const data = await res.json() as { provider: CloudProvider };
  return data.provider;
}

/**
 * 更新 provider（字段级 PATCH）
 */
export async function updateCloudProvider(
  id: string,
  payload: UpdateProviderPayload
): Promise<CloudProvider> {
  const headers = await getAuthHeaders();
  const res = await fetch(`${API_BASE_URL}/user-providers/${id}`, {
    method: 'PATCH',
    headers,
    body: JSON.stringify(payload),
  });

  if (!res.ok) {
    const err = await res.json().catch(() => ({})) as { error?: string };
    throw new Error(err.error || `Failed to update provider: ${res.status}`);
  }

  const data = await res.json() as { provider: CloudProvider };
  return data.provider;
}

/**
 * 删除 provider
 */
export async function deleteCloudProvider(id: string): Promise<void> {
  const headers = await getAuthHeaders();
  const res = await fetch(`${API_BASE_URL}/user-providers/${id}`, {
    method: 'DELETE',
    headers,
  });

  if (!res.ok) {
    const err = await res.json().catch(() => ({})) as { error?: string };
    throw new Error(err.error || `Failed to delete provider: ${res.status}`);
  }
}

/**
 * 设为默认 provider
 */
export async function setDefaultCloudProvider(id: string): Promise<void> {
  const headers = await getAuthHeaders();
  const res = await fetch(`${API_BASE_URL}/user-providers/${id}/default`, {
    method: 'POST',
    headers,
  });

  if (!res.ok) {
    const err = await res.json().catch(() => ({})) as { error?: string };
    throw new Error(err.error || `Failed to set default: ${res.status}`);
  }
}

/**
 * 服务端代测连通性
 */
export async function testCloudProvider(id: string): Promise<TestResult> {
  const headers = await getAuthHeaders();
  const res = await fetch(`${API_BASE_URL}/user-providers/${id}/test`, {
    method: 'POST',
    headers,
  });

  if (!res.ok) {
    return { success: false, error: `Server error: ${res.status}` };
  }

  return await res.json() as TestResult;
}

// ============================================================================
// Built-in Provider Templates (for "Add Provider" UI)
// ============================================================================

export interface ProviderTemplate {
  kind: string;
  name: string;
  api_type: 'anthropic-messages' | 'openai-completions';
  base_url: string;
  endpoint_path: string;
  models: string[];
  default_model: string;
  icon: string;
  api_key_url: string;
}

export const BUILTIN_PROVIDER_TEMPLATES: ProviderTemplate[] = [
  {
    kind: 'deepseek',
    name: 'DeepSeek',
    api_type: 'anthropic-messages',
    base_url: 'https://api.deepseek.com',
    endpoint_path: '/anthropic/v1/messages',
    models: ['deepseek-v4-flash', 'deepseek-v4-pro'],
    default_model: 'deepseek-v4-flash',
    icon: 'D',
    api_key_url: 'https://platform.deepseek.com/api_keys',
  },
  {
    kind: 'minimax',
    name: 'MiniMax',
    api_type: 'anthropic-messages',
    base_url: 'https://api.minimaxi.com',
    endpoint_path: '/anthropic/v1/messages',
    models: ['MiniMax-M2', 'MiniMax-M2.5', 'MiniMax-M2.7'],
    default_model: 'MiniMax-M2.7',
    icon: 'M',
    api_key_url: 'https://platform.minimax.io/subscribe/coding-plan?code=9hgHKlPO3G&source=link',
  },
  {
    kind: 'zhipu',
    name: '智谱 BigModel',
    api_type: 'anthropic-messages',
    base_url: 'https://open.bigmodel.cn',
    endpoint_path: '/api/anthropic/v1/messages',
    models: ['glm-5.1', 'glm-5-turbo', 'glm-4.7'],
    default_model: 'glm-5.1',
    icon: 'Z',
    api_key_url: 'https://bigmodel.cn/usercenter/apikeys',
  },
  {
    kind: 'volcengine',
    name: '火山方舟',
    api_type: 'anthropic-messages',
    base_url: 'https://ark.cn-beijing.volces.com',
    endpoint_path: '/api/coding/v1/messages',
    models: ['ark-code-latest'],
    default_model: 'ark-code-latest',
    icon: 'V',
    api_key_url: 'https://volcengine.com/L/Sq5rSgyFu_E',
  },
  {
    kind: 'siliconflow',
    name: 'SiliconFlow',
    api_type: 'openai-completions',
    base_url: 'https://api.siliconflow.cn',
    endpoint_path: '/v1/chat/completions',
    models: ['MiniMaxAI/MiniMax-M2.1', 'zai-org/GLM-4.7'],
    default_model: 'zai-org/GLM-4.7',
    icon: 'S',
    api_key_url: 'https://cloud.siliconflow.com/me/account/ak',
  },
  {
    kind: 'kimi',
    name: 'Kimi (Moonshot)',
    api_type: 'openai-completions',
    base_url: 'https://api.moonshot.cn',
    endpoint_path: '/v1/chat/completions',
    models: ['kimi-k2.6', 'moonshot-v1-32k', 'moonshot-v1-128k'],
    default_model: 'kimi-k2.6',
    icon: 'K',
    api_key_url: 'https://platform.moonshot.cn/console/api-keys',
  },
  {
    kind: 'qwen',
    name: '通义千问',
    api_type: 'openai-completions',
    base_url: 'https://dashscope.aliyuncs.com',
    endpoint_path: '/compatible-mode/v1/chat/completions',
    models: ['qwen3.6-plus', 'qwen-plus', 'qwen-turbo'],
    default_model: 'qwen3.6-plus',
    icon: 'Q',
    api_key_url: 'https://dashscope.console.aliyun.com/apiKey',
  },
];
