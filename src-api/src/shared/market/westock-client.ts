import type { BrokerMarket, KlinePoint, QuoteSnapshot, ResolvedInstrument } from '@/shared/broker';

const WESTOCK_PROXY_URL = 'https://proxy.finance.qq.com/cgi/cgi-bin/openai/openclaw/proxy';
const WESTOCK_SEARCH_URL = 'https://proxy.finance.qq.com/cgi/cgi-bin/smartbox/search';
const WESTOCK_REPORT_URL = 'http://ifzq.gtimg.cn/appstock/app/investRate/getReport';
const WESTOCK_NEWS_URL = 'http://ifzq.gtimg.cn/appstock/news/info/search';
const DEFAULT_CHANNEL = 'stockclaw';

interface WestockStockRow {
  code?: unknown;
  name?: unknown;
  data?: Record<string, unknown>;
  [key: string]: unknown;
}

interface WestockResponse {
  code?: number;
  data?: {
    stocks?: WestockStockRow[];
    series?: Array<{ date?: string; data?: Record<string, unknown> }>;
    results?: unknown[];
    code?: string;
    name?: string;
  };
}

interface SmartboxStockRow {
  code?: string;
  name?: string;
  type?: string;
}

interface SmartboxResponse {
  stock?: SmartboxStockRow[];
}

interface WestockResearchReportRow {
  title?: unknown;
  time?: unknown;
  src?: unknown;
  tzpj?: unknown;
  summary?: unknown;
}

interface WestockReportResponse {
  code?: number;
  data?: {
    reports?: WestockResearchReportRow[];
  };
}

interface WestockNewsRow {
  title?: unknown;
  time?: unknown;
  src?: unknown;
  summary?: unknown;
  url?: unknown;
}

interface WestockNewsResponse {
  code?: number;
  data?: {
    data?: WestockNewsRow[];
    news?: WestockNewsRow[];
  };
}

export interface MarketResearchReport {
  title: string;
  source: string;
  rating?: string;
  date?: string;
  summary?: string;
}

export interface MarketNewsItem {
  title: string;
  source: string;
  date?: string;
  summary?: string;
  url?: string;
}

function numberFrom(value: unknown): number | null {
  if (typeof value === 'number' && Number.isFinite(value)) return value;
  if (typeof value === 'string' && value.trim()) {
    const parsed = Number(value.replace(/,/g, ''));
    return Number.isFinite(parsed) ? parsed : null;
  }
  return null;
}

function lotSizeForMarket(market: BrokerMarket): number {
  return market === 'US' ? 1 : 100;
}

export function toWestockCode(code: string): string {
  const normalized = code.trim();
  if (normalized.startsWith('CN.')) {
    const raw = normalized.slice(3);
    const prefix = raw.startsWith('6') ? 'sh' : 'sz';
    return `${prefix}${raw}`;
  }
  if (normalized.startsWith('HK.')) return `hk${normalized.slice(3)}`;
  if (normalized.startsWith('US.')) return `us${normalized.slice(3).toUpperCase()}`;
  return normalized;
}

function fromWestockCode(code: string): { code: string; market: BrokerMarket; currency: string } | null {
  const normalized = code.trim();
  const lower = normalized.toLowerCase();
  if (lower.startsWith('sh') || lower.startsWith('sz')) {
    return { code: `CN.${normalized.slice(2)}`, market: 'CN', currency: 'CNY' };
  }
  if (lower.startsWith('hk')) {
    return { code: `HK.${normalized.slice(2).padStart(5, '0')}`, market: 'HK', currency: 'HKD' };
  }
  if (lower.startsWith('us')) {
    const ticker = normalized.slice(2).split('.')[0].toUpperCase();
    if (!ticker) return null;
    return { code: `US.${ticker}`, market: 'US', currency: 'USD' };
  }
  return null;
}

