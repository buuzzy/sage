import type { SupabaseClient } from '@supabase/supabase-js';

import { extractIdeaIntent } from '@/shared/services/idea-intent';

export type MobileActionKind =
  | 'idea_confirmation'
  | 'plan_confirmation'
  | 'alert'
  | 'order_confirmation'
  | 'review'
  | 'system';

export interface MobileActionItem {
  id: string;
  kind: MobileActionKind;
  title: string;
  subtitle: string;
  status: string;
  priority: number;
  createdAt: string;
  noteId?: string;
}

export interface IdeaNote {
  id: string;
  transcript: string;
  symbol: string;
  intent: string;
  status: '待确认' | '已确认';
  createdAt: string;
}

interface MobileActionRow {
  id: string;
  kind: string;
  title: string;
  subtitle: string | null;
  status: string | null;
  priority: number | null;
  note_id: string | null;
  created_at: string;
}

interface IdeaNoteRow {
  id: string;
  transcript: string;
  symbol: string | null;
  intent: string | null;
  status: string | null;
  created_at: string;
}

const DEFAULT_IDEA_TRANSCRIPT =
  '比亚迪如果回调到 230 附近可以加仓，新能源调整差不多了。';

/**
 * 系统默认卡片：不入库，每次读取时按需生成，保证新用户也能看到上下文提示。
 * 真正的动态条目（想法确认、定时任务结果）才落 mobile_actions 表。
 */
function systemActions(): MobileActionItem[] {
  return [
    {
      id: 'system-futu-mock',
      kind: 'system',
      title: '富途模拟盘数据已接入 mock',
      subtitle: '开户完成后将替换为真实模拟盘 adapter，接口保持不变',
      status: '准备中',
      priority: 9,
      createdAt: new Date(0).toISOString(),
    },
  ];
}

function toActionItem(row: MobileActionRow): MobileActionItem {
  return {
    id: row.id,
    kind: (row.kind as MobileActionKind) ?? 'system',
    title: row.title,
    subtitle: row.subtitle ?? '',
    status: row.status ?? '',
    priority: row.priority ?? 5,
    createdAt: row.created_at,
    noteId: row.note_id ?? undefined,
  };
}

function toIdeaNote(row: IdeaNoteRow): IdeaNote {
  return {
    id: row.id,
    transcript: row.transcript,
    symbol: row.symbol ?? '',
    intent: row.intent ?? '',
    status: (row.status as IdeaNote['status']) ?? '待确认',
    createdAt: row.created_at,
  };
}

function sortActions(items: MobileActionItem[]): MobileActionItem[] {
  return [...items].sort((left, right) => {
    if (left.priority !== right.priority) return left.priority - right.priority;
    return right.createdAt.localeCompare(left.createdAt);
  });
}

/**
 * 行动中心 feed = 用户持久化动态条目 + 代码层系统默认卡片。
 */
export async function listMobileActions(
  db: SupabaseClient,
  userId: string
): Promise<MobileActionItem[]> {
  const { data, error } = await db
    .from('mobile_actions')
    .select('*')
    .eq('user_id', userId);

  if (error) {
    throw new Error(`Failed to list mobile actions: ${error.message}`);
  }

  const persisted = (data as MobileActionRow[] | null)?.map(toActionItem) ?? [];
  return sortActions([...persisted, ...systemActions()]);
}

/**
 * 记录想法卡：插入 idea_notes + 对应 idea_confirmation 行动条目。
 */
