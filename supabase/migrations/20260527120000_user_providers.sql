-- Phase 1A: user_providers 表 + Vault 加密 + RLS
-- 模型配置云端化：每个用户独立管理自己的 LLM provider 配置
-- API Key 通过 Supabase Vault (pgsodium) 服务端 KMS 加密存储

-- 1. 启用 Vault 扩展（如果尚未启用）
CREATE EXTENSION IF NOT EXISTS pgsodium;
-- vault schema 由 Supabase 平台自动创建，无需手动 CREATE SCHEMA

-- 2. 创建 user_providers 表
CREATE TABLE public.user_providers (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id         UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  provider_kind   TEXT NOT NULL,   -- 'deepseek'|'minimax'|'zhipu'|'volcengine'|'siliconflow'|'kimi'|'qwen'|'custom'
  display_name    TEXT NOT NULL,   -- "DeepSeek" 或用户自定义别名（支持 emoji）
  api_type        TEXT NOT NULL CHECK (api_type IN ('anthropic-messages', 'openai-completions')),
  base_url        TEXT NOT NULL,   -- 主机根 URL，如 https://api.deepseek.com
  endpoint_path   TEXT NOT NULL,   -- 完整路径，如 /anthropic/v1/messages
  models          JSONB NOT NULL DEFAULT '[]'::jsonb,  -- string[] 可用模型列表
  default_model   TEXT,            -- 默认模型名
  api_key_secret_id UUID,          -- 引用 vault.secrets(id)，由 pgsodium 自动加密
  enabled         BOOLEAN NOT NULL DEFAULT TRUE,
  is_default      BOOLEAN NOT NULL DEFAULT FALSE,  -- 每用户只能有一个默认 provider
  sort_order      INT NOT NULL DEFAULT 0,
  created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at      TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- 3. 索引
CREATE INDEX idx_user_providers_user_id ON public.user_providers (user_id, sort_order);
-- 每用户最多一个 is_default=true 的 provider
CREATE UNIQUE INDEX uniq_user_default_provider ON public.user_providers (user_id) WHERE is_default = TRUE;

-- 4. 自动更新 updated_at 触发器（复用已有函数）
CREATE TRIGGER trg_user_providers_updated_at
  BEFORE UPDATE ON public.user_providers
  FOR EACH ROW EXECUTE FUNCTION public.handle_updated_at();

-- 5. RLS：用户只能访问自己的 provider 配置
ALTER TABLE public.user_providers ENABLE ROW LEVEL SECURITY;

CREATE POLICY "user_providers_owner_select"
  ON public.user_providers FOR SELECT
  USING (auth.uid() = user_id);

CREATE POLICY "user_providers_owner_insert"
  ON public.user_providers FOR INSERT
  WITH CHECK (auth.uid() = user_id);

CREATE POLICY "user_providers_owner_update"
  ON public.user_providers FOR UPDATE
  USING (auth.uid() = user_id)
  WITH CHECK (auth.uid() = user_id);

CREATE POLICY "user_providers_owner_delete"
  ON public.user_providers FOR DELETE
  USING (auth.uid() = user_id);

-- 6. service_role 绕过 RLS（后端 Cron/Channel 需要跨用户读取）
-- Supabase 的 service_role 默认绕过 RLS，无需额外 policy

-- 7. 注释
COMMENT ON TABLE public.user_providers IS '用户 LLM Provider 配置（云端唯一真相源）';
COMMENT ON COLUMN public.user_providers.api_key_secret_id IS '引用 vault.secrets(id)，明文 API Key 由 Vault KMS 加密存储';
COMMENT ON COLUMN public.user_providers.provider_kind IS '内置厂商标识或 custom';
COMMENT ON COLUMN public.user_providers.endpoint_path IS '完整 API 路径，如 /anthropic/v1/messages 或 /v1/chat/completions';
