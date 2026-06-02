import { Hono } from 'hono';
import type { Context } from 'hono';

import { createUserScopedSupabase } from '@/shared/supabase/client';
import {
  confirmIdeaNote,
  createIdeaNote,
  getIdeaNote,
  listMobileActions,
  recordOrderResult,
  saveIdeaAnalysis,
  triggerWatch,
} from '@/shared/services/mobile-actions';
import { getMobileDashboard } from '@/shared/services/mobile-dashboard';
import { transcribeAudio, TranscriptionError } from '@/shared/services/transcribe';
import { buildOrderDraft } from '@/shared/services/order-draft';
import {
  analyzeOrderIdea,
  cachedOrderAnalysis,
  mergeOrderAnalysisCache,
} from '@/shared/services/order-analysis';
import { analyzeIdea } from '@/shared/services/idea-analysis';
import { upsertMobileDeviceToken } from '@/shared/services/mobile-device-tokens';
import { getBrokerAdapter } from '@/shared/broker';
import { MarketDataUnavailableError } from '@/shared/broker/market-data-error';
import type { OrderType, TradeSide } from '@/shared/broker';

export const mobileRoutes = new Hono();

const SSE_HEADERS = {
  'Content-Type': 'text/event-stream',
  'Cache-Control': 'no-cache, no-transform',
  Connection: 'keep-alive',
  'X-Accel-Buffering': 'no',
};

/**
 * 用户态上下文：从 localOnlyMiddleware 注入的 userId + Bearer JWT 派生出
 * user-scoped supabase client（RLS 强制 auth.uid()=user_id）。
 * 共享 SAGE_API_TOKEN（server-to-server）无用户身份，访问这些接口返回 401。
 */
function userContext(c: Context): { userId: string; accessToken: string } | null {
  const userId = c.get('userId');
  const authHeader = c.req.header('authorization');
  const accessToken = authHeader?.startsWith('Bearer ') ? authHeader.slice(7) : '';
  if (!userId || !accessToken) return null;
  return { userId, accessToken };
}

mobileRoutes.get('/dashboard', async (c) => {
  const dashboard = await getMobileDashboard();
  return c.json({ ok: true, dashboard });
});

mobileRoutes.get('/actions', async (c) => {
  const ctx = userContext(c);
  if (!ctx) return c.json({ ok: false, error: 'User authentication required' }, 401);

  const db = createUserScopedSupabase(ctx.accessToken);
  const actions = await listMobileActions(db, ctx.userId);
  return c.json({ ok: true, actions });
});

mobileRoutes.post('/device-token', async (c) => {
  const ctx = userContext(c);
  if (!ctx) return c.json({ ok: false, error: 'User authentication required' }, 401);

  type DeviceTokenBody = Partial<{ token: string; platform: string; environment: string; appVersion: string }>;
  const body = await c.req
    .json<DeviceTokenBody>()
    .catch((): DeviceTokenBody => ({}));
  if (!body.token?.trim()) {
    return c.json({ ok: false, error: 'token is required' }, 400);
  }

  const db = createUserScopedSupabase(ctx.accessToken);
  await upsertMobileDeviceToken(db, ctx.userId, {
    token: body.token,
    platform: body.platform,
    environment: body.environment,
    appVersion: body.appVersion,
  });
  return c.json({ ok: true });
});

/**
 * 对讲机语音转文字：iOS 按住录音 → multipart 上传音频 → SenseVoice 转写 → 返回文本。
 * 需用户 JWT（防止共享 token 滥用 ASR 配额）；key 留 Railway env，不下发客户端。
 */
mobileRoutes.post('/transcribe', async (c) => {
  const ctx = userContext(c);
  if (!ctx) return c.json({ ok: false, error: 'User authentication required' }, 401);

  const body = await c.req.parseBody();
  const file = body['file'];
  if (!(file instanceof File)) {
    return c.json({ ok: false, error: 'audio file (multipart field "file") required' }, 400);
  }

  try {
    const text = await transcribeAudio(file, file.name || 'audio.m4a');
    return c.json({ ok: true, text });
  } catch (err) {
    const status: 500 | 502 | 503 = err instanceof TranscriptionError ? err.httpStatus : 500;
    const message = err instanceof Error ? err.message : 'transcription failed';
    return c.json({ ok: false, error: message }, status);
  }
});

