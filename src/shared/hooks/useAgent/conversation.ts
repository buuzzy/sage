/**
 * Conversation history builder.
 * Transforms local message array into the format expected by the Agent API.
 */

import { getSettings } from '@/shared/db/settings';

import type { AgentMessage, ConversationMessage } from './types';

function buildConversationHistory(
  initialPrompt: string,
  messages: AgentMessage[]
): ConversationMessage[] {
  const history: ConversationMessage[] = [];

  // Use persisted user messages whenever they exist. task.prompt can later be
  // replaced by a generated sidebar title, so it must not be treated as the
  // canonical first user message for follow-up context.
  const hasPersistedUserMessage = messages.some((msg) => msg.type === 'user');
  if (initialPrompt && !hasPersistedUserMessage) {
    history.push({ role: 'user', content: initialPrompt });
  }

  // Process messages to build conversation, including tool results
  // so the Agent can reference previous data lookups in follow-up questions.
  let currentAssistantContent = '';
  const pendingToolNames = new Map<string, string>();

  for (const msg of messages) {
    if (msg.type === 'user') {
      if (currentAssistantContent) {
        history.push({
          role: 'assistant',
          content: currentAssistantContent.trim(),
        });
        currentAssistantContent = '';
      }

      const imagePaths = msg.attachments
        ?.filter((a) => a.type === 'image' && a.path)
        .map((a) => a.path as string);

      history.push({
        role: 'user',
        content: msg.content || '',
        imagePaths:
          imagePaths && imagePaths.length > 0 ? imagePaths : undefined,
      });
    } else if (msg.type === 'text') {
      currentAssistantContent += (msg.content || '') + '\n';
    } else if (msg.type === 'tool_use') {
      const toolId =
        (msg as { id?: string }).id || msg.toolUseId || `tool_${Date.now()}`;
      if (msg.name) pendingToolNames.set(toolId, msg.name);
      currentAssistantContent += `[Used tool: ${msg.name}]\n`;
    } else if (msg.type === 'tool_result') {
      const toolName =
        (msg.toolUseId && pendingToolNames.get(msg.toolUseId)) || 'tool';
      const output = msg.output || '';
      if (output) {
        const truncated =
          output.length > 800 ? output.slice(0, 800) + '...' : output;
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

  // Apply history length limit - keep only the most recent messages
  // Get max conversation turns from settings, fallback to default
  const settings = getSettings();
  const maxTurns = settings.maxConversationTurns || 20;
  const maxMessages = maxTurns * 2; // 2 messages per turn (user + assistant)

  if (history.length > maxMessages) {
    console.log(
      `[buildConversationHistory] Truncating history from ${history.length} to ${maxMessages} messages (max turns: ${maxTurns})`
    );
    return history.slice(-maxMessages);
  }

  return history;
}

export { buildConversationHistory };
