import { getBrokerAdapter } from '@/shared/broker';
import type { BrokerAccount, BrokerPosition, QuoteSnapshot } from '@/shared/broker';
import { WestockMarketClient } from '@/shared/market/westock-client';
import type { MarketNewsItem, MarketResearchReport } from '@/shared/market/westock-client';
import { callDeepSeekJson } from '@/shared/services/deepseek-json';
import { buildOrderDraft } from '@/shared/services/order-draft';
import type { OrderDraft } from '@/shared/services/order-draft';
import type { IdeaAnalysis } from '@/shared/services/idea-analysis';
import type { IdeaNote } from '@/shared/services/mobile-actions';

export type OrderAnalysisStep =
  | 'resolving_symbol'
  | 'loading_quote'
  | 'loading_account'
  | 'loading_research'
  | 'loading_news'
  | 'synthesizing';

export interface OrderAnalysisProgress {
  step: OrderAnalysisStep;
  message: string;
  status?: 'running' | 'done' | 'skipped';
}

export interface OrderAnalysis {
  title: string;
  summary: string;
  bullets: string[];
  risks: string[];
  sources: string[];
  generatedAt: string;
}

export interface CachedOrderIdeaAnalysis extends IdeaAnalysis {
  orderAnalysis?: OrderAnalysis;
}

type ProgressSink = (progress: OrderAnalysisProgress) => void;

interface HtscReport {
  title: string;
  author?: string;
  date?: string;
  summary?: string;
}

interface HtscResponse {
  code?: string;
  msg?: string;
  resultData?: Array<{
    showTitle?: unknown;
    authorNames?: unknown;
    summay?: unknown;
    pubdate?: unknown;
  }>;
}

interface AnalysisContext {
  note: IdeaNote;
  draft: OrderDraft;
  account: BrokerAccount;
  position: BrokerPosition | null;
  quote: QuoteSnapshot | null;
  klineChangePercent: number | null;
  htscReports: HtscReport[];
  westockReports: MarketResearchReport[];
  news: MarketNewsItem[];
}

const SYSTEM_PROMPT =
  '你是 Sage 的投资标的分析模块。用户准备下单前，你需要把资金情况、持仓、实时行情、研报/资讯整合成一张克制的中文分析卡。' +
  '只返回 JSON：{"title":"","summary":"","bullets":[""],"risks":[""],"sources":[""]}。\n' +
  'title：≤32字，明确标的和态度，不喊单。\n' +
  'summary：一段 120-180 字，必须结合用户现金/仓位、订单方向与数量、当前行情和研报/资讯。如果研报缺失，要说明只基于行情与账户上下文。\n' +
  'bullets：2-4 条，每条 ≤32 字，给出关键依据。\n' +
  'risks：1-3 条，每条 ≤32 字。\n' +
  'sources：列出实际使用的数据源，但只能使用通用名称，如“行情 skill”“研报 skill”“资讯 skill”“模拟账户/持仓”，禁止暴露供应商或接口名。禁止编造未提供的数据。';

export function cachedOrderAnalysis(note: IdeaNote): OrderAnalysis | null {
  const cached = note.analysis as CachedOrderIdeaAnalysis | undefined;
  return isOrderAnalysis(cached?.orderAnalysis) ? cached.orderAnalysis : null;
}

export function mergeOrderAnalysisCache(note: IdeaNote, orderAnalysis: OrderAnalysis): CachedOrderIdeaAnalysis {
  const existing = note.analysis as CachedOrderIdeaAnalysis | undefined;
  return {
    conclusion: existing?.conclusion ?? orderAnalysis.title,
    points: existing?.points ?? orderAnalysis.bullets,
    suggestOrder: existing?.suggestOrder ?? false,
    suggestedSide: existing?.suggestedSide,
    generatedAt: existing?.generatedAt ?? orderAnalysis.generatedAt,
    orderAnalysis,
  };
}

