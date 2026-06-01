/**
 * 订单草稿生成：把「标的名 + 操作意图」翻译成可提交的模拟盘订单草稿（富途 OpenAPI 语义）。
 *
 * 标的身份 + 报价统一由 broker adapter 提供（命中持仓优先，其次标的池，兜底占位）。
 * 草稿只是「建议」，用户在 Step2 可改方向/价格/数量。当前数据为富途语义 mock，
 * 接真实模拟盘时只需替换 broker adapter，本服务的 contract 不变。
 */

import { getBrokerAdapter } from '@/shared/broker';
import type { BrokerMarket, OrderType, ResolvedInstrument, TradeSide } from '@/shared/broker';

export interface OrderDraft {
  accountId: string;
  code: string;
  name: string;
  market: BrokerMarket;
  currency: string;
  side: TradeSide;
  orderType: OrderType;
  price: number;
  quantity: number;
  lotSize: number;
  environment: 'SIMULATE';
  rationale: string;
}

const BUY_INTENTS = ['加仓', '买入', '补仓', '建仓', '加'];
const SELL_INTENTS = ['减仓', '止盈', '止损', '卖出', '清仓', '减', '卖'];

function sideFromIntent(intent: string): TradeSide {
  const text = intent.trim();
  if (SELL_INTENTS.some((kw) => text.includes(kw))) return 'SELL';
  return 'BUY';
}

/** broker 无法识别标的时的占位身份，保证下游表单仍可渲染并提示用户核对。 */
function placeholderInstrument(symbol: string): ResolvedInstrument {
  return {
    code: 'CN.000000',
    name: symbol.trim() || '待确认标的',
    market: 'CN',
    currency: 'CNY',
    lastPrice: 100,
    lotSize: 100,
  };
}

export async function buildOrderDraft(input: { symbol: string; intent: string }): Promise<OrderDraft> {
  const adapter = getBrokerAdapter();
  const [account] = await adapter.listAccounts();
  const positions = await adapter.listPositions(account.id);

  const resolved = await adapter.resolveInstrument(input.symbol);
  const instrument = resolved ?? placeholderInstrument(input.symbol);
  const isPlaceholder = !resolved;

  // 实时报价覆盖快照价（mock 下二者一致；接富途后取最新价）。
  const quote = isPlaceholder ? null : await adapter.getQuote(instrument.code);
  const price = quote ?? instrument.lastPrice;

  const side = sideFromIntent(input.intent);
  const lot = instrument.lotSize;

  let quantity: number;
  let rationale: string;

  if (side === 'SELL') {
    const held = positions.find((position) => position.code === instrument.code);
    if (held && held.availableQuantity > 0) {
      quantity = Math.max(lot, Math.floor(held.availableQuantity / lot) * lot);
      rationale = `按持仓可卖 ${held.availableQuantity} 股给出${input.intent || '卖出'}草稿，可手动调整数量`;
    } else {
      quantity = lot;
      rationale = '未匹配到对应持仓，按 1 手给出占位草稿，提交前请在富途核对';
    }
  } else {
    const budget = account.cash * 0.1;
    const lots = Math.max(1, Math.floor(budget / (price * lot)));
    quantity = lots * lot;
    rationale = `按约 10% 可用资金估算 ${quantity} 股，价格用最新价，可手动调整`;
  }

  if (isPlaceholder) {
    rationale = '未匹配到行情，已用占位价 100，提交前请在富途核对标的与价格';
  }

  return {
    accountId: account.id,
    code: instrument.code,
    name: instrument.name,
    market: instrument.market,
    currency: instrument.currency,
    side,
    orderType: 'NORMAL',
    price,
    quantity,
    lotSize: lot,
    environment: 'SIMULATE',
    rationale,
  };
}