export async function createIdeaNote(
  db: SupabaseClient,
  userId: string,
  input: { transcript?: string; symbol?: string; intent?: string }
): Promise<{ note: IdeaNote; action: MobileActionItem }> {
  const now = new Date().toISOString();
  const noteId = `idea-${Date.now()}`;
  // 有真实语音转写时不伪造标的/意图（避免「说宁德时代、卡片显示比亚迪」），
  // 留空让前端隐藏标签 + 后续 Agent 意图抽取补齐；纯 mock 按钮路径才用演示默认值。
  const hasTranscript = !!input.transcript?.trim();
  const transcript = input.transcript?.trim() || DEFAULT_IDEA_TRANSCRIPT;
  let symbol = input.symbol?.trim() || (hasTranscript ? '' : '比亚迪');
  let intent = input.intent?.trim() || (hasTranscript ? '' : '加仓');

  // 语音想法且未显式带标的/意图时，用 LLM 从转写文本里抽取（best-effort，失败保持留空）。
  if (hasTranscript && !symbol && !intent) {
    const extracted = await extractIdeaIntent(transcript);
    symbol = extracted.symbol;
    intent = extracted.intent;
  }

  const subject = [symbol, intent].filter(Boolean).join('');

  const { data: noteData, error: noteErr } = await db
    .from('idea_notes')
    .insert({
      id: noteId,
      user_id: userId,
      transcript,
      symbol,
      intent,
      status: '待确认',
      created_at: now,
    })
    .select('*')
    .single();

  if (noteErr || !noteData) {
    throw new Error(`Failed to create idea note: ${noteErr?.message ?? 'no row'}`);
  }

  const actionId = `action-${noteId}`;
  const { data: actionData, error: actionErr } = await db
    .from('mobile_actions')
    .insert({
      id: actionId,
      user_id: userId,
      kind: 'idea_confirmation',
      title: subject ? `确认${subject}想法` : '确认语音想法',
      subtitle: '已整理为想法卡，等待你确认是否生成交易计划',
      status: '待确认',
      priority: 0,
      note_id: noteId,
      created_at: now,
    })
    .select('*')
    .single();

  if (actionErr || !actionData) {
    throw new Error(`Failed to create action: ${actionErr?.message ?? 'no row'}`);
  }

  return {
    note: toIdeaNote(noteData as IdeaNoteRow),
    action: toActionItem(actionData as MobileActionRow),
  };
}

/**
 * 确认想法卡：想法状态置「已确认」，对应行动条目降权并标记完成。
 */
export async function confirmIdeaNote(
  db: SupabaseClient,
  userId: string,
  noteId: string
): Promise<{ note: IdeaNote; action: MobileActionItem | null } | null> {
  const { data: noteData, error: noteErr } = await db
    .from('idea_notes')
    .update({ status: '已确认' })
    .eq('id', noteId)
    .eq('user_id', userId)
    .select('*')
    .maybeSingle();

  if (noteErr) {
    throw new Error(`Failed to confirm idea note: ${noteErr.message}`);
  }
  if (!noteData) return null;

  const { data: actionData } = await db
    .from('mobile_actions')
    .update({ status: '已确认', priority: 10 })
    .eq('note_id', noteId)
    .eq('user_id', userId)
    .select('*')
    .maybeSingle();

  return {
    note: toIdeaNote(noteData as IdeaNoteRow),
    action: actionData ? toActionItem(actionData as MobileActionRow) : null,
  };
}

/**
 * 定时任务结果落地为行动卡（由 Railway cron 用 service-role client 调用）。
 * 让早报 / 提醒等定时结果直接出现在「行动」Tab，而不是只写 sessions 表。
 */
export async function appendCronAction(
  db: SupabaseClient,
  userId: string,
  input: { jobName: string; preview?: string; sessionId?: string }
): Promise<void> {
  const now = new Date().toISOString();
  const id = `action-cron-${input.sessionId ?? Date.now()}`;

  const { error } = await db.from('mobile_actions').insert({
    id,
    user_id: userId,
    kind: 'review',
    title: input.jobName,
    subtitle: input.preview?.slice(0, 120) || '定时任务已生成新结果，点击查看',
    status: '待查看',
    priority: 1,
    created_at: now,
  });

  if (error) {
    throw new Error(`Failed to append cron action: ${error.message}`);
  }
}
