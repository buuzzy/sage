/**
 * 订单草稿生成：把「标的名 + 操作意图」翻译成可提交的模拟盘订单草稿（富途 OpenAPI 语义）。
 *
 * 解析顺序：① 命中当前持仓（用真实成本/最新价）② 命中内置标的字典 ③ 占位兜底。
 * 草稿只是「建议」，用户在 Step2 可改方向/价格/数量。当前数据为富途语义 mock，
 * 接真实模拟盘时只需替换 broker adapter，本服务的 contract 不变。
 */

import { getBrokerAdapter } from '@/shared/broker';
import type { BrokerMarket, BrokerPosition, OrderType, TradeSide } from '@/shared/broker';

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

interface Instrument {
  code: string;
  name: string;
  market: BrokerMarket;
  currency: string;
  lastPrice: number;
  lotSize: number;
}

/** 内置常见标的字典：覆盖 demo 高频口述名，命中后给可信报价。 */
const INSTRUMENTS: Instrument[] = [
  { code: 'CN.300750', name: '宁德时代', market: 'CN', currency: 'CNY', lastPrice: 245.6, lotSize: 100 },
  { code: 'CN.002594', name: '比亚迪', market: 'CN', currency: 'CNY', lastPrice: 248.3, lotSize: 100 },
  { code: 'CN.600519', name: '贵州茅台', market: 'CN', currency: 'CNY', lastPrice: 1486.0, lotSize: 100 },
  { code: 'CN.600036', name: '招商银行', market: 'CN', currency: 'CNY', lastPrice: 38.7, lotSize: 100 },
  { code: 'CN.601012', name: '隆基绿能', market: 'CN', currency: 'CNY', lastPrice: 15.4, lotSize: 100 },
  { code: 'HK.00700', name: '腾讯控股', market: 'HK', currency: 'HKD', lastPrice: 389.6, lotSize: 100 },
  { code: 'HK.03690', name: '美团', market: 'HK', currency: 'HKD', lastPrice: 91.85, lotSize: 100 },
  { code: 'HK.09988', name: '阿里巴巴', market: 'HK', currency: 'HKD', lastPrice: 82.4, lotSize: 100 },
  { code: 'HK.01810', name: '小米集团', market: 'HK', currency: 'HKD', lastPrice: 18.6, lotSize: 100 },
  { code: 'US.NVDA', name: '英伟达', market: 'US', currency: 'USD', lastPrice: 142.2, lotSize: 1 },
  { code: 'US.AAPL', name: '苹果', market: 'US', currency: 'USD', lastPrice: 226.1, lotSize: 1 },
  { code: 'US.TSLA', name: '特斯拉', market: 'US', currency: 'USD', lastPrice: 251.4, lotSize: 1 },
];

const BUY_INTENTS = ['加仓', '买入', '补仓', '建仓', '加'];
const SELL_INTENTS = ['减仓', '止盈', '止损', '卖出', '清仓', '减', '卖'];

function sideFromIntent(intent: string): TradeSide {
  const text = intent.trim();
  if (SELL_INTENTS.some((kw) => text.includes(kw))) return 'SELL';
  return 'BUY';
}

function lotSizeForMarket(market: BrokerMarket): number {
  return market === 'US' ? 1 : 100;
}

/** 名称模糊匹配：双向 includes，兼容「腾讯」↔「腾讯控股」「美团」↔「美团-W」。 */
function nameMatches(symbol: string, candidate: string): boolean {
  const a = symbol.trim();
  const b = candidate.trim();
  if (!a || !b) return false;
  return a.includes(b) || b.includes(a);
}

function resolveInstrument(symbol: string, positions: BrokerPosition[]): Instrument {
  const held = positions.find((position) => nameMatches(symbol, position.name));
  if (held) {
    return {
      code: held.code,
      name: held.name,
      market: held.market,
      currency: held.currency,
      lastPrice: held.lastPrice,
      lotSize: lotSizeForMarket(held.market),
    };
  }

  const known = INSTRUMENTS.find((item) => nameMatches(symbol, item.name));
  if (known) return known;

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

  const instrument = resolveInstrument(input.symbol, positions);
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
    const lots = Math.max(1, Math.floor(budget / (instrument.lastPrice * lot)));
    quantity = lots * lot;
    rationale = `按约 10% 可用资金估算 ${quantity} 股，价格用最新价，可手动调整`;
  }

  if (instrument.code === 'CN.000000') {
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
    price: instrument.lastPrice,
    quantity,
    lotSize: lot,
    environment: 'SIMULATE',
    rationale,
  };
}