mobileRoutes.post('/notes', async (c) => {
  const ctx = userContext(c);
  if (!ctx) return c.json({ ok: false, error: 'User authentication required' }, 401);

  const body = await c.req
    .json<Partial<{ transcript: string; symbol: string; intent: string }>>()
    .catch(() => ({}));

  const db = createUserScopedSupabase(ctx.accessToken);
  const result = await createIdeaNote(db, ctx.userId, body);
  return c.json({ ok: true, ...result }, 201);
});

mobileRoutes.post('/notes/:id/confirm', async (c) => {
  const ctx = userContext(c);
  if (!ctx) return c.json({ ok: false, error: 'User authentication required' }, 401);

  const id = c.req.param('id');
  const db = createUserScopedSupabase(ctx.accessToken);
  const result = await confirmIdeaNote(db, ctx.userId, id);
  if (!result) {
    return c.json({ ok: false, error: 'note not found' }, 404);
  }
  return c.json({ ok: true, ...result });
});

/**
 * 想法卡详情：返回完整 note（含任务类型 / 条件 / 监控状态 / 已缓存的分析）。
 * 条件单额外附带当前行情价，供监控详情页展示「现价 vs 目标价」。
 */
mobileRoutes.get('/notes/:id', async (c) => {
  const ctx = userContext(c);
  if (!ctx) return c.json({ ok: false, error: 'User authentication required' }, 401);

  const db = createUserScopedSupabase(ctx.accessToken);
  const note = await getIdeaNote(db, ctx.userId, c.req.param('id'));
  if (!note) return c.json({ ok: false, error: 'note not found' }, 404);

  let quote: number | null = null;
  if (note.taskType === 'conditional' && note.symbol) {
    const adapter = getBrokerAdapter();
    const resolved = await adapter.resolveInstrument(note.symbol);
    quote = resolved ? await adapter.getQuote(resolved.code) : null;
  }

  return c.json({ ok: true, note, quote });
});

/**
 * 分析任务：惰性生成（首次打开分析卡时调用），结合持仓上下文给出结构化判断并缓存。
 * 已缓存则直接返回，避免重复消耗 LLM。
 */
mobileRoutes.post('/notes/:id/analyze', async (c) => {
  const ctx = userContext(c);
  if (!ctx) return c.json({ ok: false, error: 'User authentication required' }, 401);

  const db = createUserScopedSupabase(ctx.accessToken);
  const note = await getIdeaNote(db, ctx.userId, c.req.param('id'));
  if (!note) return c.json({ ok: false, error: 'note not found' }, 404);

  if (note.analysis) {
    return c.json({ ok: true, note, analysis: note.analysis });
  }

  const analysis = await analyzeIdea({
    symbol: note.symbol,
    intent: note.intent,
    transcript: note.transcript,
  });
  await saveIdeaAnalysis(db, ctx.userId, note.id, analysis);
  return c.json({ ok: true, note: { ...note, analysis }, analysis });
});

/**
 * 手动模拟触发条件单（demo 用）：把监控卡立即转为待确认下单卡。
 * 真实自动触发由 Railway 后台 sweep（price-watch monitor）按行情完成。
 */
mobileRoutes.post('/notes/:id/trigger', async (c) => {
  const ctx = userContext(c);
  if (!ctx) return c.json({ ok: false, error: 'User authentication required' }, 401);

  const db = createUserScopedSupabase(ctx.accessToken);
  const note = await triggerWatch(db, ctx.userId, c.req.param('id'));
  if (!note) return c.json({ ok: false, error: 'note not found or not a conditional watch' }, 404);
  return c.json({ ok: true, note });
});

/**
 * 两步确认 Step1：流式生成「标的分析」。
 * 过程会读取行情、模拟账户、华泰/机构研报和资讯，并持续返回进度事件。
 */
