/**
 * 投资想法分析：对「分析/咨询」类想法（如「宁德时代要不要止盈」）给出结构化观点。
 *
 * 关键：分析建立在用户**真实持仓上下文**（成本、现价、浮盈、可用数量）之上，而不是
 * 泛泛而谈——这才符合「有记忆的伙伴」。当前持仓为富途语义 mock，接真实账户后上下文自动变真。
 *
 * 用 DeepSeek V4 Flash 生成；失败时回退到基于数字的确定性结论，
 * 保证分析卡永远有可读内容。
 */

import { getBrokerAdapter } from '@/shared/broker';
import type { BrokerPosition } from '@/shared/broker';
import { callDeepSeekJson } from '@/shared/services/deepseek-json';

const SYSTEM_PROMPT =
  '你是用户的投资陪伴助手 Sage。基于给定的持仓上下文和用户的想法，给出克制、可执行的分析。' +
  '只返回 JSON：{"conclusion":"","points":["",""],"suggestOrder":false,"suggestedSide":""}。\n' +
  'conclusion：一句话结论（≤40 字），点明是否达到用户关心的条件、当前该怎么看。\n' +
  'points：2-4 条关键依据，每条 ≤30 字（结合成本/现价/浮盈/仓位）。\n' +
  'suggestOrder：是否建议现在就据此下单（true/false）。\n' +
  'suggestedSide：若建议下单，BUY 或 SELL；否则留空。\n' +
  '语气专业、不夸张、不喊单，不确定就说明需要继续观察。';

export interface IdeaAnalysis {
  conclusion: string;
  points: string[];
  suggestOrder: boolean;
  suggestedSide?: 'BUY' | 'SELL';
  generatedAt: string;
}

const SELL_INTENTS = ['减仓', '止盈', '止损', '卖出', '清仓'];

function buildContext(input: {
  symbol: string;
  intent: string;
  transcript: string;
  position: BrokerPosition | null;
}): string {
  const lines: string[] = [];
  lines.push(`用户想法原话：${input.transcript}`);
  lines.push(`标的：${input.symbol || '未明确'}；意图：${input.intent || '未明确'}`);
  if (input.position) {
    const p = input.position;
    lines.push(
      `持仓上下文：成本 ${p.costPrice}，现价 ${p.lastPrice}，` +
        `浮动盈亏 ${p.unrealizedPnlPercent.toFixed(2)}%，` +
        `持有 ${p.quantity} 股（可用 ${p.availableQuantity}），` +
        `今日涨跌 ${p.dayChangePercent.toFixed(2)}%`
    );
  } else {
    lines.push('持仓上下文：当前未持有该标的（或无法匹配到持仓）。');
  }
  return lines.join('\n');
}

/** LLM 不可用 / 失败时的确定性兜底：直接用持仓数字拼一个朴素但真实的结论。 */
function fallbackAnalysis(input: {
  intent: string;
  position: BrokerPosition | null;
}): IdeaAnalysis {
  const now = new Date().toISOString();
  const p = input.position;
  if (!p) {
    return {
      conclusion: '暂无该标的持仓数据，建议先补充行情再判断。',
      points: ['未匹配到对应持仓', '需要接入实时行情后再给结论'],
      suggestOrder: false,
      generatedAt: now,
    };
  }
  const wantsSell = SELL_INTENTS.some((kw) => input.intent.includes(kw));
  const profitable = p.unrealizedPnlPercent >= 0;
  return {
    conclusion: profitable
      ? `当前浮盈 ${p.unrealizedPnlPercent.toFixed(1)}%，是否${input.intent || '操作'}取决于你的目标位。`
      : `当前浮亏 ${Math.abs(p.unrealizedPnlPercent).toFixed(1)}%，建议结合纪律再决定。`,
    points: [
      `成本 ${p.costPrice} / 现价 ${p.lastPrice}`,
      `浮动盈亏 ${p.unrealizedPnlPercent.toFixed(2)}%`,
      `持有 ${p.quantity} 股，今日 ${p.dayChangePercent.toFixed(2)}%`,
    ],
    suggestOrder: false,
    suggestedSide: wantsSell ? 'SELL' : 'BUY',
    generatedAt: now,
  };
}

export async function analyzeIdea(input: {
  symbol: string;
  intent: string;
  transcript: string;
}): Promise<IdeaAnalysis> {
  const adapter = getBrokerAdapter();
  const resolved = await adapter.resolveInstrument(input.symbol);
  const positions = await adapter.listPositions();
  const position = resolved
    ? positions.find((p) => p.code === resolved.code) ?? null
    : null;

  try {
    const parsed = await callDeepSeekJson({
      systemPrompt: SYSTEM_PROMPT,
      userPrompt: buildContext({ ...input, position }),
      temperature: 0.3,
      maxTokens: 320,
    });
    const conclusion =
      typeof parsed.conclusion === 'string' && parsed.conclusion.trim()
        ? parsed.conclusion.trim()
        : fallbackAnalysis({ intent: input.intent, position }).conclusion;
    const points = Array.isArray(parsed.points)
      ? parsed.points.filter((x): x is string => typeof x === 'string' && x.trim().length > 0).slice(0, 4)
      : [];
    const suggestOrder = parsed.suggestOrder === true;
    const rawSide = parsed.suggestedSide;
    const suggestedSide = rawSide === 'BUY' || rawSide === 'SELL' ? rawSide : undefined;

    return {
      conclusion,
      points: points.length > 0 ? points : fallbackAnalysis({ intent: input.intent, position }).points,
      suggestOrder,
      suggestedSide,
      generatedAt: new Date().toISOString(),
    };
  } catch {
    return fallbackAnalysis({ intent: input.intent, position });
  }
}
