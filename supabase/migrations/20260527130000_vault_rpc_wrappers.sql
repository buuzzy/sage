-- Phase 5 补充：Vault RPC wrapper 函数
-- user-store.ts 通过 supabase.rpc() 调用这些函数来操作 Vault secrets
-- 这些函数使用 SECURITY DEFINER 以 service_role 权限执行

-- 插入 secret，返回 UUID
CREATE OR REPLACE FUNCTION public.vault_insert_secret(
  new_secret TEXT,
  new_name TEXT DEFAULT NULL,
  new_description TEXT DEFAULT NULL
) RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, vault
AS $$
DECLARE
  secret_id UUID;
BEGIN
  INSERT INTO vault.secrets (secret, name, description)
  VALUES (new_secret, new_name, new_description)
  RETURNING id INTO secret_id;
  RETURN secret_id;
END;
$$;

-- 删除 secret
CREATE OR REPLACE FUNCTION public.delete_vault_secret(
  secret_id UUID
) RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, vault
AS $$
BEGIN
  DELETE FROM vault.secrets WHERE id = secret_id;
END;
$$;

-- 授权：只有 service_role 可以调用这些函数
REVOKE ALL ON FUNCTION public.vault_insert_secret FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.vault_insert_secret TO service_role;

REVOKE ALL ON FUNCTION public.delete_vault_secret FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.delete_vault_secret TO service_role;

-- 为 user-store.ts 的 vaultGetSecret 创建视图访问
-- vault.decrypted_secrets 是 Supabase Vault 自带的视图，service_role 默认可访问
-- 但需要确保 PostgREST 能通过 .from('decrypted_secrets') 访问它
-- 如果 vault schema 未暴露给 PostgREST，创建一个 public schema 的 wrapper 视图
CREATE OR REPLACE VIEW public.decrypted_secrets AS
  SELECT id, name, description, decrypted_secret, created_at, updated_at
  FROM vault.decrypted_secrets;

-- 只允许 service_role 访问
REVOKE ALL ON public.decrypted_secrets FROM PUBLIC;
GRANT SELECT ON public.decrypted_secrets TO service_role;
