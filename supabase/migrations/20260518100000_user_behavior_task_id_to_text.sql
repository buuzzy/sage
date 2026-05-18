-- ============================================================
-- Fix: user_behavior.task_id UUID → TEXT
-- ============================================================
-- 根因：
--   前端 createTask() 用 Date.now().toString() 生成 task_id（如 "1777630441077"），
--   messages.task_id 列是 TEXT 类型，所以消息同步正常。
--   但 user_behavior.task_id 在建表时误设为 UUID，导致客户端
--   sync_queue 里所有 user_behavior INSERT 都因
--   "invalid input syntax for type uuid" 无限重试。
--
-- 修复：ALTER COLUMN task_id TYPE TEXT。
--   表当前无数据（全部被 UUID 类型拒掉了），ALTER 零代价。
-- ============================================================

ALTER TABLE public.user_behavior
  ALTER COLUMN task_id TYPE TEXT;