mobileRoutes.get('/notes/:id/order-analysis/stream', async (c) => {
  const ctx = userContext(c);
  if (!ctx) return c.json({ ok: false, error: 'User authentication required' }, 401);

  const db = createUserScopedSupabase(ctx.accessToken);
  const note = await getIdeaNote(db, ctx.userId, c.req.param('id'));
  if (!note) return c.json({ ok: false, error: 'note not found' }, 404);

  const encoder = new TextEncoder();
  const readable = new ReadableStream({
    async start(controller) {
      const send = (event: Record<string, unknown>) => {
        controller.enqueue(encoder.encode(`data: ${JSON.stringify(event)}\n\n`));
      };

      try {
        const cached = cachedOrderAnalysis(note);
        if (cached) {
          send({ type: 'progress', step: 'synthesizing', status: 'done', message: '已读取缓存的标的分析' });
          send({ type: 'result', analysis: cached });
          return;
        }

        const analysis = await analyzeOrderIdea(note, (progress) => {
          send({ type: 'progress', ...progress });
        });
        await saveIdeaAnalysis(db, ctx.userId, note.id, mergeOrderAnalysisCache(note, analysis));
        send({ type: 'result', analysis });
      } catch (error) {
        const message = error instanceof Error ? error.message : '标的分析失败';
        send({ type: 'error', message });
      } finally {
        send({ type: 'done' });
        controller.close();
      }
    },
  });

  return new Response(readable, { headers: SSE_HEADERS });
});

/**
 * 两步确认 Step2：按想法卡（标的+意图）生成模拟盘订单草稿（富途语义）。
 * 返回 note + draft，iOS 据此渲染可调整的下单表单。
 */
mobileRoutes.get('/notes/:id/order-draft', async (c) => {
  const ctx = userContext(c);
  if (!ctx) return c.json({ ok: false, error: 'User authentication required' }, 401);

  const db = createUserScopedSupabase(ctx.accessToken);
  const note = await getIdeaNote(db, ctx.userId, c.req.param('id'));
  if (!note) return c.json({ ok: false, error: 'note not found' }, 404);

  try {
    const draft = await buildOrderDraft({ symbol: note.symbol, intent: note.intent });
    return c.json({ ok: true, note, draft });
  } catch (error) {
    if (error instanceof MarketDataUnavailableError) {
      return c.json({ ok: false, error: error.message }, 503);
    }
    throw error;
  }
});

const TRADE_SIDES = new Set<TradeSide>(['BUY', 'SELL']);
const ORDER_TYPES = new Set<OrderType>(['NORMAL', 'MARKET', 'ABSOLUTE_LIMIT']);

/**
 * 两步确认 Step3：把（可能被用户调整过的）草稿提交到富途模拟盘，
 * 记录成交行动卡并把对应想法卡标记「已下单」。
 */
mobileRoutes.post('/orders', async (c) => {
  const ctx = userContext(c);
  if (!ctx) return c.json({ ok: false, error: 'User authentication required' }, 401);

  type OrderBody = Partial<{
    noteId: string;
    accountId: string;
    code: string;
    name: string;
    side: TradeSide;
    orderType: OrderType;
    price: number;
    quantity: number;
  }>;
  const body = await c.req.json<OrderBody>().catch((): OrderBody => ({}));

  if (!body.accountId || !body.code) {
    return c.json({ ok: false, error: 'accountId and code are required' }, 400);
  }
  if (!body.side || !TRADE_SIDES.has(body.side)) {
    return c.json({ ok: false, error: 'side must be BUY or SELL' }, 400);
  }
  if (!body.orderType || !ORDER_TYPES.has(body.orderType)) {
    return c.json({ ok: false, error: 'orderType is invalid' }, 400);
  }
  if (!Number.isFinite(body.price) || Number(body.price) <= 0) {
    return c.json({ ok: false, error: 'price must be greater than 0' }, 400);
  }
  if (!Number.isFinite(body.quantity) || Number(body.quantity) <= 0) {
    return c.json({ ok: false, error: 'quantity must be greater than 0' }, 400);
  }

  try {
    const order = await getBrokerAdapter().submitSimulatedOrder({
      accountId: body.accountId,
      code: body.code,
      side: body.side,
      orderType: body.orderType,
      price: Number(body.price),
      quantity: Number(body.quantity),
      remark: body.noteId ? `note:${body.noteId}` : undefined,
    });

    const db = createUserScopedSupabase(ctx.accessToken);
    const action = await recordOrderResult(db, ctx.userId, {
      orderId: order.id,
      noteId: body.noteId,
      name: body.name?.trim() || body.code,
      side: order.side,
      quantity: order.quantity,
      price: order.dealtAvgPrice ?? order.price,
      status: order.status,
    });

    return c.json({ ok: true, order, action }, 201);
  } catch (error) {
    if (error instanceof MarketDataUnavailableError) {
      return c.json({ ok: false, error: error.message }, 503);
    }
    throw error;
  }
});
