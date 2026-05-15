interface ContextMessage {
  type: string;
  content?: string | null;
  name?: string;
  id?: string;
  toolUseId?: string;
  output?: string;
}

function estimateTokens(text: string): number {
  return Math.ceil(text.length / 4);
}

/**
 * Mirrors the conversation payload assembled in useAgent before sending a
 * follow-up request. This is still an estimate, but it counts the hidden tool
 * result context that the visible chat text alone misses.
 */
export function estimateConversationContextTokens(
  initialPrompt: string,
  messages: ContextMessage[],
  maxConversationTurns: number
): number {
  const history: string[] = [];
  const pendingToolNames = new Map<string, string>();
  let currentAssistantContent = '';

  if (initialPrompt) {
    history.push(initialPrompt);
  }

  for (const msg of messages) {
    if (msg.type === 'user') {
      if (currentAssistantContent) {
        history.push(currentAssistantContent.trim());
        currentAssistantContent = '';
      }
      history.push(msg.content ?? '');
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
    history.push(currentAssistantContent.trim());
  }

  const maxMessages = Math.max(1, maxConversationTurns || 20) * 2;
  const effectiveHistory =
    history.length > maxMessages ? history.slice(-maxMessages) : history;

  return effectiveHistory.reduce((total, content) => {
    return total + estimateTokens(content);
  }, 0);
}
