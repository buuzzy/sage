import type { SupabaseClient } from '@supabase/supabase-js';

import { classifyIdea } from '@/shared/services/idea-intent';
import type { IdeaCondition, IdeaTaskType } from '@/shared/services/idea-intent';
import type { IdeaAnalysis } from '@/shared/services/idea-analysis';

export type MobileActionKind =
  | 'idea_confirmation'
  | 'analysis_task'
  | 'price_watch'
  | 'plan_confirmation'
  | 'alert'
  | 'order_confirmation'
  | 'review'
  | 'system';

export type WatchStatus = 'watching' | 'triggered' | 'cancelled';

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
  status: string;
  taskType: IdeaTaskType;
  condition?: IdeaCondition;
  watchStatus?: WatchStatus;
  analysis?: IdeaAnalysis;
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
  task_type: string | null;
  condition_op: string | null;
  condition_price: number | null;
  watch_status: string | null;
  analysis: IdeaAnalysis | null;
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
  const taskType = (row.task_type as IdeaTaskType) ?? 'order';
  const condition: IdeaCondition | undefined =
    (row.condition_op === 'lte' || row.condition_op === 'gte') && typeof row.condition_price === 'number'
      ? { op: row.condition_op, price: row.condition_price }
      : undefined;
  const watchStatus =
    row.watch_status === 'watching' || row.watch_status === 'triggered' || row.watch_status === 'cancelled'
      ? (row.watch_status as WatchStatus)
      : undefined;

  return {
    id: row.id,
    transcript: row.transcript,
    symbol: row.symbol ?? '',
    intent: row.intent ?? '',
    status: row.status ?? '待确认',
    taskType,
    condition,
    watchStatus,
    analysis: row.analysis ?? undefined,
    createdAt: row.created_at,
  };
}

const IDEA_NOTE_COLUMNS =
  'id, transcript, symbol, intent, status, task_type, condition_op, condition_price, watch_status, analysis, created_at';

