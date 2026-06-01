/**
 * 投资想法分类：从语音转写文本里识别「标的 + 操作意图 + 任务类型 + 触发条件」。
 *
 * 任务类型是核心——一条想法不一定是「立刻下单」：
 *   · order       立即下单意图（「现在买 100 股宁德时代」）
 *   · analysis    分析/咨询意图（「宁德时代要不要止盈」「看看比亚迪怎么样」）
 *   · conditional 条件触发意图（「比亚迪回调到 230 我想加仓」）→ 解析出 condition
 *
 * 实现：Qwen 小模型做结构化分类（OpenAI 兼容 chat），并叠加确定性正则修复条件价；
 * best-effort 语义：无 key / 网络 / 解析失败时回退到纯规则启发式，绝不阻塞想法卡创建。
 */

const SILICONFLOW_CHAT_URL = 'https://api.siliconflow.cn/v1/chat/completions';
const INTENT_MODEL = 'Qwen/Qwen2.5-7B-Instruct';

const SYSTEM_PROMPT =
  '你从用户口述的投资想法里提取结构化信息，只返回 JSON：' +
  '{"symbol":"","intent":"","taskType":"","condition":{"op":"","price":0}}。\n' +
  'symbol：股票/基金/指数等标的名（如「宁德时代」「比亚迪」），没有则留空。\n' +
  'intent：操作意图，从 加仓/减仓/止盈/止损/买入/卖出/观望/调仓 里选最贴近的，判断不了留空。\n' +
  'taskType 三选一：\n' +
  '  order = 用户想立刻下单（「现在买」「帮我卖出100股」）；\n' +
  '  analysis = 用户在问分析/建议（「要不要止盈」「怎么样」「该不该买」「值不值」）；\n' +
  '  conditional = 用户设定了价格触发条件（「回调到230加仓」「涨到260止盈」）。\n' +
  'condition：仅当 taskType=conditional 时给出，op 为 lte（跌到/回调到/低于）或 gte（涨到/突破/高于），price 为数字；其它情况 condition 省略或留 price=0。\n' +
  '不要编造，不确定的字段留空。';

export type IdeaTaskType = 'order' | 'analysis' | 'conditional';

export interface IdeaCondition {
  op: 'lte' | 'gte';
  price: number;
}

export interface ClassifiedIdea {
  symbol: string;
  intent: string;
  taskType: IdeaTaskType;
  condition?: IdeaCondition;
}

interface ChatCompletionResponse {
  choices?: Array<{ message?: { content?: string } }>;
}

const ANALYSIS_KEYWORDS = [
  '要不要', '怎么样', '怎么看', '如何', '分析', '看看', '值不值', '该不该',
  '能不能', '是否', '走势', '前景', '行不行', '可不可以', '建议',
];
const IMMEDIATE_KEYWORDS = ['现在', '立刻', '马上', '立即', '直接'];
const LTE_KEYWORDS = ['回调到', '跌到', '跌至', '回落到', '下跌到', '低于', '调整到', '回踩到'];
const GTE_KEYWORDS = ['涨到', '涨至', '突破', '站上', '涨破', '反弹到', '高于', '冲到'];

/** 从文本里抽取「方向词 + 数字」的价格条件，确定性正则，作为 LLM 结果的兜底/修复。 */
function extractConditionByRegex(text: string): IdeaCondition | null {
  const matchOp = (keywords: string[], op: 'lte' | 'gte'): IdeaCondition | null => {
    for (const kw of keywords) {
      const idx = text.indexOf(kw);
      if (idx === -1) continue;
      const tail = text.slice(idx + kw.length);
      const num = tail.match(/[0-9]+(?:\.[0-9]+)?/);
      if (num) return { op, price: Number(num[0]) };
    }
    return null;
  };
  return matchOp(LTE_KEYWORDS, 'lte') ?? matchOp(GTE_KEYWORDS, 'gte');
}

