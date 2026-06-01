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

/**
 * 标的解析结果：把口述名称（「比亚迪」）映射到可交易/可报价的合约身份。
 * 价格只是当前快照，真实下单 / 监控时应再通过 getQuote 取最新价。
 */
export interface ResolvedInstrument {
  code: string;
  name: string;
  market: BrokerMarket;
  currency: string;
  lastPrice: number;
  lotSize: number;
}

export interface BrokerAdapter {
  listAccounts(): Promise<BrokerAccount[]>;
  listPositions(accountId?: string): Promise<BrokerPosition[]>;
  getKline(code: string, options?: { period?: string; count?: number }): Promise<KlinePoint[]>;
  submitSimulatedOrder(input: SubmitSimulatedOrderInput): Promise<SimulatedOrder>;
  /** 取某合约当前价（富途实时报价语义）。未知合约返回 null。 */
  getQuote(code: string): Promise<number | null>;
  /** 把口述名称解析成合约身份（命中持仓优先，其次标的池）。无法识别返回 null。 */
  resolveInstrument(symbol: string): Promise<ResolvedInstrument | null>;
}