function opText(op: IdeaCondition['op']): string {
  return op === 'lte' ? '跌到' : '涨到';
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

/** 按任务类型决定行动卡的 kind / 标题 / 文案 / 初始状态。 */
function actionCopyFor(input: {
  taskType: IdeaTaskType;
  symbol: string;
  intent: string;
  condition?: IdeaCondition;
}): { kind: MobileActionKind; title: string; subtitle: string; status: string; priority: number } {
  const subject = [input.symbol, input.intent].filter(Boolean).join('');
  switch (input.taskType) {
    case 'analysis':
      return {
        kind: 'analysis_task',
        title: input.symbol ? `分析「${input.symbol}」` : '分析这个想法',
        subtitle: '点击查看 Sage 结合你持仓给出的判断',
        status: '待查看',
        priority: 0,
      };
    case 'conditional': {
      const cond = input.condition;
      const trigger = cond ? `${opText(cond.op)} ${cond.price}` : '触发条件';
      const verb = input.intent || '提醒你';
      return {
        kind: 'price_watch',
        title: input.symbol ? `监控「${input.symbol}」` : '价格监控',
        subtitle: `${input.symbol || '该标的'} ${trigger} 时提醒你${verb}`,
        status: '监控中',
        priority: 0,
      };
    }
    case 'order':
    default:
      return {
        kind: 'idea_confirmation',
        title: subject ? `确认${subject}想法` : '确认语音想法',
        subtitle: '已整理为想法卡，等待你确认是否生成交易计划',
        status: '待确认',
        priority: 0,
      };
  }
}

/**
 * 记录想法卡：分类 transcript → 按任务类型（下单 / 分析 / 条件监控）落 idea_notes
 * 并生成对应 kind 的行动条目。分析结果与监控触发是惰性的（在用户打开卡片 / 行情触发时产生）。
 */
export async function createIdeaNote(
  db: SupabaseClient,
  userId: string,
  input: { transcript?: string; symbol?: string; intent?: string }
): Promise<{ note: IdeaNote; action: MobileActionItem }> {
  const now = new Date().toISOString();
  const noteId = `idea-${Date.now()}`;
  const hasTranscript = !!input.transcript?.trim();
  const transcript = input.transcript?.trim() || DEFAULT_IDEA_TRANSCRIPT;

  // 语音想法走分类器（标的 + 意图 + 任务类型 + 条件价）；显式带参的 mock 路径直接用参数。
  const classified = await classifyIdea(transcript);
  const symbol = input.symbol?.trim() || classified.symbol || (hasTranscript ? '' : '比亚迪');
  const intent = input.intent?.trim() || classified.intent || (hasTranscript ? '' : '加仓');
  const taskType = classified.taskType;
  const condition = classified.condition;

  const initialStatus = taskType === 'order' ? '待确认' : taskType === 'analysis' ? '待查看' : '监控中';

  const { data: noteData, error: noteErr } = await db
    .from('idea_notes')
    .insert({
      id: noteId,
      user_id: userId,
      transcript,
      symbol,
      intent,
      status: initialStatus,
      task_type: taskType,
      condition_op: condition?.op ?? null,
      condition_price: condition?.price ?? null,
      watch_status: taskType === 'conditional' ? 'watching' : null,
      created_at: now,
    })
    .select(IDEA_NOTE_COLUMNS)
    .single();

  if (noteErr || !noteData) {
    throw new Error(`Failed to create idea note: ${noteErr?.message ?? 'no row'}`);
  }

  const copy = actionCopyFor({ taskType, symbol, intent, condition });
  const actionId = `action-${noteId}`;
  const { data: actionData, error: actionErr } = await db
    .from('mobile_actions')
    .insert({
      id: actionId,
      user_id: userId,
      kind: copy.kind,
      title: copy.title,
      subtitle: copy.subtitle,
      status: copy.status,
      priority: copy.priority,
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
 * 读取单条想法卡（按 userId 隔离），用于订单草稿/确认流程加载上下文。
 */
export async function getIdeaNote(
  db: SupabaseClient,
  userId: string,
  noteId: string
): Promise<IdeaNote | null> {
  const { data, error } = await db
    .from('idea_notes')
    .select(IDEA_NOTE_COLUMNS)
    .eq('id', noteId)
    .eq('user_id', userId)
    .maybeSingle();

  if (error) {
    throw new Error(`Failed to load idea note: ${error.message}`);
  }
  return data ? toIdeaNote(data as IdeaNoteRow) : null;
}

/**
 * 缓存分析结果到 idea_notes.analysis，并把对应分析卡标记「已分析」。
 * 分析是惰性生成的（用户打开卡片时），缓存后下次直接读，避免重复调用 LLM。
 */
export async function saveIdeaAnalysis(
  db: SupabaseClient,
  userId: string,
  noteId: string,
  analysis: IdeaAnalysis
): Promise<void> {
  const { error } = await db
    .from('idea_notes')
    .update({ analysis })
    .eq('id', noteId)
    .eq('user_id', userId);
  if (error) {
    throw new Error(`Failed to save idea analysis: ${error.message}`);
  }

  await db
    .from('mobile_actions')
    .update({ status: '已分析', priority: 6 })
    .eq('note_id', noteId)
    .eq('kind', 'analysis_task')
    .eq('user_id', userId);
}

/**
 * 条件单触发：想法 watch_status → triggered，并把监控卡转成「待确认」下单卡，
 * 复用既有两步确认流程进入下单页。由实时行情监控或手动模拟触发调用。
 */
export async function triggerWatch(
  db: SupabaseClient,
  userId: string,
  noteId: string
): Promise<IdeaNote | null> {
  const note = await getIdeaNote(db, userId, noteId);
  if (!note || note.taskType !== 'conditional') return null;
  if (note.watchStatus === 'triggered') return note;

  const { error: noteErr } = await db
    .from('idea_notes')
    .update({ watch_status: 'triggered', status: '待确认' })
    .eq('id', noteId)
    .eq('user_id', userId);
  if (noteErr) {
    throw new Error(`Failed to trigger watch: ${noteErr.message}`);
  }

  const cond = note.condition;
  const trigger = cond ? `${opText(cond.op)} ${cond.price}` : '触发条件';
  await db
    .from('mobile_actions')
    .update({
      kind: 'idea_confirmation',
      title: `${note.symbol || '标的'}已${trigger} · 确认${note.intent || '操作'}`,
      subtitle: '你设定的条件已触发，确认后进入下单',
      status: '待确认',
      priority: 0,
    })
    .eq('note_id', noteId)
    .eq('kind', 'price_watch')
    .eq('user_id', userId);

  return await getIdeaNote(db, userId, noteId);
}

/**
 * 记录模拟盘下单结果：新增一条成交行动卡，并把对应想法卡的确认条目降权标记「已下单」。
 */
export async function recordOrderResult(
  db: SupabaseClient,
  userId: string,
  input: {
    orderId: string;
    noteId?: string;
    name: string;
    side: 'BUY' | 'SELL';
    quantity: number;
    price: number;
    status: string;
  }
): Promise<MobileActionItem> {
  const now = new Date().toISOString();
  const sideText = input.side === 'BUY' ? '买入' : '卖出';
  const statusText = input.status === 'FILLED' ? '已成交' : input.status === 'REJECTED' ? '已拒绝' : '已提交';
  const id = `action-order-${input.orderId}`;

  const { data, error } = await db
    .from('mobile_actions')
    .insert({
      id,
      user_id: userId,
      kind: 'order_confirmation',
      title: `模拟盘 · ${input.name} ${sideText} ${input.quantity} 股`,
      subtitle: `委托价 ${input.price} · ${statusText}`,
      status: statusText,
      priority: 2,
      note_id: input.noteId ?? null,
      created_at: now,
    })
    .select('*')
    .single();

  if (error || !data) {
    throw new Error(`Failed to record order result: ${error?.message ?? 'no row'}`);
  }

  if (input.noteId) {
    await db
      .from('mobile_actions')
      .update({ status: '已下单', priority: 11 })
      .eq('note_id', input.noteId)
      .eq('kind', 'idea_confirmation')
      .eq('user_id', userId);
  }

  return toActionItem(data as MobileActionRow);
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
