import { getBrokerAdapter } from '@/shared/broker';
import type { BrokerAccount, BrokerPosition, QuoteSnapshot } from '@/shared/broker';
import { WestockMarketClient, type MarketNewsItem } from '@/shared/market/westock-client';

export interface MobileDashboard {
  connected: boolean;
  account: BrokerAccount;
  assetTrend: AssetTrendPoint[];
  todayPoints: TodayPoint[];
  positions: HoldingSummary[];
  walkiePrompt: string;
  updatedAt: string;
}

export interface AssetTrendPoint {
  time: string;
  value: number;
}

export interface TodayPoint {
  id: string;
  tone: 'positive' | 'warning' | 'neutral';
  title: string;
  body: string;
  relatedCode?: string;
  relatedName?: string;
  newsTitle?: string;
  newsSource?: string;
  newsDate?: string;
  newsSummary?: string;
  newsUrl?: string;
}

export interface HoldingDetailPoint {
  title: string;
  body: string;
}

export interface HoldingSummary extends BrokerPosition {
  attention: string;
  detailPoints: HoldingDetailPoint[];
  quoteSnapshot?: QuoteSnapshot | null;
}

export async function getMobileDashboard(): Promise<MobileDashboard> {
  const broker = getBrokerAdapter();
  const market = new WestockMarketClient();
  const [account] = await broker.listAccounts();
  if (!account) {
    throw new Error('No broker account available');
  }

  const positions = await broker.listPositions(account.id);
  const enriched = await Promise.all(positions.map((position) => enrichPosition(broker, position)));
  const sortedPositions = [...enriched].sort(
    (left, right) => Math.abs(right.marketValue) - Math.abs(left.marketValue)
  );

  const refreshedAccount = rebuildAccountFromPositions(account, sortedPositions);

  return {
    connected: true,
    account: refreshedAccount,
    assetTrend: buildAssetTrend(refreshedAccount, sortedPositions),
    todayPoints: await buildTodayPoints(sortedPositions, market),
    positions: sortedPositions,
    walkiePrompt: '记录一个想法',
    updatedAt: new Date().toISOString(),
  };
}

function rebuildAccountFromPositions(account: BrokerAccount, positions: HoldingSummary[]): BrokerAccount {
  const marketValue = round2(
    positions.reduce((sum, position) => sum + convertCurrency(position.marketValue, position.currency, account.currency), 0)
  );
  const dayPnl = round2(
    positions.reduce(
      (sum, position) => sum + convertCurrency(position.dayChange * position.quantity, position.currency, account.currency),
      0
    )
  );
  const totalAssets = round2(account.cash + marketValue);
  const dayPnlBase = totalAssets - dayPnl;
  return {
    ...account,
    marketValue,
    totalAssets,
    dayPnl,
    dayPnlPercent: dayPnlBase > 0 ? round2((dayPnl / dayPnlBase) * 100) : 0,
    updatedAt: new Date().toISOString(),
  };
}

function convertCurrency(value: number, from: string, to: string): number {
  if (from === to) return value;
  const hkdPerUnit: Record<string, number> = { HKD: 1, USD: 7.82, CNY: 1.08 };
  return (value * (hkdPerUnit[from] ?? 1)) / (hkdPerUnit[to] ?? 1);
}

async function enrichPosition(
  broker: ReturnType<typeof getBrokerAdapter>,
  position: BrokerPosition
): Promise<HoldingSummary> {
  const snapshot = await broker.getQuoteSnapshot(position.code);
  if (!snapshot) {
    return {
      ...position,
      attention: '行情暂不可用，数量与成本仍为模拟数据',
      detailPoints: buildDetailPoints(position, null),
    quoteSnapshot: null,
    };
  }

  const lastPrice = round2(snapshot.lastPrice);
  const marketValue = round2(lastPrice * position.quantity);
  const unrealizedPnl = round2((lastPrice - position.costPrice) * position.quantity);
  const unrealizedPnlPercent =
    position.costPrice > 0 ? round2(((lastPrice - position.costPrice) / position.costPrice) * 100) : 0;

  const enriched: BrokerPosition = {
    ...position,
    lastPrice,
    marketValue,
    unrealizedPnl,
    unrealizedPnlPercent,
    dayChange: round2(snapshot.change),
    dayChangePercent: round2(snapshot.changePercent),
  };

  return {
    ...enriched,
    attention: buildAttention(enriched),
    detailPoints: buildDetailPoints(enriched, snapshot),
    quoteSnapshot: snapshot,
  };
}

async function buildTodayPoints(positions: HoldingSummary[], market: WestockMarketClient): Promise<TodayPoint[]> {
  const focusPositions = positions
    .filter((position) => Math.abs(position.marketValue) > 0)
    .slice(0, 9);

  const newsByCode = await Promise.all(
    focusPositions.map(async (position) => ({
      position,
      news: await market.getMarketNews(position.code, 2).catch(() => []),
    }))
  );

  const points = newsByCode
    .map(({ position, news }) => {
      const latest = latestRecentNews(news);
      if (!latest) return null;
      return buildNewsPoint(position, latest);
    })
    .filter((point): point is TodayPoint => point !== null);

  if (points.length > 0) return points.slice(0, 6);

  return focusPositions.slice(0, 3).map((position) => ({
    id: `holding-${position.code}`,
    tone: position.dayChangePercent >= 0 ? 'positive' : position.dayChangePercent < -1 ? 'warning' : 'neutral',
    title: position.name,
    body: `${position.name} 今日 ${formatPercent(position.dayChangePercent)}，资讯 skill 暂无最近内容，先关注价格与持仓成本关系。`,
    relatedCode: position.code,
    relatedName: position.name,
  }));
}

