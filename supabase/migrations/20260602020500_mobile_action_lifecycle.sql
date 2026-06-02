-- ============================================================
-- Sage 投资对讲机：行动卡生命周期与分组
-- ============================================================
-- mobile_actions 原先只用中文 status + priority 表达进度。
-- 本 migration 增加稳定枚举字段，供 iOS 行动 Tab 按分组收纳展示。

ALTER TABLE public.mobile_actions
  ADD COLUMN IF NOT EXISTS status_code TEXT,
  ADD COLUMN IF NOT EXISTS group_key    TEXT,
  ADD COLUMN IF NOT EXISTS completed_at TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS archived_at  TIMESTAMPTZ;

COMMENT ON COLUMN public.mobile_actions.status_code IS
  '稳定生命周期枚举：pending_review | awaiting_confirmation | active | pending_fill | partially_filled | filled | completed | cancelled | failed | expired。';
COMMENT ON COLUMN public.mobile_actions.group_key IS
  '行动 Tab 分组：exception | pending | confirmation | active | completed。';
COMMENT ON COLUMN public.mobile_actions.completed_at IS
  '进入成交/完成/取消/过期等终态的时间。';
COMMENT ON COLUMN public.mobile_actions.archived_at IS
  '用户主动归档时间；当前已完成分组默认折叠，预留后续手动归档。';

UPDATE public.mobile_actions
SET status_code = CASE
    WHEN status ILIKE '%拒绝%' OR status ILIKE '%失败%' THEN 'failed'
    WHEN status ILIKE '%部分成交%' THEN 'partially_filled'
    WHEN status ILIKE '%待成交%' OR status ILIKE '%已提交%' THEN 'pending_fill'
    WHEN status ILIKE '%已成交%' THEN 'filled'
    WHEN status ILIKE '%已下单%' OR status ILIKE '%已确认%' OR status ILIKE '%已分析%' THEN 'completed'
    WHEN status ILIKE '%监控中%' OR kind = 'system' OR kind = 'review' THEN 'active'
    WHEN status ILIKE '%待确认%' THEN 'awaiting_confirmation'
    WHEN status ILIKE '%待查看%' THEN 'pending_review'
    ELSE 'pending_review'
  END
WHERE status_code IS NULL;

UPDATE public.mobile_actions
SET group_key = CASE
    WHEN status_code = 'failed' THEN 'exception'
    WHEN status_code = 'pending_review' THEN 'pending'
    WHEN status_code = 'awaiting_confirmation' THEN 'confirmation'
    WHEN status_code IN ('active', 'pending_fill', 'partially_filled') THEN 'active'
    ELSE 'completed'
  END
WHERE group_key IS NULL;

UPDATE public.mobile_actions
SET completed_at = COALESCE(completed_at, created_at)
WHERE completed_at IS NULL
  AND status_code IN ('filled', 'completed', 'cancelled', 'failed', 'expired');

ALTER TABLE public.mobile_actions
  ALTER COLUMN status_code SET DEFAULT 'pending_review',
  ALTER COLUMN group_key SET DEFAULT 'pending';

CREATE INDEX IF NOT EXISTS mobile_actions_user_group_sort_idx
  ON public.mobile_actions (user_id, group_key, priority, created_at DESC);

CREATE INDEX IF NOT EXISTS mobile_actions_user_status_idx
  ON public.mobile_actions (user_id, status_code, created_at DESC);
