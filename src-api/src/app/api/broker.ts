import { Hono } from 'hono';

import { getBrokerAdapter } from '@/shared/broker';
import { MarketDataUnavailableError } from '@/shared/broker/market-data-error';
import type { OrderType, TradeSide } from '@/shared/broker';

export const brokerRoutes = new Hono();

const tradeSides = new Set<TradeSide>(['BUY', 'SELL']);
const orderTypes = new Set<OrderType>(['NORMAL', 'MARKET', 'ABSOLUTE_LIMIT']);

brokerRoutes.get('/accounts', async (c) => {
  const accounts = await getBrokerAdapter().listAccounts();
  return c.json({ ok: true, accounts });
});

brokerRoutes.get('/positions', async (c) => {
  const accountId = c.req.query('accountId');
  const positions = await getBrokerAdapter().listPositions(accountId);
  return c.json({ ok: true, positions });
});

brokerRoutes.get('/positions/:code/kline', async (c) => {
  const code = decodeURIComponent(c.req.param('code'));
  const period = c.req.query('period') ?? 'day';
  const count = Number(c.req.query('count') ?? 60);
  try {
    const kline = await getBrokerAdapter().getKline(code, { period, count });
    return c.json({ ok: true, code, period, kline });
  } catch (error) {
    if (error instanceof MarketDataUnavailableError) {
      return c.json({ ok: false, error: error.message }, 503);
    }
    throw error;
  }
});

brokerRoutes.post('/orders/simulated', async (c) => {
  const body = await c.req.json<Partial<{
    accountId: string;
    code: string;
    side: TradeSide;
    orderType: OrderType;
    price: number;
    quantity: number;
    remark: string;
  }>>();

  if (!body.accountId || !body.code) {
    return c.json({ ok: false, error: 'accountId and code are required' }, 400);
  }
  if (!body.side || !tradeSides.has(body.side)) {
    return c.json({ ok: false, error: 'side must be BUY or SELL' }, 400);
  }
  if (!body.orderType || !orderTypes.has(body.orderType)) {
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
      remark: body.remark,
    });
    return c.json({ ok: true, order }, 201);
  } catch (error) {
    if (error instanceof MarketDataUnavailableError) {
      return c.json({ ok: false, error: error.message }, 503);
    }
    throw error;
  }
});