function buildNewsPoint(position: HoldingSummary, news: MarketNewsItem): TodayPoint {
  return {
    id: `holding-${position.code}-${news.date ?? news.title}`,
    tone: position.dayChangePercent >= 0 ? 'positive' : position.dayChangePercent < -1 ? 'warning' : 'neutral',
    title: position.name,
    body: news.title,
    relatedCode: position.code,
    relatedName: position.name,
    newsTitle: news.title,
    newsSource: news.source,
    newsDate: news.date,
    newsSummary: news.summary,
    newsUrl: news.url,
  };
}

function buildAssetTrend(account: BrokerAccount, positions: HoldingSummary[]): AssetTrendPoint[] {
  const currentTotal = account.totalAssets;
  const currentMarketValue = positions.reduce((sum, position) => sum + position.marketValue, 0);
  const previousMarketValue = positions.reduce((sum, position) => {
    const prevClose = position.quoteSnapshot?.prevClose;
    if (prevClose && prevClose > 0) return sum + prevClose * position.quantity;
    return sum + (position.marketValue - position.dayChange * position.quantity);
  }, 0);
  const dayDelta = currentMarketValue - previousMarketValue || account.dayPnl;
  const openTotal = currentTotal - dayDelta;
  const checkpoints = [0, 0.18, 0.12, 0.38, 0.31, 0.56, 0.49, 0.72, 0.66, 0.88, 1];
  return checkpoints.map((progress, index) => ({
    time: `T${index}`,
    value: round2(openTotal + dayDelta * progress),
  }));
}

function latestRecentNews(news: MarketNewsItem[]): MarketNewsItem | null {
  const cutoff = Date.now() - 2 * 24 * 60 * 60 * 1000;
  return (
    news.find((item) => {
      const time = parseNewsTime(item.date);
      return time == null || time >= cutoff;
    }) ??
    news[0] ??
    null
  );
}

function parseNewsTime(value?: string): number | null {
  if (!value) return null;
  const normalized = value.replace(/\//g, '-');
  const parsed = Date.parse(normalized);
  return Number.isFinite(parsed) ? parsed : null;
}

function buildAttention(position: BrokerPosition): string {
  if (position.unrealizedPnlPercent >= 4) {
    return '浮盈扩大，关注是否接近目标价';
  }
  if (position.unrealizedPnlPercent <= -3) {
    return '接近风险区，检查止损计划';
  }
  if (Math.abs(position.dayChangePercent) >= 2) {
    return position.dayChangePercent > 0 ? '今日波动偏大，留意追涨风险' : '今日波动偏大，留意加仓节奏';
  }
  return '持仓状态稳定';
}

function buildDetailPoints(position: BrokerPosition, snapshot: QuoteSnapshot | null): HoldingDetailPoint[] {
  if (!snapshot) {
    return [
      {
        title: '行情',
        body: '行情 skill 暂不可用，展示价为 mock 快照，数量与成本仍为模拟持仓。',
      },
      {
        title: '模拟持仓',
        body: `持仓 ${formatQuantity(position.quantity)} 股，成本 ${formatPrice(position.costPrice, position.currency)}。`,
      },
    ];
  }

  const asOf = snapshot.endDate ? `（截至 ${snapshot.endDate}）` : '';
  return [
    {
      title: '实时行情',
      body: `最新价 ${formatPrice(snapshot.lastPrice, position.currency)}，今日 ${formatSignedChange(snapshot.change, position.currency)} / ${formatPercent(snapshot.changePercent)}${asOf}。`,
    },
    {
      title: '模拟持仓',
      body: `持仓 ${formatQuantity(position.quantity)} 股，成本 ${formatPrice(position.costPrice, position.currency)}，浮盈 ${formatSignedMoney(position.unrealizedPnl, position.currency)}（${formatPercent(position.unrealizedPnlPercent)}）。`,
    },
    {
      title: '关注提示',
      body: buildAttention(position),
    },
  ];
}

function formatSignedMoney(value: number, currency: string): string {
  const sign = value >= 0 ? '+' : '-';
  return `${sign}${currency} ${Math.abs(value).toLocaleString('en-US', {
    maximumFractionDigits: 2,
  })}`;
}

function formatSignedChange(value: number, currency: string): string {
  const sign = value >= 0 ? '+' : '-';
  return `${sign}${currency} ${Math.abs(value).toFixed(2)}`;
}

function formatPrice(value: number, currency: string): string {
  return `${currency} ${value.toLocaleString('en-US', { maximumFractionDigits: 2 })}`;
}

function formatQuantity(value: number): string {
  return value.toLocaleString('en-US', { maximumFractionDigits: 0 });
}

function formatPercent(value: number): string {
  const sign = value >= 0 ? '+' : '';
  return `${sign}${value.toFixed(2)}%`;
}

function round2(value: number): number {
  return Math.round(value * 100) / 100;
}
