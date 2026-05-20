/**
 * RunningIndicator — shows current activity status during agent execution.
 */

import type { AgentMessage, AgentPhase } from '@/shared/hooks/useAgent';

function RunningIndicator({
  messages,
  phase,
}: {
  messages: AgentMessage[];
  phase: AgentPhase;
}) {
  const lastUserIndex = messages.reduce(
    (lastIndex, message, index) =>
      message.type === 'user' ? index : lastIndex,
    -1
  );
  const currentTurnMessages = messages.slice(lastUserIndex + 1);
  const lastToolUse = [...currentTurnMessages]
    .reverse()
    .find((m) => m.type === 'tool_use');

  // Get description of current activity
  const getActivityText = () => {
    if (phase === 'planning') {
      return 'Planning execution...';
    }

    if (!lastToolUse?.name) {
      return phase === 'executing' ? 'Executing...' : 'Thinking...';
    }

    const input = lastToolUse.input as Record<string, unknown> | undefined;

    switch (lastToolUse.name) {
      case 'Bash':
        return `Running command...`;
      case 'Read':
        const readFile = input?.file_path
          ? String(input.file_path).split('/').pop()
          : '';
        return `Reading ${readFile || 'file'}...`;
      case 'Write':
        const writeFile = input?.file_path
          ? String(input.file_path).split('/').pop()
          : '';
        return `Writing ${writeFile || 'file'}...`;
      case 'Edit':
        const editFile = input?.file_path
          ? String(input.file_path).split('/').pop()
          : '';
        return `Editing ${editFile || 'file'}...`;
      case 'Grep':
        return 'Searching...';
      case 'Glob':
        return 'Finding files...';
      case 'WebSearch':
        return 'Searching web...';
      case 'WebFetch':
        return 'Fetching page...';
      case 'Task':
        return 'Running subtask...';
      default:
        return `Running ${lastToolUse.name}...`;
    }
  };

  return (
    <div className="flex items-center gap-2 py-2">
      {/* Spinning loader - Claude style */}
      <div className="relative size-4 shrink-0">
        <svg className="size-4 animate-spin" viewBox="0 0 24 24">
          <circle
            className="opacity-20"
            cx="12"
            cy="12"
            r="10"
            stroke="currentColor"
            strokeWidth="2"
            fill="none"
            style={{ color: '#d97706' }}
          />
          <path
            className="opacity-80"
            fill="none"
            stroke="currentColor"
            strokeWidth="2"
            strokeLinecap="round"
            d="M12 2a10 10 0 0 1 10 10"
            style={{ color: '#d97706' }}
          />
        </svg>
      </div>
      <span className="text-muted-foreground text-sm">{getActivityText()}</span>
    </div>
  );
}

export { RunningIndicator };
