-- ============================================================
-- Sage 投资对讲机：想法卡任务类型化（下单 / 分析 / 条件监控）
-- ============================================================
-- 背景：
--   原 idea_notes 把每条想法都当成「即时下单」。实际想法分三类：
--     · order       立即下单意图
--     · analysis    分析/咨询（「宁德时代要不要止盈」）→ 缓存 Sage 分析观点
--     · conditional 价格条件触发（「比亚迪回调到 230 加仓」）→ 监控行情，命中转下单
--
--   本 migration 为 idea_notes 增加任务类型、触发条件、监控状态、分析缓存列。
--
-- 设计要点：
--   · task_type 默认 'order'，兼容历史行（历史想法视为下单类）。
--   · condition_op/condition_price：仅条件单使用，监控 sweep 直接 SQL 过滤。
--   · watch_status：watching|triggered|cancelled，配合 (task_type, watch_status) 索引。
--   · analysis：JSONB 缓存 LLM 分析结果，避免重复调用。
-- ============================================================

ALTER TABLE public.idea_notes
  ADD COLUMN IF NOT EXISTS task_type       TEXT NOT NULL DEFAULT 'order',
  ADD COLUMN IF NOT EXISTS condition_op    TEXT,
  ADD COLUMN IF NOT EXISTS condition_price NUMERIC,
  ADD COLUMN IF NOT EXISTS watch_status    TEXT,
  ADD COLUMN IF NOT EXISTS analysis        JSONB;

COMMENT ON COLUMN public.idea_notes.task_type IS
  '想法任务类型：order(立即下单) | analysis(分析咨询) | conditional(价格条件触发)。';
COMMENT ON COLUMN public.idea_notes.condition_op IS
  '条件单方向：lte(跌到/低于) | gte(涨到/突破)。仅 task_type=conditional 使用。';
COMMENT ON COLUMN public.idea_notes.condition_price IS
  '条件单目标价。仅 task_type=conditional 使用。';
COMMENT ON COLUMN public.idea_notes.watch_status IS
  '条件单监控状态：watching | triggered | cancelled。';
COMMENT ON COLUMN public.idea_notes.analysis IS
  '分析任务的 LLM 结构化结论缓存（conclusion / points / suggestOrder 等）。';

-- 监控 sweep 高频查询：按任务类型 + 监控状态过滤活跃条件单。
CREATE INDEX IF NOT EXISTS idea_notes_watch_idx
  ON public.idea_notes (task_type, watch_status)
  WHERE task_type = 'conditional';
