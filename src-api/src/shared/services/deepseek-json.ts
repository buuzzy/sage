/**
 * DeepSeek OpenAI-compatible JSON helper for mobile investment workflows.
 *
 * Used by lightweight product-state LLM calls (idea classification and analysis),
 * not by the general Agent provider stack.
 */

const DEEPSEEK_BASE_URL = 'https://api.deepseek.com';
export const DEEPSEEK_V4_FLASH_MODEL = 'deepseek-v4-flash';

interface DeepSeekJsonRequest {
  systemPrompt: string;
  userPrompt: string;
  temperature: number;
  maxTokens: number;
}

interface DeepSeekChatCompletionResponse {
  choices?: Array<{ message?: { content?: string } }>;
}

function deepSeekChatUrl(): string {
  const baseUrl = (process.env.DEEPSEEK_BASE_URL || DEEPSEEK_BASE_URL).replace(/\/+$/, '');
  return `${baseUrl}/chat/completions`;
}

export async function callDeepSeekJson(input: DeepSeekJsonRequest): Promise<Record<string, unknown>> {
  const apiKey = process.env.DEEPSEEK_API_KEY;
  if (!apiKey) throw new Error('DEEPSEEK_API_KEY missing');

  const res = await fetch(deepSeekChatUrl(), {
    method: 'POST',
    headers: { Authorization: `Bearer ${apiKey}`, 'Content-Type': 'application/json' },
    body: JSON.stringify({
      model: DEEPSEEK_V4_FLASH_MODEL,
      messages: [
        { role: 'system', content: input.systemPrompt },
        { role: 'user', content: input.userPrompt },
      ],
      temperature: input.temperature,
      max_tokens: input.maxTokens,
      response_format: { type: 'json_object' },
    }),
  });

  if (!res.ok) {
    const detail = await res.text().catch(() => '');
    throw new Error(`DeepSeek JSON request failed (HTTP ${res.status}): ${detail.slice(0, 200)}`);
  }

  const data = (await res.json()) as DeepSeekChatCompletionResponse;
  const content = data.choices?.[0]?.message?.content;
  if (!content) throw new Error('DeepSeek JSON request returned empty content');

  return JSON.parse(content) as Record<string, unknown>;
}
