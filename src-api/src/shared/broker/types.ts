export type BrokerProvider = 'futu';

export type BrokerEnvironment = 'SIMULATE' | 'REAL';

export type BrokerMarket = 'HK' | 'US' | 'CN';

export type TradeSide = 'BUY' | 'SELL';

export type OrderType = 'NORMAL' | 'MARKET' | 'ABSOLUTE_LIMIT';

export interface BrokerAccount {
  id: string;
  provider: BrokerProvider;
  name: string;
  environment: BrokerEnvironment;
  trdMarket: BrokerMarket;
  currency: string;
  totalAssets: number;
  cash: number;
  marketValue: number;
  dayPnl: number;
  dayPnlPercent: number;
  updatedAt: string;
}

export interface BrokerPosition {
  id: string;
  accountId: string;
  code: string;
  name: string;
  market: BrokerMarket;
  currency: string;
  quantity: number;
  availableQuantity: number;
  costPrice: number;
  lastPrice: number;
  marketValue: number;
  unrealizedPnl: number;
  unrealizedPnlPercent: number;
  dayChange: number;
  dayChangePercent: number;
}

export interface KlinePoint {
  time: string;
  open: number;
  high: number;
  low: number;
  close: number;
  volume: number;
}

export interface SubmitSimulatedOrderInput {
  accountId: string;
  code: string;
  side: TradeSide;
  orderType: OrderType;
  price: number;
  quantity: number;
  remark?: string;
}

export interface SimulatedOrder {
  id: string;
  accountId: string;
  code: string;
  side: TradeSide;
  orderType: OrderType;
  price: number;
  quantity: number;
  status: 'SUBMITTED' | 'FILLED' | 'REJECTED';
  trdEnv: BrokerEnvironment;
  submittedAt: string;
  filledAt?: string;
  dealtAvgPrice?: number;
  remark?: string;
}

export interface BrokerAdapter {
  listAccounts(): Promise<BrokerAccount[]>;
  listPositions(accountId?: string): Promise<BrokerPosition[]>;
  getKline(code: string, options?: { period?: string; count?: number }): Promise<KlinePoint[]>;
  submitSimulatedOrder(input: SubmitSimulatedOrderInput): Promise<SimulatedOrder>;
}
