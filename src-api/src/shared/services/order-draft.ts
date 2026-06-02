/**
 * 订单草稿生成：把「标的名 + 操作意图」翻译成可提交的模拟盘订单草稿（富途 OpenAPI 语义）。
 *
 * 标的身份由 mock 持仓 + westock 搜索解析；成交价用 westock 实时价。
 * 草稿只是「建议」，用户在 Step2 可改方向/数量；提交时按最新 westock 价成交。
 */

import { getBrokerAdapter } from '@/shared/broker';
import { MarketDataUnavailableError } from '@/shared/broker/market-data-error';
import type { BrokerMarket, OrderType, TradeSide } from '@/shared/broker';

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

export async function buildOrderDraft(input: { symbol: string; intent: string }): Promise<OrderDraft> {
  const adapter = getBrokerAdapter();
  const [account] = await adapter.listAccounts();
  const positions = await adapter.listPositions(account.id);

  const resolved = await adapter.resolveInstrument(input.symbol);
  if (!resolved) {
    throw new MarketDataUnavailableError(`无法识别标的「${input.symbol}」，请核对名称或代码`);
  }
  const instrument = resolved;

  const quote = await adapter.getQuote(instrument.code);
  if (quote == null) {
    throw new MarketDataUnavailableError(`无法获取 ${instrument.name} 的实时行情`);
  }
  const price = quote;

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
    rationale = `按约 10% 模拟可用资金估算 ${quantity} 股，价格为 westock 实时价；提交时按最新价成交`;
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
