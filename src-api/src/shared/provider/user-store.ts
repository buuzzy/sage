/**
 * User Provider Store
 *
 * CRUD 操作 + Vault KMS 加解密，操作 user_providers 表。
 * 仅在 Railway 服务端使用（需要 service_role 访问 vault.decrypted_secrets）。
 */

import { getServiceSupabase } from '@/shared/supabase/client';

// ============================================================================
// Types
// ============================================================================

export interface UserProvider {
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
  // api_key_secret_id 不暴露给客户端
}

export interface UserProviderWithKey extends UserProvider {
  /** 明文 API Key（仅后端内部使用，从 Vault 解密） */
  api_key: string;
}

export interface CreateProviderInput {
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

export interface UpdateProviderInput {
  display_name?: string;
  api_type?: 'anthropic-messages' | 'openai-completions';
  base_url?: string;
  endpoint_path?: string;
  models?: string[];
  default_model?: string | null;
  api_key?: string; // 如果提供，替换 Vault 中的旧 secret
  enabled?: boolean;
  is_default?: boolean;
  sort_order?: number;
}

// ============================================================================
// Vault Helpers
// ============================================================================

/**
 * 将 API Key 存入 Vault，返回 secret_id
 */
async function vaultStoreSecret(
  userId: string,
  providerKind: string,
  apiKey: string
): Promise<string> {
  const sb = getServiceSupabase();
  const name = `user_provider_${userId}_${providerKind}_${Date.now()}`;

  const { data, error } = await sb.rpc('vault_insert_secret', {
    new_secret: apiKey,
    new_name: name,
    new_description: `API Key for user ${userId} provider ${providerKind}`,
  });

  if (error) {
    throw new Error(`[user-store] Failed to store secret in Vault: ${error.message}`);
  }

  return data as string;
}

/**
 * 从 Vault 解密获取明文 API Key
 */
async function vaultGetSecret(secretId: string): Promise<string | null> {
  const sb = getServiceSupabase();

  // 通过 vault.decrypted_secrets 视图获取明文
  const { data, error } = await sb
    .from('decrypted_secrets')
    .select('decrypted_secret')
    .eq('id', secretId)
    .single();

  if (error || !data) {
    console.warn(`[user-store] Failed to decrypt secret ${secretId}:`, error?.message);
    return null;
  }

  return data.decrypted_secret;
}

/**
 * 删除 Vault 中的 secret
 */
async function vaultDeleteSecret(secretId: string): Promise<void> {
  const sb = getServiceSupabase();

  const { error } = await sb.rpc('delete_vault_secret', {
    secret_id: secretId,
  });

  if (error) {
    console.warn(`[user-store] Failed to delete secret ${secretId}:`, error.message);
  }
}

// ============================================================================
// CRUD Operations
// ============================================================================

/**
 * 列出用户所有 provider（不含明文 key）
 */
export async function listProviders(userId: string): Promise<UserProvider[]> {
  const sb = getServiceSupabase();

  const { data, error } = await sb
    .from('user_providers')
    .select('id, user_id, provider_kind, display_name, api_type, base_url, endpoint_path, models, default_model, enabled, is_default, sort_order, created_at, updated_at')
    .eq('user_id', userId)
    .order('sort_order', { ascending: true });

  if (error) {
    throw new Error(`[user-store] listProviders failed: ${error.message}`);
  }

  return (data || []) as UserProvider[];
}

/**
 * 创建 provider（API Key 写入 Vault）
 */
export async function createProvider(
  userId: string,
  input: CreateProviderInput
): Promise<UserProvider> {
  const sb = getServiceSupabase();

  // 1. 存 API Key 到 Vault
  const secretId = await vaultStoreSecret(userId, input.provider_kind, input.api_key);

  // 2. 如果设为默认，先取消其他默认
  if (input.is_default) {
    await sb
      .from('user_providers')
      .update({ is_default: false })
      .eq('user_id', userId)
      .eq('is_default', true);
  }

  // 3. 插入 user_providers
  const { data, error } = await sb
    .from('user_providers')
    .insert({
      user_id: userId,
      provider_kind: input.provider_kind,
      display_name: input.display_name,
      api_type: input.api_type,
      base_url: input.base_url,
      endpoint_path: input.endpoint_path,
      models: input.models || [],
      default_model: input.default_model || null,
      api_key_secret_id: secretId,
      enabled: input.enabled ?? true,
      is_default: input.is_default ?? false,
      sort_order: input.sort_order ?? 0,
    })
    .select('id, user_id, provider_kind, display_name, api_type, base_url, endpoint_path, models, default_model, enabled, is_default, sort_order, created_at, updated_at')
    .single();

  if (error) {
    // 回滚 Vault secret
    await vaultDeleteSecret(secretId);
    throw new Error(`[user-store] createProvider failed: ${error.message}`);
  }

  return data as UserProvider;
}

/**
 * 更新 provider（字段级 PATCH）
 */
export async function updateProvider(
  userId: string,
  providerId: string,
  input: UpdateProviderInput
): Promise<UserProvider> {
  const sb = getServiceSupabase();

  // 构建 patch 对象（不含 api_key）
  const patch: Record<string, unknown> = {};
  if (input.display_name !== undefined) patch.display_name = input.display_name;
  if (input.api_type !== undefined) patch.api_type = input.api_type;
  if (input.base_url !== undefined) patch.base_url = input.base_url;
  if (input.endpoint_path !== undefined) patch.endpoint_path = input.endpoint_path;
  if (input.models !== undefined) patch.models = input.models;
  if (input.default_model !== undefined) patch.default_model = input.default_model;
  if (input.enabled !== undefined) patch.enabled = input.enabled;
  if (input.sort_order !== undefined) patch.sort_order = input.sort_order;

  // 处理 API Key 更新
  if (input.api_key !== undefined) {
    // 获取旧 secret_id
    const { data: existing } = await sb
      .from('user_providers')
      .select('api_key_secret_id')
      .eq('id', providerId)
      .eq('user_id', userId)
      .single();

    // 存新 key
    const newSecretId = await vaultStoreSecret(userId, 'update', input.api_key);
    patch.api_key_secret_id = newSecretId;

    // 删旧 key
    if (existing?.api_key_secret_id) {
      await vaultDeleteSecret(existing.api_key_secret_id);
    }
  }

  // 处理 is_default
  if (input.is_default === true) {
    await sb
      .from('user_providers')
      .update({ is_default: false })
      .eq('user_id', userId)
      .eq('is_default', true);
    patch.is_default = true;
  } else if (input.is_default === false) {
    patch.is_default = false;
  }

  // 执行更新
  const { data, error } = await sb
    .from('user_providers')
    .update(patch)
    .eq('id', providerId)
    .eq('user_id', userId)
    .select('id, user_id, provider_kind, display_name, api_type, base_url, endpoint_path, models, default_model, enabled, is_default, sort_order, created_at, updated_at')
    .single();

  if (error) {
    throw new Error(`[user-store] updateProvider failed: ${error.message}`);
  }

  return data as UserProvider;
}

/**
 * 删除 provider（同时删除 Vault secret）
 */
export async function deleteProvider(userId: string, providerId: string): Promise<void> {
  const sb = getServiceSupabase();

  // 获取 secret_id
  const { data: existing } = await sb
    .from('user_providers')
    .select('api_key_secret_id')
    .eq('id', providerId)
    .eq('user_id', userId)
    .single();

  // 删除记录
  const { error } = await sb
    .from('user_providers')
    .delete()
    .eq('id', providerId)
    .eq('user_id', userId);

  if (error) {
    throw new Error(`[user-store] deleteProvider failed: ${error.message}`);
  }

  // 删除 Vault secret
  if (existing?.api_key_secret_id) {
    await vaultDeleteSecret(existing.api_key_secret_id);
  }
}

/**
 * 设为默认 provider
 */
export async function setDefaultProvider(userId: string, providerId: string): Promise<void> {
  const sb = getServiceSupabase();

  // 取消所有默认
  await sb
    .from('user_providers')
    .update({ is_default: false })
    .eq('user_id', userId)
    .eq('is_default', true);

  // 设新默认
  const { error } = await sb
    .from('user_providers')
    .update({ is_default: true })
    .eq('id', providerId)
    .eq('user_id', userId);

  if (error) {
    throw new Error(`[user-store] setDefaultProvider failed: ${error.message}`);
  }
}

/**
 * 获取用户默认 provider（含明文 API Key，后端 Cron/Channel 用）
 */
export async function getDefaultProvider(userId: string): Promise<UserProviderWithKey | null> {
  const sb = getServiceSupabase();

  const { data, error } = await sb
    .from('user_providers')
    .select('*')
    .eq('user_id', userId)
    .eq('is_default', true)
    .eq('enabled', true)
    .single();

  if (error || !data) {
    // fallback: 取第一个 enabled 的
    const { data: fallback } = await sb
      .from('user_providers')
      .select('*')
      .eq('user_id', userId)
      .eq('enabled', true)
      .order('sort_order', { ascending: true })
      .limit(1)
      .single();

    if (!fallback) return null;

    const apiKey = fallback.api_key_secret_id
      ? await vaultGetSecret(fallback.api_key_secret_id)
      : null;

    return {
      ...fallback,
      api_key: apiKey || '',
    } as UserProviderWithKey;
  }

  // 解密 API Key
  const apiKey = data.api_key_secret_id
    ? await vaultGetSecret(data.api_key_secret_id)
    : null;

  return {
    ...data,
    api_key: apiKey || '',
  } as UserProviderWithKey;
}

/**
 * 获取指定 provider（含明文 API Key，后端内部用）
 */
export async function getProviderWithKey(
  userId: string,
  providerId: string
): Promise<UserProviderWithKey | null> {
  const sb = getServiceSupabase();

  const { data, error } = await sb
    .from('user_providers')
    .select('*')
    .eq('id', providerId)
    .eq('user_id', userId)
    .single();

  if (error || !data) return null;

  const apiKey = data.api_key_secret_id
    ? await vaultGetSecret(data.api_key_secret_id)
    : null;

  return {
    ...data,
    api_key: apiKey || '',
  } as UserProviderWithKey;
}