export async function analyzeOrderIdea(note: IdeaNote, onProgress: ProgressSink): Promise<OrderAnalysis> {
  onProgress({ step: 'resolving_symbol', status: 'running', message: '正在识别标的与交易方向' });
  const draft = await buildOrderDraft({ symbol: note.symbol, intent: note.intent });
  onProgress({
    step: 'resolving_symbol',
    status: 'done',
    message: `已识别为 ${draft.name}（${draft.code}）${draft.side === 'SELL' ? '卖出' : '买入'}`,
  });

  const westock = new WestockMarketClient();
  onProgress({ step: 'loading_quote', status: 'running', message: '正在调用行情 skill，读取行情与近期走势' });
  const [quote, kline] = await Promise.all([
    westock.getQuoteSnapshot(draft.code).catch(() => null),
    westock.getKline(draft.code, 20).catch(() => null),
  ]);
  onProgress({
    step: 'loading_quote',
    status: quote ? 'done' : 'skipped',
    message: quote ? `最新价 ${quote.lastPrice} ${draft.currency}` : '行情 skill 暂不可用，使用订单草稿价兜底',
  });

  onProgress({ step: 'loading_account', status: 'running', message: '正在读取模拟账户资金与持仓' });
  const adapter = getBrokerAdapter();
  const [account] = await adapter.listAccounts();
  const positions = await adapter.listPositions(account.id);
  const position = positions.find((item) => item.code === draft.code) ?? null;
  onProgress({
    step: 'loading_account',
    status: 'done',
    message: position ? `已读取持仓 ${position.quantity} 股` : `当前未持有，现金 ${account.currency} ${formatNumber(account.cash)}`,
  });

  onProgress({ step: 'loading_research', status: 'running', message: '正在调用研报 skill，检索机构观点' });
  const [htscReports, westockReports] = await Promise.all([
    fetchHtscReports(reportSearchNames(draft.name)).catch(() => []),
    westock.getResearchReports(draft.code, 3).catch(() => []),
  ]);
  const reportCount = htscReports.length + westockReports.length;
  onProgress({
    step: 'loading_research',
    status: reportCount > 0 ? 'done' : 'skipped',
    message: reportCount > 0 ? `已获取 ${reportCount} 条研报线索` : '研报 skill 暂无结果，继续基于行情与账户分析',
  });

  onProgress({ step: 'loading_news', status: 'running', message: '正在调用资讯 skill，读取公告与资讯线索' });
  const news = await westock.getMarketNews(draft.code, 3).catch(() => []);
  onProgress({
    step: 'loading_news',
    status: news.length > 0 ? 'done' : 'skipped',
    message: news.length > 0 ? `已获取 ${news.length} 条资讯` : '资讯 skill 暂无结果，跳过资讯源',
  });

  const context: AnalysisContext = {
    note,
    draft,
    account,
    position,
    quote,
    klineChangePercent: computeKlineChangePercent(kline),
    htscReports,
    westockReports,
    news,
  };

  onProgress({ step: 'synthesizing', status: 'running', message: '正在整合资金、行情与研报观点' });
  const analysis = await synthesizeAnalysis(context);
  onProgress({ step: 'synthesizing', status: 'done', message: '标的分析已完成' });
  return analysis;
}