const BUY_SELL_KEYWORDS = ['加仓', '减仓', '止盈', '止损', '买入', '卖出', '清仓', '建仓', '补仓', '加点', '减点'];

/** 纯规则启发式：无 LLM 时也能给出合理的 taskType（条件 > 分析 > 下单 > 默认分析）。 */
function heuristicClassify(transcript: string): ClassifiedIdea {
  const text = transcript.trim();
  const condition = extractConditionByRegex(text);
  if (condition) {
    return { symbol: '', intent: '', taskType: 'conditional', condition };
  }
  if (ANALYSIS_KEYWORDS.some((kw) => text.includes(kw))) {
    return { symbol: '', intent: '', taskType: 'analysis' };
  }
  const hasOrderVerb = BUY_SELL_KEYWORDS.some((kw) => text.includes(kw));
  const isImmediate = IMMEDIATE_KEYWORDS.some((kw) => text.includes(kw));
  if (hasOrderVerb && isImmediate) {
    return { symbol: '', intent: '', taskType: 'order' };
  }
  // 模糊想法默认进分析（更安全：不擅自给下单草稿）。
  return { symbol: '', intent: '', taskType: 'analysis' };
}

function normalizeTaskType(value: unknown): IdeaTaskType | null {
  if (value === 'order' || value === 'analysis' || value === 'conditional') return value;
  return null;
}

function normalizeCondition(value: unknown): IdeaCondition | null {
  if (!value || typeof value !== 'object') return null;
  const op = (value as { op?: unknown }).op;
  const price = Number((value as { price?: unknown }).price);
  if ((op === 'lte' || op === 'gte') && Number.isFinite(price) && price > 0) {
    return { op, price };
  }
  return null;
}

export async function classifyIdea(transcript: string): Promise<ClassifiedIdea> {
  const text = transcript.trim();
  if (!text) return { symbol: '', intent: '', taskType: 'analysis' };

  const regexCondition = extractConditionByRegex(text);
  const apiKey = process.env.SILICONFLOW_API_KEY;

  if (!apiKey) {
    const fallback = heuristicClassify(text);
    return regexCondition
      ? { ...fallback, taskType: 'conditional', condition: regexCondition }
      : fallback;
  }

  try {
    const res = await fetch(SILICONFLOW_CHAT_URL, {
      method: 'POST',
      headers: { Authorization: `Bearer ${apiKey}`, 'Content-Type': 'application/json' },
      body: JSON.stringify({
        model: INTENT_MODEL,
        messages: [
          { role: 'system', content: SYSTEM_PROMPT },
          { role: 'user', content: text },
        ],
        temperature: 0,
        max_tokens: 160,
        response_format: { type: 'json_object' },
      }),
    });
    if (!res.ok) throw new Error(`status ${res.status}`);

    const data = (await res.json()) as ChatCompletionResponse;
    const content = data.choices?.[0]?.message?.content;
    if (!content) throw new Error('empty content');

    const parsed = JSON.parse(content) as Record<string, unknown>;
    const symbol = typeof parsed.symbol === 'string' ? parsed.symbol.trim() : '';
    const intent = typeof parsed.intent === 'string' ? parsed.intent.trim() : '';
    let taskType = normalizeTaskType(parsed.taskType) ?? heuristicClassify(text).taskType;
    let condition = normalizeCondition(parsed.condition) ?? regexCondition ?? undefined;

    // 一致性修复：有条件价 → 一定是 conditional；标成 conditional 却没价就降级。
    if (condition) taskType = 'conditional';
    else if (taskType === 'conditional') taskType = ANALYSIS_KEYWORDS.some((kw) => text.includes(kw)) ? 'analysis' : 'order';

    return { symbol, intent, taskType, condition };
  } catch {
    const fallback = heuristicClassify(text);
    return regexCondition
      ? { ...fallback, taskType: 'conditional', condition: regexCondition }
      : fallback;
  }
}
