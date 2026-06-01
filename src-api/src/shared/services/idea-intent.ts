/**
 * 投资想法意图抽取：从语音转写文本里提取「标的名称 + 操作意图」。
 *
 * 复用 SiliconFlow（ASR 同 key）的 Qwen 小模型做结构化抽取，OpenAI 兼容 chat 接口。
 * best-effort 语义：任何失败（无 key / 网络 / 解析）都返回空字段，绝不阻塞想法卡创建。
 */

const SILICONFLOW_CHAT_URL = 'https://api.siliconflow.cn/v1/chat/completions';
const INTENT_MODEL = 'Qwen/Qwen2.5-7B-Instruct';

const SYSTEM_PROMPT =
  '你从用户口述的投资想法里提取标的名称和操作意图，只返回 JSON：{"symbol":"","intent":""}。' +
  'symbol 是股票/基金/指数等标的名（如「宁德时代」「比亚迪」「标普500」），没有明确标的则留空字符串。' +
  'intent 是操作意图，从 加仓/减仓/止盈/止损/买入/卖出/观望/调仓 里选最贴近的，判断不了则留空字符串。' +
  '不要编造，不确定就留空。';

export interface ExtractedIntent {
  symbol: string;
  intent: string;
}

const EMPTY: ExtractedIntent = { symbol: '', intent: '' };

interface ChatCompletionResponse {
  choices?: Array<{ message?: { content?: string } }>;
}

export async function extractIdeaIntent(transcript: string): Promise<ExtractedIntent> {
  const apiKey = process.env.SILICONFLOW_API_KEY;
  if (!apiKey || !transcript.trim()) return EMPTY;

  try {
    const res = await fetch(SILICONFLOW_CHAT_URL, {
      method: 'POST',
      headers: {
        Authorization: `Bearer ${apiKey}`,
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({
        model: INTENT_MODEL,
        messages: [
          { role: 'system', content: SYSTEM_PROMPT },
          { role: 'user', content: transcript },
        ],
        temperature: 0,
        max_tokens: 80,
        response_format: { type: 'json_object' },
      }),
    });

    if (!res.ok) return EMPTY;

    const data = (await res.json()) as ChatCompletionResponse;
    const content = data.choices?.[0]?.message?.content;
    if (!content) return EMPTY;

    const parsed = JSON.parse(content) as Partial<ExtractedIntent>;
    return {
      symbol: typeof parsed.symbol === 'string' ? parsed.symbol.trim() : '',
      intent: typeof parsed.intent === 'string' ? parsed.intent.trim() : '',
    };
  } catch {
    return EMPTY;
  }
}
