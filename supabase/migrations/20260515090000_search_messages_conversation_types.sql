-- ============================================================
-- Sage Phase 3: search_messages conversation type mapping
-- ============================================================
-- Frontend/runtime messages use:
--   user = user prompt
--   text = assistant visible text
-- while earlier memory code expected assistant. Keep the public RPC contract
-- as role_filter=user/assistant/all, but map assistant to text + legacy assistant.

DROP FUNCTION IF EXISTS public.search_messages(TEXT, UUID, INTEGER, INTEGER, TIMESTAMPTZ, TIMESTAMPTZ, TEXT);

CREATE OR REPLACE FUNCTION public.search_messages(
  q TEXT,
  user_id_filter UUID DEFAULT NULL,
  limit_n INTEGER DEFAULT 20,
  days_back INTEGER DEFAULT NULL,
  time_start TIMESTAMPTZ DEFAULT NULL,
  time_end TIMESTAMPTZ DEFAULT NULL,
  role_filter TEXT DEFAULT NULL
)
RETURNS TABLE (
  id UUID,
  task_id TEXT,
  type TEXT,
  content TEXT,
  created_at TIMESTAMPTZ,
  rank REAL
)
LANGUAGE plpgsql
STABLE
SECURITY INVOKER
AS $$
DECLARE
  effective_user_id UUID;
  normalized_role TEXT;
BEGIN
  IF q IS NULL OR LENGTH(TRIM(q)) = 0 THEN
    RETURN;
  END IF;

  effective_user_id := COALESCE(auth.uid(), user_id_filter);

  IF effective_user_id IS NULL THEN
    RETURN;
  END IF;

  IF limit_n IS NULL OR limit_n < 1 THEN
    limit_n := 20;
  ELSIF limit_n > 100 THEN
    limit_n := 100;
  END IF;

  normalized_role := lower(NULLIF(TRIM(role_filter), ''));
  IF normalized_role IS NOT NULL
     AND normalized_role NOT IN ('user', 'assistant') THEN
    normalized_role := NULL;
  END IF;

  RETURN QUERY
  SELECT
    m.id,
    m.task_id,
    m.type,
    m.content,
    m.created_at,
    pgroonga_score(m.tableoid, m.ctid)::REAL AS rank
  FROM public.messages m
  WHERE m.user_id = effective_user_id
    AND m.content &@~ q
    AND m.deleted_at IS NULL
    AND m.type IN ('user', 'text', 'assistant')
    AND (days_back IS NULL OR m.created_at >= NOW() - (days_back || ' days')::INTERVAL)
    AND (time_start IS NULL OR m.created_at >= time_start)
    AND (time_end IS NULL OR m.created_at <= time_end)
    AND (
      normalized_role IS NULL
      OR (normalized_role = 'user' AND m.type = 'user')
      OR (normalized_role = 'assistant' AND m.type IN ('text', 'assistant'))
    )
  ORDER BY rank DESC, m.created_at DESC
  LIMIT limit_n;
END;
$$;

COMMENT ON FUNCTION public.search_messages IS
  'Phase 3 v4: 只召回 conversational messages；assistant role maps to text + legacy assistant.';

REVOKE EXECUTE ON FUNCTION public.search_messages(TEXT, UUID, INTEGER, INTEGER, TIMESTAMPTZ, TIMESTAMPTZ, TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.search_messages(TEXT, UUID, INTEGER, INTEGER, TIMESTAMPTZ, TIMESTAMPTZ, TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION public.search_messages(TEXT, UUID, INTEGER, INTEGER, TIMESTAMPTZ, TIMESTAMPTZ, TEXT) TO service_role;
