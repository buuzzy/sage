import { getBrokerAdapter } from '@/shared/broker';
import type { BrokerAccount, BrokerPosition } from '@/shared/broker';

export interface MobileDashboard {
  connected: boolean;
  account: BrokerAccount;
  todayPoints: TodayPoint[];
  positions: HoldingSummary[];
  walkiePrompt: string;
  updatedAt: string;
}

export interface TodayPoint {
  id: string;
  tone: 'positive' | 'warning' | 'neutral';
  title: string;
  body: string;
  relatedCode?: string;
}

export interface HoldingSummary extends BrokerPosition {
  attention: string;
}

export async function getMobileDashboard(): Promise<MobileDashboard> {
  const broker = getBrokerAdapter();
  const [account] = await broker.listAccounts();
  if (!account) {
    throw new Error('No broker account available');
  }

  const positions = await broker.listPositions(account.id);
  const sortedPositions = [...positions].sort(
    (left, right) => Math.abs(right.marketValue) - Math.abs(left.marketValue)
  );

  return {
    connected: true,
    account,
    todayPoints: buildTodayPoints(account, sortedPositions),
    positions: sortedPositions.map(toHoldingSummary),
    walkiePrompt: '记录一个想法',
    updatedAt: new Date().toISOString(),
  };
}

function buildTodayPoints(account: BrokerAccount, positions: BrokerPosition[]): TodayPoint[] {
  const largestWinner = positions
    .filter((position) => position.dayChangePercent > 0)
    .sort((left, right) => right.dayChangePercent - left.dayChangePercent)[0];
  const largestLoser = positions
    .filter((position) => position.dayChangePercent < 0)
    .sort((left, right) => left.dayChangePercent - right.dayChangePercent)[0];

  const points: TodayPoint[] = [
    {
      id: 'asset-pnl',
      tone: account.dayPnl >= 0 ? 'positive' : 'warning',
      title: account.dayPnl >= 0 ? '资产小幅走强' : '资产承压',
      body: `今日盈亏 ${formatSignedMoney(account.dayPnl, account.currency)}，主要由持仓波动贡献。`,
    },
  ];

  if (largestWinner) {
    points.push({
      id: `winner-${largestWinner.code}`,
      tone: 'positive',
      title: `${largestWinner.name} 贡献领先`,
      body: `今日上涨 ${formatPercent(largestWinner.dayChangePercent)}，可在详情页检查是否接近计划价。`,
      relatedCode: largestWinner.code,
    });
  }

  if (largestLoser) {
    points.push({
      id: `loser-${largestLoser.code}`,
      tone: 'warning',
      title: `${largestLoser.name} 需要关注`,
      body: `今日下跌 ${formatPercent(largestLoser.dayChangePercent)}，建议确认是否仍符合原持仓逻辑。`,
      relatedCode: largestLoser.code,
    });
  }

  return points.slice(0, 3);
}

function toHoldingSummary(position: BrokerPosition): HoldingSummary {
  const attention = position.unrealizedPnlPercent >= 4
    ? '浮盈扩大，关注是否接近目标价'
    : position.unrealizedPnlPercent <= -3
      ? '接近风险区，检查止损计划'
      : '持仓状态稳定';
  return { ...position, attention };
}

function formatSignedMoney(value: number, currency: string): string {
  const sign = value >= 0 ? '+' : '-';
  return `${sign}${currency} ${Math.abs(value).toLocaleString('en-US', {
    maximumFractionDigits: 2,
  })}`;
}

function formatPercent(value: number): string {
  const sign = value >= 0 ? '+' : '';
  return `${sign}${value.toFixed(2)}%`;
}
