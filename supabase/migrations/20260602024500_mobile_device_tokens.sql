-- ============================================================
-- Sage iOS：APNs 设备 token
-- ============================================================

CREATE TABLE IF NOT EXISTS public.mobile_device_tokens (
  id          TEXT PRIMARY KEY,
  user_id     UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  platform    TEXT NOT NULL DEFAULT 'ios',
  token       TEXT NOT NULL,
  environment TEXT NOT NULL DEFAULT 'production',
  app_version TEXT,
  last_seen_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  created_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE (user_id, token)
);

COMMENT ON TABLE public.mobile_device_tokens IS
  'iOS APNs device token registry. User-scoped insert/update via RLS; Railway service-role reads for push delivery.';
COMMENT ON COLUMN public.mobile_device_tokens.environment IS
  'APNs environment: sandbox | production.';

CREATE INDEX IF NOT EXISTS mobile_device_tokens_user_seen_idx
  ON public.mobile_device_tokens (user_id, last_seen_at DESC);

ALTER TABLE public.mobile_device_tokens ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "mobile_device_tokens_self_all" ON public.mobile_device_tokens;
CREATE POLICY "mobile_device_tokens_self_all"
  ON public.mobile_device_tokens
  FOR ALL
  USING (auth.uid() = user_id)
  WITH CHECK (auth.uid() = user_id);

GRANT SELECT, INSERT, UPDATE, DELETE ON public.mobile_device_tokens TO authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.mobile_device_tokens TO service_role;