function snapshotFromRow(row: WestockStockRow): QuoteSnapshot | null {
  const data = row.data ?? {};
  const lastPrice = quoteFromRow(row);
  if (lastPrice == null) return null;
  const prevClose = numberFrom(data.PrevClosePrice);
  const computedChange = prevClose != null ? lastPrice - prevClose : 0;
  const change = numberFrom(data.Change) ?? computedChange;
  const changePercent = numberFrom(data.ChangeRatio) ?? (prevClose && prevClose > 0 ? (computedChange / prevClose) * 100 : 0);
  const endDate = typeof data.EndDate === 'string' ? data.EndDate : null;
  return { lastPrice, change, changePercent, prevClose, endDate };
}

function quoteFromRow(row: WestockStockRow): number | null {
  const data = row.data ?? {};
  return (
    numberFrom(data.ClosePrice) ??
    numberFrom(data.LastestTradedPrice) ??
    numberFrom(data.FwdClosePrice) ??
    numberFrom(row.zxj)
  );
}

function flattenRecords(value: unknown): Array<Record<string, unknown>> {
  if (Array.isArray(value)) return value.flatMap(flattenRecords);
  if (!value || typeof value !== 'object') return [];
  const record = value as Record<string, unknown>;
  const children = Object.values(record).flatMap(flattenRecords);
  return [record, ...children];
}

export class WestockMarketClient {
  private readonly apiKey = process.env.WESTOCK_API_KEY || '';

  get configured(): boolean {
    return !!this.apiKey;
  }

  async getQuote(code: string): Promise<number | null> {
    const snapshot = await this.getQuoteSnapshot(code).catch(() => null);
    return snapshot?.lastPrice ?? null;
  }

  async getQuoteSnapshot(code: string): Promise<QuoteSnapshot | null> {
    if (!this.configured) return null;
    const westockCode = toWestockCode(code);
    const data = await this.post('stock_quote_snapshot', {
      codes: westockCode,
      fields: 'ClosePrice,LastestTradedPrice,Change,ChangeRatio,OpenPrice,HighPrice,LowPrice,PrevClosePrice,EndDate',
    });
    const row = data.data?.stocks?.[0];
    return row ? snapshotFromRow(row) : null;
  }

  async getKline(code: string, count: number): Promise<KlinePoint[] | null> {
    if (!this.configured) return null;
    const end = new Date();
    const start = new Date();
    start.setDate(end.getDate() - Math.max(count * 2, 90));

    const data = await this.post('stock_quote_history', {
      code: toWestockCode(code),
      start_date: start.toISOString().slice(0, 10),
      end_date: end.toISOString().slice(0, 10),
      fields: 'OpenPrice,ClosePrice,HighPrice,LowPrice,TurnoverVolume',
    });

    const series = data.data?.series ?? [];
    const points = series
      .map((item): KlinePoint | null => {
        const row = item.data ?? {};
        const open = numberFrom(row.OpenPrice);
        const close = numberFrom(row.ClosePrice);
        const high = numberFrom(row.HighPrice);
        const low = numberFrom(row.LowPrice);
        if (open == null || close == null || high == null || low == null || !item.date) return null;
        return {
          time: item.date,
          open,
          high,
          low,
          close,
          volume: numberFrom(row.TurnoverVolume) ?? 0,
        };
      })
      .filter((point): point is KlinePoint => point !== null)
      .slice(-count);

    return points.length > 0 ? points : null;
  }

  async searchInstrument(symbol: string): Promise<ResolvedInstrument | null> {
    if (!this.configured || !symbol.trim()) return null;
    const url = new URL(WESTOCK_SEARCH_URL);
    url.searchParams.set('app', 'openclaw');
    url.searchParams.set('token', this.apiKey);
    url.searchParams.set('skill_channel', DEFAULT_CHANNEL);
    url.searchParams.set('query', symbol.trim());
    url.searchParams.set('stockFlag', '1');
    url.searchParams.set('fundFlag', '0');
    url.searchParams.set('ptFlag', '0');

    const res = await fetch(url);
    if (!res.ok) throw new Error(`westock search failed: ${res.status}`);
    const data = (await res.json()) as SmartboxResponse & WestockResponse;

    const smartboxRows: Array<Record<string, unknown>> = (data.stock ?? []).map((row) => ({
      code: row.code,
      name: row.name,
      type: row.type,
    }));
    const legacyRows = flattenRecords(data.data?.results ?? []);
    const records = smartboxRows.length > 0 ? smartboxRows : legacyRows;

    for (const record of records) {
      if (record.type === 'ZS') continue;
      const rawCode = typeof record.code === 'string' ? record.code : typeof record.Code === 'string' ? record.Code : '';
      const name = typeof record.name === 'string' ? record.name : typeof record.Name === 'string' ? record.Name : '';
      const normalized = rawCode ? fromWestockCode(rawCode) : null;
      if (!normalized || !name) continue;
      const snapshot = await this.getQuoteSnapshot(normalized.code).catch(() => null);
      if (!snapshot) continue;
      return {
        ...normalized,
        name,
        lastPrice: snapshot.lastPrice,
        lotSize: lotSizeForMarket(normalized.market),
      };
    }
    return null;
  }

