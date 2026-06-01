import type {
  BrokerAccount,
  BrokerAdapter,
  BrokerPosition,
  KlinePoint,
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

export class MockBrokerAdapter implements BrokerAdapter {
  async listAccounts(): Promise<BrokerAccount[]> {
    return [{ ...mockAccount, updatedAt: nowIso() }];
  }

  async listPositions(accountId = mockAccount.id): Promise<BrokerPosition[]> {
    return mockPositions.filter((position) => position.accountId === accountId);
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
