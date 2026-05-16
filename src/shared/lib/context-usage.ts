interface ContextMessage {
  type: string;
  content?: string | null;
  name?: string;
  id?: string;
  toolUseId?: string;
  output?: string;
}

interface ConversationPayloadMessage {
  role: 'user' | 'assistant';
  content: string;
}

interface ContextUsageOptions {
  maxConversationTurns: number;
  maxHistoryTokens: number;
}

const CJK_RE =
  /[\u3400-\u4dbf\u4e00-\u9fff\uf900-\ufaff\u3040-\u30ff\uac00-\ud7af]/g;

export function estimateTokens(text: string): number {
  if (!text) return 0;

  const cjkCount = text.match(CJK_RE)?.length ?? 0;
  const nonCjkText = text.replace(CJK_RE, ' ');
  const nonWhitespaceChars = nonCjkText.replace(/\s+/g, '').length;

  // English/code/JSON roughly fit the classic chars/4 rule, while CJK text is
  // much closer to one token per character. Use the larger estimate so the UI
  // does not under-report Chinese-heavy conversations.
  return Math.max(
    1,
    cjkCount + Math.ceil(nonWhitespaceChars / 4),
    Math.ceil(text.length / 4)
  );
}

function buildConversationPayloadMessages(
  initialPrompt: string,
  messages: ContextMessage[],
  maxConversationTurns: number
): ConversationPayloadMessage[] {
  const history: ConversationPayloadMessage[] = [];
  const hasPersistedUserMessage = messages.some((msg) => msg.type === 'user');
  const pendingToolNames = new Map<string, string>();
  let currentAssistantContent = '';

  // New tasks may not have persisted the first user message yet. Existing tasks
  // must use the real user messages, because task.prompt can later be replaced
  // by a generated sidebar title.
  if (initialPrompt && !hasPersistedUserMessage) {
    history.push({ role: 'user', content: initialPrompt });
  }

  for (const msg of messages) {
    if (msg.type === 'user') {
      if (currentAssistantContent) {
        history.push({
          role: 'assistant',
          content: currentAssistantContent.trim(),
        });
        currentAssistantContent = '';
      }
      history.push({ role: 'user', content: msg.content ?? '' });
      continue;
    }

    if (msg.type === 'text') {
      currentAssistantContent += `${msg.content ?? ''}\n`;
      continue;
    }

    if (msg.type === 'tool_use') {
      const toolId = msg.id ?? msg.toolUseId;
      if (toolId && msg.name) {
        pendingToolNames.set(toolId, msg.name);
      }
      currentAssistantContent += `[Used tool: ${msg.name ?? 'tool'}]\n`;
      continue;
    }

    if (msg.type === 'tool_result') {
      const toolName =
        (msg.toolUseId && pendingToolNames.get(msg.toolUseId)) ?? 'tool';
      const output = msg.output ?? '';
      if (output) {
        const truncated =
          output.length > 800 ? `${output.slice(0, 800)}...` : output;
        currentAssistantContent += `[${toolName} result]: ${truncated}\n`;
      }
    }
  }

  if (currentAssistantContent) {
    history.push({
      role: 'assistant',
      content: currentAssistantContent.trim(),
    });
  }

  const maxMessages = Math.max(1, maxConversationTurns || 20) * 2;
  return history.length > maxMessages ? history.slice(-maxMessages) : history;
}

function formatEstimatedConversationContext(
  conversation: ConversationPayloadMessage[],
  maxHistoryTokens: number
): string {
  if (conversation.length === 0) return '';

  const parts = ['## Recent Conversation\n'];
  let tokenBudget = Math.max(1, maxHistoryTokens || 12000) - estimateTokens(parts.join(''));
  const recentParts: string[] = [];

  for (let i = conversation.length - 1; i >= 0; i--) {
    const msg = conversation[i];
    const role = msg.role === 'user' ? 'User' : 'Assistant';
    const line = `${role}: ${msg.content}`;
    const lineTokens = estimateTokens(line);

    if (tokenBudget - lineTokens < 0 && recentParts.length >= 2) {
      recentParts.unshift(`[... ${i + 1} earlier messages omitted ...]`);
      break;
    }

    recentParts.unshift(line);
    tokenBudget -= lineTokens;
  }

  parts.push(recentParts.join('\n\n'));
  return parts.join('\n') + '\n\n---\n## Current Request\n';
}

/**
 * Mirrors the conversation context assembled before sending a follow-up request.
 * This counts the hidden tool-result snippets and the same context wrapper the
 * backend injects before the current prompt. It is still an estimate, but it is
 * intentionally conservative for Chinese-heavy conversations.
 */
export function estimateConversationContextTokens(
  initialPrompt: string,
  messages: ContextMessage[],
  options: ContextUsageOptions
): number {
  const conversation = buildConversationPayloadMessages(
    initialPrompt,
    messages,
    options.maxConversationTurns
  );
  const context = formatEstimatedConversationContext(
    conversation,
    options.maxHistoryTokens
  );

  return estimateTokens(context);
}
