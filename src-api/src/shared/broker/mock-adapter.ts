import type {
  BrokerAccount,
  BrokerAdapter,
  BrokerMarket,
  BrokerPosition,
  KlinePoint,
  ResolvedInstrument,
  SimulatedOrder,
  SubmitSimulatedOrderInput,
} from './types';

const nowIso = () => new Date().toISOString();

const mockAccount: BrokerAccount = {
  id: 'futu-sim-001',
  provider: 'futu',
  name: '富途模拟盘',
  environment: 'SIMULATE',
  trdMarket: 'HK',
  currency: 'HKD',
  totalAssets: 724_386.42,
  cash: 158_920.18,
  marketValue: 565_466.24,
  dayPnl: 4_826.31,
  dayPnlPercent: 0.67,
  updatedAt: nowIso(),
};

const mockPositions: BrokerPosition[] = [
  {
    id: 'pos-HK-00700',
    accountId: mockAccount.id,
    code: 'HK.00700',
    name: '腾讯控股',
    market: 'HK',
    currency: 'HKD',
    quantity: 600,
    availableQuantity: 600,
    costPrice: 371.2,
    lastPrice: 389.6,
    marketValue: 233_760,
    unrealizedPnl: 11_040,
    unrealizedPnlPercent: 4.96,
    dayChange: 3.8,
    dayChangePercent: 0.99,
  },
  {
    id: 'pos-HK-03690',
    accountId: mockAccount.id,
    code: 'HK.03690',
    name: '美团-W',
    market: 'HK',
    currency: 'HKD',
    quantity: 1_200,
    availableQuantity: 1_200,
    costPrice: 94.5,
    lastPrice: 91.85,
    marketValue: 110_220,
    unrealizedPnl: -3_180,
    unrealizedPnlPercent: -2.8,
    dayChange: -1.15,
    dayChangePercent: -1.24,
  },
  {
    id: 'pos-US-NVDA',
    accountId: mockAccount.id,
    code: 'US.NVDA',
    name: '英伟达',
    market: 'US',
    currency: 'USD',
    quantity: 80,
    availableQuantity: 80,
    costPrice: 136.4,
    lastPrice: 142.2,
    marketValue: 11_376,
    unrealizedPnl: 464,
    unrealizedPnlPercent: 4.25,
    dayChange: 1.9,
    dayChangePercent: 1.35,
  },
];

/**
 * 标的池：覆盖 demo 高频口述名。持仓里已有的标的不重复列入（resolveInstrument
 * 会先查持仓，命中后用真实成本/最新价）。价格为 mock 快照，接富途后由实时报价替换。
 */
const INSTRUMENT_UNIVERSE: ResolvedInstrument[] = [
  { code: 'CN.300750', name: '宁德时代', market: 'CN', currency: 'CNY', lastPrice: 245.6, lotSize: 100 },
  { code: 'CN.002594', name: '比亚迪', market: 'CN', currency: 'CNY', lastPrice: 248.3, lotSize: 100 },
  { code: 'CN.600519', name: '贵州茅台', market: 'CN', currency: 'CNY', lastPrice: 1486.0, lotSize: 100 },
  { code: 'CN.600036', name: '招商银行', market: 'CN', currency: 'CNY', lastPrice: 38.7, lotSize: 100 },
  { code: 'CN.601012', name: '隆基绿能', market: 'CN', currency: 'CNY', lastPrice: 15.4, lotSize: 100 },
  { code: 'HK.09988', name: '阿里巴巴', market: 'HK', currency: 'HKD', lastPrice: 82.4, lotSize: 100 },
  { code: 'HK.01810', name: '小米集团', market: 'HK', currency: 'HKD', lastPrice: 18.6, lotSize: 100 },
  { code: 'US.AAPL', name: '苹果', market: 'US', currency: 'USD', lastPrice: 226.1, lotSize: 1 },
  { code: 'US.TSLA', name: '特斯拉', market: 'US', currency: 'USD', lastPrice: 251.4, lotSize: 1 },
];

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

function positionToInstrument(position: BrokerPosition): ResolvedInstrument {
  return {
    code: position.code,
    name: position.name,
    market: position.market,
    currency: position.currency,
    lastPrice: position.lastPrice,
    lotSize: lotSizeForMarket(position.market),
  };
}

export class MockBrokerAdapter implements BrokerAdapter {
  async listAccounts(): Promise<BrokerAccount[]> {
    return [{ ...mockAccount, updatedAt: nowIso() }];
  }

  async listPositions(accountId = mockAccount.id): Promise<BrokerPosition[]> {
    return mockPositions.filter((position) => position.accountId === accountId);
  }

  async getQuote(code: string): Promise<number | null> {
    const held = mockPositions.find((position) => position.code === code);
    if (held) return held.lastPrice;
    const known = INSTRUMENT_UNIVERSE.find((item) => item.code === code);
    return known ? known.lastPrice : null;
  }

  async resolveInstrument(symbol: string): Promise<ResolvedInstrument | null> {
    const query = symbol.trim();
    if (!query) return null;

    const held = mockPositions.find((position) => nameMatches(query, position.name));
    if (held) return positionToInstrument(held);

    const known = INSTRUMENT_UNIVERSE.find((item) => nameMatches(query, item.name));
    return known ? { ...known } : null;
  }

  async getKline(code: string, options?: { period?: string; count?: number }): Promise<KlinePoint[]> {
    const position = mockPositions.find((item) => item.code === code);
    const count = Math.min(Math.max(options?.count ?? 60, 20), 120);
    const base = position?.lastPrice ?? 100;
    const points: KlinePoint[] = [];

    for (let index = count - 1; index >= 0; index -= 1) {
      const date = new Date();
      date.setDate(date.getDate() - index);
      const wave = Math.sin((count - index) / 5) * base * 0.018;
      const drift = (count - index) * base * 0.0009;
      const close = round2(base - count * base * 0.0005 + drift + wave);
      const open = round2(close * (1 + Math.sin(index) * 0.006));
      const high = round2(Math.max(open, close) * 1.012);
      const low = round2(Math.min(open, close) * 0.988);

      points.push({
        time: date.toISOString().slice(0, 10),
        open,
        high,
        low,
        close,
        volume: Math.round(800_000 + Math.abs(Math.sin(index / 3)) * 2_400_000),
      });
    }

    return points;
  }

  async submitSimulatedOrder(input: SubmitSimulatedOrderInput): Promise<SimulatedOrder> {
    return {
      id: `futu-sim-order-${Date.now()}`,
      accountId: input.accountId,
      code: input.code,
      side: input.side,
      orderType: input.orderType,
      price: input.price,
      quantity: input.quantity,
      status: 'FILLED',
      trdEnv: 'SIMULATE',
      submittedAt: nowIso(),
      filledAt: nowIso(),
      dealtAvgPrice: input.price,
      remark: input.remark,
    };
  }
}

function round2(value: number): number {
  return Math.round(value * 100) / 100;
}
