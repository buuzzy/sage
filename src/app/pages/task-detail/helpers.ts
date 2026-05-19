/**
 * Helper utilities for TaskDetail page.
 */

import type { AgentMessage } from '@/shared/hooks/useAgent';

function serializeMessagesForCopy(msgs: AgentMessage[]): string {
  const MAX_TOOL_RESULT_CHARS = 500;

  return msgs
    .map((msg) => {
      switch (msg.type) {
        case 'user':
          return `[用户]\n${msg.content || ''}`;
        case 'text':
          return `[助手]\n${msg.content || ''}`;
        case 'tool_use': {
          const inputStr =
            typeof msg.input === 'string'
              ? msg.input
              : JSON.stringify(msg.input, null, 2);
          return `[工具调用] ${msg.name || ''}\n${inputStr}`;
        }
        case 'tool_result': {
          const raw = msg.content || '';
          const truncated =
            raw.length > MAX_TOOL_RESULT_CHARS
              ? `${raw.slice(0, MAX_TOOL_RESULT_CHARS)}… [truncated ${raw.length - MAX_TOOL_RESULT_CHARS} chars]`
              : raw;
          return `[工具结果]\n${truncated}`;
        }
        case 'result':
          return `[完成] subtype=${msg.subtype || ''} cost=${msg.cost ?? ''} duration=${msg.duration ?? ''}ms`;
        case 'error':
          return `[错误] ${msg.message || ''}`;
        case 'plan':
          return `[计划]\n${JSON.stringify(msg.plan, null, 2)}`;
        default:
          return `[${msg.type}]\n${msg.content || ''}`;
      }
    })
    .join('\n\n---\n\n');
}


export { serializeMessagesForCopy };
