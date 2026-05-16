-- Store provider/SDK usage snapshots captured at task completion.
-- This is intentionally task-level first; per-request accounting can be added
-- later without blocking cloud history restore.

ALTER TABLE public.tasks
  ADD COLUMN IF NOT EXISTS provider_usage JSONB;