async function fetchHtscReports(secuAbbrCandidates: string[]): Promise<HtscReport[]> {
  const apiKey = process.env.HTSC_APP_KEY || '';
  if (!apiKey) return [];

  for (const secuAbbr of secuAbbrCandidates) {
    if (!secuAbbr.trim()) continue;
    const res = await fetch('https://inst.htsc.com/institution/skill/tool/apiGateway', {
      method: 'POST',
      headers: {
        Authorization: apiKey,
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({
        channel: 'ris',
        serviceName: 'com.htsc.ris.out.api.RisOutSkillServiceI',
        method: 'SkillCommonApi',
        skillName: 'htsc-report-skill',
        params: {
          resource: 'getLatestFiveReports',
          secuAbbr,
        },
      }),
    });
    if (!res.ok) continue;
    const data = (await res.json()) as HtscResponse;
    if (data.code !== '0') continue;
    const reports = (data.resultData ?? [])
      .map((row): HtscReport | null => {
        const title = stringFrom(row.showTitle);
        if (!title) return null;
        return {
          title,
          author: stringFrom(row.authorNames) || undefined,
          date: stringFrom(row.pubdate) || undefined,
          summary: cleanupText(stringFrom(row.summay)) || undefined,
        };
      })
      .filter((item): item is HtscReport => item !== null)
      .slice(0, 5);
    if (reports.length > 0) return reports;
  }
  return [];
}

async function synthesizeAnalysis(context: AnalysisContext): Promise<OrderAnalysis> {
  try {
    const parsed = await callDeepSeekJson({
      systemPrompt: SYSTEM_PROMPT,
      userPrompt: buildPrompt(context),
      temperature: 0.25,
      maxTokens: 760,
    });

    return {
      title: nonEmptyString(parsed.title) || fallbackAnalysis(context).title,
      summary: nonEmptyString(parsed.summary) || fallbackAnalysis(context).summary,
      bullets: stringArray(parsed.bullets).slice(0, 4),
      risks: stringArray(parsed.risks).slice(0, 3),
      sources: stringArray(parsed.sources),
      generatedAt: new Date().toISOString(),
    };
  } catch {
    return fallbackAnalysis(context);
  }
}

function fallbackAnalysis(context: AnalysisContext): OrderAnalysis {
  const { draft, account, position, quote } = context;
  const side = draft.side === 'SELL' ? '卖出' : '买入';
  const price = quote?.lastPrice ?? draft.price;
  const amount = price * draft.quantity;
  const cashRatio = account.cash > 0 ? (amount / account.cash) * 100 : 0;
  const holdingText = position
    ? `已有持仓 ${position.quantity} 股，成本 ${position.costPrice}，浮盈 ${position.unrealizedPnlPercent.toFixed(2)}%。`
    : '当前没有匹配到该标的持仓。';

  return {
    title: `${draft.name}：先按小仓位验证判断`,
    summary:
      `这次指令被识别为${side} ${draft.name}，草稿数量 ${draft.quantity} 股，按现价约占模拟现金 ${cashRatio.toFixed(1)}%。` +
      `${holdingText} 当前研报/资讯源不足，判断主要基于 westock 行情和模拟账户资金，适合作为下单前确认，不宜视为确定性买卖建议。`,
    bullets: [
      `现价 ${price} ${draft.currency}`,
      `预计金额约 ${formatNumber(amount)} ${draft.currency}`,
      position ? `持仓浮盈 ${position.unrealizedPnlPercent.toFixed(2)}%` : '当前未匹配持仓',
    ],
    risks: ['研报/资讯覆盖不足', '模拟账户不等同真实资金约束'],
    sources: ['行情 skill', '模拟账户/持仓'],
    generatedAt: new Date().toISOString(),
  };
}

function buildPrompt(context: AnalysisContext): string {
  const { note, draft, account, position, quote, klineChangePercent, htscReports, westockReports, news } = context;
  return [
    `用户原话：${note.transcript}`,
    `订单草稿：${draft.name} ${draft.code} ${draft.side} ${draft.quantity} 股，草稿价 ${draft.price} ${draft.currency}`,
    `资金情况：现金 ${account.currency} ${account.cash}，总资产 ${account.totalAssets}，今日盈亏 ${account.dayPnlPercent}%`,
    position
      ? `持仓情况：持有 ${position.quantity} 股，可用 ${position.availableQuantity}，成本 ${position.costPrice}，浮盈 ${position.unrealizedPnlPercent}%，今日 ${position.dayChangePercent}%`
      : '持仓情况：当前未持有该标的',
    quote
      ? `实时行情：最新价 ${quote.lastPrice}，涨跌幅 ${quote.changePercent}%，日期 ${quote.endDate ?? '未知'}`
      : '实时行情：不可用',
    klineChangePercent == null ? '近期走势：不可用' : `近期走势：近 20 根K线涨跌约 ${klineChangePercent.toFixed(2)}%`,
    `研报skill A：${formatHtscReports(htscReports)}`,
    `研报skill B：${formatWestockReports(westockReports)}`,
    `资讯：${formatNews(news)}`,
  ].join('\n');
}

function reportSearchNames(name: string): string[] {
  const trimmed = name.trim();
  const simplified = trimmed
    .replace(/控股$/u, '')
    .replace(/股份$/u, '')
    .replace(/集团$/u, '')
    .replace(/-W$/u, '')
    .replace(/-SW$/u, '')
    .trim();
  return [...new Set([trimmed, simplified].filter(Boolean))];
}

function isOrderAnalysis(value: unknown): value is OrderAnalysis {
  if (!value || typeof value !== 'object') return false;
  const record = value as Record<string, unknown>;
  return (
    typeof record.title === 'string' &&
    typeof record.summary === 'string' &&
    Array.isArray(record.bullets) &&
    Array.isArray(record.risks) &&
    Array.isArray(record.sources) &&
    typeof record.generatedAt === 'string'
  );
}

function computeKlineChangePercent(kline: Array<{ close: number }> | null): number | null {
  if (!kline || kline.length < 2) return null;
  const first = kline[0]?.close;
  const last = kline[kline.length - 1]?.close;
  if (!first || !last) return null;
  return ((last - first) / first) * 100;
}

function formatHtscReports(reports: HtscReport[]): string {
  if (reports.length === 0) return '无';
  return reports
    .slice(0, 3)
    .map((item) => `${item.title}${item.date ? `（${item.date}）` : ''}：${item.summary ?? '无摘要'}`)
    .join('\n');
}

function formatWestockReports(reports: MarketResearchReport[]): string {
  if (reports.length === 0) return '无';
  return reports
    .slice(0, 3)
    .map((item) => `${item.title}${item.rating ? `，评级 ${item.rating}` : ''}：${item.summary ?? '无摘要'}`)
    .join('\n');
}

function formatNews(news: MarketNewsItem[]): string {
  if (news.length === 0) return '无';
  return news
    .slice(0, 3)
    .map((item) => `${item.title}${item.source ? `（${item.source}）` : ''}：${item.summary ?? '无摘要'}`)
    .join('\n');
}

function cleanupText(value: string): string {
  return value.replace(/[\t\r\n]+/g, ' ').replace(/\s+/g, ' ').trim();
}

function nonEmptyString(value: unknown): string {
  return typeof value === 'string' ? value.trim() : '';
}

function stringArray(value: unknown): string[] {
  return Array.isArray(value)
    ? value.filter((item): item is string => typeof item === 'string' && item.trim().length > 0).map((item) => item.trim())
    : [];
}

function stringFrom(value: unknown): string {
  return typeof value === 'string' ? value.trim() : '';
}

function formatNumber(value: number): string {
  return value.toLocaleString('en-US', { maximumFractionDigits: 2 });
}