  async getResearchReports(code: string, limit = 3): Promise<MarketResearchReport[]> {
    if (!this.configured) return [];
    const url = new URL(WESTOCK_REPORT_URL);
    url.searchParams.set('app', 'openclaw');
    url.searchParams.set('token', this.apiKey);
    url.searchParams.set('skill_channel', DEFAULT_CHANNEL);
    url.searchParams.set('symbol', toWestockCode(code));
    url.searchParams.set('page', '1');
    url.searchParams.set('n', String(Math.max(1, Math.min(limit, 10))));
    url.searchParams.set('withConference', '1');

    const res = await fetch(url);
    if (!res.ok) throw new Error(`westock research report failed: ${res.status}`);
    const data = (await res.json()) as WestockReportResponse;
    if (data.code !== 0) return [];
    return (data.data?.reports ?? [])
      .map((row): MarketResearchReport | null => {
        const title = stringFrom(row.title);
        if (!title) return null;
        return {
          title,
          source: stringFrom(row.src) || 'westock',
          rating: stringFrom(row.tzpj) || undefined,
          date: stringFrom(row.time) || undefined,
          summary: stringFrom(row.summary) || undefined,
        };
      })
      .filter((item): item is MarketResearchReport => item !== null);
  }

  async getMarketNews(code: string, limit = 3): Promise<MarketNewsItem[]> {
    if (!this.configured) return [];
    const url = new URL(WESTOCK_NEWS_URL);
    url.searchParams.set('app', 'openclaw');
    url.searchParams.set('token', this.apiKey);
    url.searchParams.set('skill_channel', DEFAULT_CHANNEL);
    url.searchParams.set('symbol', toWestockCode(code));
    url.searchParams.set('type', '2');
    url.searchParams.set('page', '1');
    url.searchParams.set('n', String(Math.max(1, Math.min(limit, 10))));

    const res = await fetch(url);
    if (!res.ok) throw new Error(`westock market news failed: ${res.status}`);
    const data = (await res.json()) as WestockNewsResponse;
    if (data.code !== 0) return [];
    return (data.data?.data ?? data.data?.news ?? [])
      .map((row): MarketNewsItem | null => {
        const title = stringFrom(row.title);
        if (!title) return null;
        return {
          title,
          source: stringFrom(row.src) || 'westock',
          date: stringFrom(row.time) || undefined,
          summary: stringFrom(row.summary) || undefined,
          url: stringFrom(row.url) || undefined,
        };
      })
      .filter((item): item is MarketNewsItem => item !== null);
  }

  private async post(route: string, params: Record<string, unknown>): Promise<WestockResponse> {
    const url = new URL(WESTOCK_PROXY_URL);
    url.searchParams.set('app', 'openclaw');
    url.searchParams.set('token', this.apiKey);
    url.searchParams.set('skill_channel', DEFAULT_CHANNEL);

    const res = await fetch(url, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        token: this.apiKey,
        route,
        params,
      }),
    });
    if (!res.ok) throw new Error(`westock ${route} failed: ${res.status}`);
    const data = (await res.json()) as WestockResponse;
    if (data.code !== 0) throw new Error(`westock ${route} returned code ${data.code ?? 'unknown'}`);
    return data;
  }
}

function stringFrom(value: unknown): string {
  return typeof value === 'string' ? value.trim() : '';
}
