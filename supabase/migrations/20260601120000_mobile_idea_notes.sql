-- ============================================================
-- Sage 投资对讲机：idea_notes + mobile_actions
-- ============================================================
-- 背景：
--   iOS「投资对讲机」重构后，首页（资产）/ 行动 Tab 由后端 Product API
--   (/mobile/*) 提供结构化卡片。其中：
--     · idea_notes —— 对讲机按钮记录的「想法卡」（语音/文本整理后的投资意图）
--     · mobile_actions —— 行动中心 feed（想法确认、复盘、定时任务结果、提醒等）
--
--   早期实现用模块级内存数组承载，单实例下所有用户共享、重启即丢，违背
--   「架构稳健」原则。本 migration 将二者落库，按 user_id 做 RLS 隔离。
--
-- 设计要点：
--   · id 用 TEXT（后端生成 `idea-<ts>` / `action-<...>`），与既有 tasks.id
--     (Date.now().toString()) 的 TEXT 约定一致，避免 UUID/TEXT 混用踩坑。
--   · 用户态请求走 user-scoped client（anon + JWT），RLS 强制 auth.uid()=user_id。
--   · 服务端 cron 写入走 service_role（bypass RLS），显式带 user_id。
--   · 系统默认卡片（如富途连接提示）在代码层按需生成，不入库，新用户也可见。
-- ============================================================

-- ────────────────────────────────────────────────────────────
-- 1. idea_notes —— 想法卡
-- ────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.idea_notes (
  id          TEXT PRIMARY KEY,
  user_id     UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  transcript  TEXT NOT NULL,
  symbol      TEXT NOT NULL DEFAULT '',
  intent      TEXT NOT NULL DEFAULT '',
  status      TEXT NOT NULL DEFAULT '待确认',
  created_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);

COMMENT ON TABLE public.idea_notes IS
  '投资对讲机想法卡：对讲机按钮记录的投资意图（语音/文本整理结果）。按 user_id RLS 隔离。';

CREATE INDEX IF NOT EXISTS idea_notes_user_id_created_idx
  ON public.idea_notes (user_id, created_at DESC);

-- ────────────────────────────────────────────────────────────
-- 2. mobile_actions —— 行动中心 feed
-- ────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.mobile_actions (
  id          TEXT PRIMARY KEY,
  user_id     UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  kind        TEXT NOT NULL DEFAULT 'system',
  title       TEXT NOT NULL,
  subtitle    TEXT NOT NULL DEFAULT '',
  status      TEXT NOT NULL DEFAULT '',
  priority    INTEGER NOT NULL DEFAULT 5,
  note_id     TEXT REFERENCES public.idea_notes(id) ON DELETE CASCADE,
  created_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);

COMMENT ON TABLE public.mobile_actions IS
  '投资对讲机行动中心条目：想法确认 / 复盘 / 定时任务结果 / 提醒等。kind 取 idea_confirmation|plan_confirmation|alert|order_confirmation|review|system。按 user_id RLS 隔离。';
COMMENT ON COLUMN public.mobile_actions.priority IS
  '排序优先级，越小越靠前（0 = 最高）。系统默认卡片在代码层生成不入库。';

CREATE INDEX IF NOT EXISTS mobile_actions_user_id_priority_idx
  ON public.mobile_actions (user_id, priority, created_at DESC);

-- ────────────────────────────────────────────────────────────
-- 3. RLS：用户只能读写自己的想法卡 / 行动条目
-- ────────────────────────────────────────────────────────────
ALTER TABLE public.idea_notes ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.mobile_actions ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "idea_notes_self_all" ON public.idea_notes;
CREATE POLICY "idea_notes_self_all"
  ON public.idea_notes
  FOR ALL
  USING (auth.uid() = user_id)
  WITH CHECK (auth.uid() = user_id);

DROP POLICY IF EXISTS "mobile_actions_self_all" ON public.mobile_actions;
CREATE POLICY "mobile_actions_self_all"
  ON public.mobile_actions
  FOR ALL
  USING (auth.uid() = user_id)
  WITH CHECK (auth.uid() = user_id);

-- ────────────────────────────────────────────────────────────
-- 4. service_role 授权（Railway cron 写定时任务结果用）
--    service_role 默认 bypass RLS，这里显式 GRANT 作 belt-and-suspenders。
-- ────────────────────────────────────────────────────────────
GRANT SELECT, INSERT, UPDATE, DELETE ON public.idea_notes TO service_role;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.mobile_actions TO service_role;
