import type {
  BrokerAccount,
  BrokerAdapter,
  BrokerMarket,
  BrokerPosition,
  KlinePoint,
  QuoteSnapshot,
  ResolvedInstrument,
  SimulatedOrder,
  SubmitSimulatedOrderInput,
} from './types';
import { MarketDataUnavailableError } from './market-data-error';
import { WestockMarketClient } from '@/shared/market/westock-client';

const nowIso = () => new Date().toISOString();

const mockAccount: BrokerAccount = {
  id: 'futu-sim-001',
  provider: 'futu',
  name: '富途模拟盘',
  environment: 'SIMULATE',
  trdMarket: 'HK',
  currency: 'HKD',
  totalAssets: 1_426_812.56,
  cash: 218_920.18,
  marketValue: 1_207_892.38,
  dayPnl: 8_326.31,
  dayPnlPercent: 0.59,
  updatedAt: nowIso(),
};

/** 模拟持仓：数量/成本/账户汇总为 mock；展示价与成交由 westock 提供。 */
const mockPositions: BrokerPosition[] = [
  {
    id: 'pos-CN-300750',
    accountId: mockAccount.id,
    code: 'CN.300750',
    name: '宁德时代',
    market: 'CN',
    currency: 'CNY',
    quantity: 500,
    availableQuantity: 500,
    costPrice: 214.8,
    lastPrice: 245.6,
    marketValue: 122_800,
    unrealizedPnl: 15_400,
    unrealizedPnlPercent: 14.34,
    dayChange: 4.2,
    dayChangePercent: 1.74,
  },
  {
    id: 'pos-CN-002594',
    accountId: mockAccount.id,
    code: 'CN.002594',
    name: '比亚迪',
    market: 'CN',
    currency: 'CNY',
    quantity: 800,
    availableQuantity: 800,
    costPrice: 266.4,
    lastPrice: 248.3,
    marketValue: 198_640,
    unrealizedPnl: -14_480,
    unrealizedPnlPercent: -6.79,
    dayChange: -2.8,
    dayChangePercent: -1.11,
  },
  {
    id: 'pos-CN-600519',
    accountId: mockAccount.id,
    code: 'CN.600519',
    name: '贵州茅台',
    market: 'CN',
    currency: 'CNY',
    quantity: 100,
    availableQuantity: 100,
    costPrice: 1392,
    lastPrice: 1486,
    marketValue: 148_600,
    unrealizedPnl: 9_400,
    unrealizedPnlPercent: 6.75,
    dayChange: 18.2,
    dayChangePercent: 1.24,
  },
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
    id: 'pos-HK-09988',
    accountId: mockAccount.id,
    code: 'HK.09988',
    name: '阿里巴巴-W',
    market: 'HK',
    currency: 'HKD',
    quantity: 2_000,
    availableQuantity: 2_000,
    costPrice: 78.1,
    lastPrice: 82.4,
    marketValue: 164_800,
    unrealizedPnl: 8_600,
    unrealizedPnlPercent: 5.51,
    dayChange: 0.9,
    dayChangePercent: 1.1,
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
  {
    id: 'pos-US-AAPL',
    accountId: mockAccount.id,
    code: 'US.AAPL',
    name: '苹果',
    market: 'US',
    currency: 'USD',
    quantity: 60,
    availableQuantity: 60,
    costPrice: 232.5,
    lastPrice: 226.1,
    marketValue: 13_566,
    unrealizedPnl: -384,
    unrealizedPnlPercent: -2.75,
    dayChange: -1.6,
    dayChangePercent: -0.7,
  },
  {
    id: 'pos-US-TSLA',
    accountId: mockAccount.id,
    code: 'US.TSLA',
    name: '特斯拉',
    market: 'US',
    currency: 'USD',
    quantity: 40,
    availableQuantity: 40,
    costPrice: 219.7,
    lastPrice: 251.4,
    marketValue: 10_056,
    unrealizedPnl: 1_268,
    unrealizedPnlPercent: 14.43,
    dayChange: 5.1,
    dayChangePercent: 2.07,
  },
];

function lotSizeForMarket(market: BrokerMarket): number {
  return market === 'US' ? 1 : 100;
}

function nameMatches(symbol: string, candidate: string): boolean {
  const a = symbol.trim();
  const b = candidate.trim();
  if (!a || !b) return false;
  return a.includes(b) || b.includes(a);
}

function positionToInstrument(position: BrokerPosition, lastPrice: number): ResolvedInstrument {
  return {
    code: position.code,
    name: position.name,
    market: position.market,
    currency: position.currency,
    lastPrice,
    lotSize: lotSizeForMarket(position.market),
  };
}

function requireWestock(): WestockMarketClient {
  const client = new WestockMarketClient();
  if (!client.configured) {
    throw new MarketDataUnavailableError('WESTOCK_API_KEY 未配置，无法获取行情');
  }
  return client;
}

export class MockBrokerAdapter implements BrokerAdapter {
  private readonly westock = new WestockMarketClient();

  async listAccounts(): Promise<BrokerAccount[]> {
    return [{ ...mockAccount, updatedAt: nowIso() }];
  }

  async listPositions(accountId = mockAccount.id): Promise<BrokerPosition[]> {
    return mockPositions.filter((position) => position.accountId === accountId);
  }

  async getQuote(code: string): Promise<number | null> {
    const snapshot = await this.getQuoteSnapshot(code).catch(() => null);
    return snapshot?.lastPrice ?? null;
  }

  async getQuoteSnapshot(code: string): Promise<QuoteSnapshot | null> {
    if (!this.westock.configured) return null;
    return this.westock.getQuoteSnapshot(code).catch(() => null);
  }

  async resolveInstrument(symbol: string): Promise<ResolvedInstrument | null> {
    const query = symbol.trim();
    if (!query) return null;

    const held = mockPositions.find((position) => nameMatches(query, position.name));
    if (held) {
      const snapshot = await this.getQuoteSnapshot(held.code);
      if (snapshot) return positionToInstrument(held, snapshot.lastPrice);
      return null;
    }

    return this.westock.searchInstrument(query).catch(() => null);
  }

  async getKline(code: string, options?: { period?: string; count?: number }): Promise<KlinePoint[]> {
    const count = Math.min(Math.max(options?.count ?? 60, 20), 120);
    const client = requireWestock();
    const westockKline = await client.getKline(code, count);
    if (westockKline && westockKline.length > 0) return westockKline;
    throw new MarketDataUnavailableError(`暂无 ${code} 的 K 线行情`);
  }

  async submitSimulatedOrder(input: SubmitSimulatedOrderInput): Promise<SimulatedOrder> {
    const executionPrice = await this.getQuote(input.code);
    if (executionPrice == null) {
      throw new MarketDataUnavailableError(`无法获取 ${input.code} 的实时成交价`);
    }

    return {
      id: `futu-sim-order-${Date.now()}`,
      accountId: input.accountId,
      code: input.code,
      side: input.side,
      orderType: input.orderType,
      price: executionPrice,
      quantity: input.quantity,
      status: 'FILLED',
      trdEnv: 'SIMULATE',
      submittedAt: nowIso(),
      filledAt: nowIso(),
      dealtAvgPrice: executionPrice,
      remark: input.remark,
    };
  }
}
