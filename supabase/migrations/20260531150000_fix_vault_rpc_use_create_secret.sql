-- 修复 Vault RPC wrapper：使用 vault.create_secret() 替代直接 INSERT
--
-- 问题：之前的实现直接 INSERT INTO vault.secrets，触发了 Vault 的
-- BEFORE INSERT 加密 trigger，该 trigger 调用 pgsodium._crypto_aead_det_noncegen，
-- 而 SECURITY DEFINER 函数的 owner 没有权限调用 pgsodium 内部函数。
-- 错误信息："permission denied for function _crypto_aead_det_noncegen" (SQLSTATE 42501)
--
-- 解决：vault.create_secret() 是 Supabase 官方推荐的入口，内置正确权限链路。
-- 参考：https://supabase.com/docs/guides/database/vault
-- 参考：https://github.com/amElnagdy/basarai/blob/master/supabase/migrations/00013_fix_vault_insert.sql

CREATE OR REPLACE FUNCTION public.vault_insert_secret(
  new_secret TEXT,
  new_name TEXT DEFAULT NULL,
  new_description TEXT DEFAULT NULL
) RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  secret_id UUID;
BEGIN
  SELECT vault.create_secret(new_secret, new_name, COALESCE(new_description, '')) INTO secret_id;
  RETURN secret_id;
END;
$$;

CREATE OR REPLACE FUNCTION public.delete_vault_secret(
  secret_id UUID
) RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  DELETE FROM vault.secrets WHERE id = secret_id;
END;
$$;

REVOKE ALL ON FUNCTION public.vault_insert_secret FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.vault_insert_secret TO service_role;
REVOKE ALL ON FUNCTION public.delete_vault_secret FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.delete_vault_secret TO service_role;
