/**
 * MessageList — groups messages into task groups (tool executions with text headers)
 * and renders them in order.
 */

import type { AgentMessage } from '@/shared/hooks/useAgent';

import { MessageItem } from './MessageItem';
import { TaskGroupComponent } from './TaskGroupComponent';

function MessageList({
  messages,
  isRunning,
  searchQuery,
  phase,
  onApprovePlan,
  onRejectPlan,
  taskId,
}: {
  messages: AgentMessage[];
  isRunning: boolean;
  searchQuery?: string;
  phase?: string;
  onApprovePlan?: () => void;
  onRejectPlan?: () => void;
  taskId?: string;
}) {
  if (messages.length === 0) {
    return null;
  }

  // Define types
  type ToolWithResult = {
    message: AgentMessage;
    globalIndex: number;
    result?: AgentMessage;
  };

  type TaskMessageGroup = {
    type: 'task';
    title: string;
    description: string;
    tools: ToolWithResult[];
    isCompleted: boolean;
  };

  type OtherMessageGroup = {
    type: 'other';
    message: AgentMessage;
  };

  type MessageGroup = TaskMessageGroup | OtherMessageGroup;

  // Pre-process: find the last text message index in each segment between user messages
  // This ensures we keep the agent's response to each user question
  const lastTextIndicesInSegments = new Set<number>();

  // Find segment boundaries (user messages and result)
  const segmentBoundaries: number[] = [];
  messages.forEach((msg, idx) => {
    if (msg.type === 'user' || msg.type === 'result') {
      segmentBoundaries.push(idx);
    }
  });
  segmentBoundaries.push(messages.length); // End boundary

  // For each segment, find the last text message
  let segmentStart = 0;
  for (const boundary of segmentBoundaries) {
    // Find last text message in this segment (from segmentStart to boundary)
    for (let i = boundary - 1; i >= segmentStart; i--) {
      if (messages[i].type === 'text' && messages[i].content) {
        lastTextIndicesInSegments.add(i);
        break;
      }
    }
    segmentStart = boundary + 1;
  }

  // Filter messages: only keep the last text message in each segment
  const mergedMessages: AgentMessage[] = [];
  for (let i = 0; i < messages.length; i++) {
    const msg = messages[i];
    if (msg.type === 'text' && msg.content) {
      // Only keep text messages that are the last in their segment
      if (lastTextIndicesInSegments.has(i)) {
        mergedMessages.push(msg);
      }
      // Skip other text messages (intermediate thinking)
    } else {
      mergedMessages.push(msg);
    }
  }

  // Collect all tool_result messages in order for matching with tool_use
  const toolResultMessages: AgentMessage[] = [];
  mergedMessages.forEach((msg) => {
    if (msg.type === 'tool_result') {
      toolResultMessages.push(msg);
    }
  });

  // Match tool_use with tool_result by index (they come in pairs)
  const getToolResult = (toolUseIndex: number): AgentMessage | undefined => {
    return toolResultMessages[toolUseIndex];
  };

  // Filter out duplicate plan messages - only keep the last one
  const lastPlanIdx = mergedMessages.reduce(
    (lastIdx, msg, idx) => (msg.type === 'plan' ? idx : lastIdx),
    -1
  );
  const filteredMessages =
    lastPlanIdx >= 0
      ? mergedMessages.filter(
          (msg, idx) => msg.type !== 'plan' || idx === lastPlanIdx
        )
      : mergedMessages;

  // Find the last result message index in filteredMessages
  let lastResultIndex = -1;
  filteredMessages.forEach((msg, index) => {
    if (msg.type === 'result') {
      lastResultIndex = index;
    }
  });

  // Process messages into groups
  const groups: MessageGroup[] = [];
  let toolGlobalIndex = 0;
  let toolUseIndex = 0;

  // Use a ref object to track current group (avoids TypeScript narrowing issues)
  const state = { currentGroup: null as TaskMessageGroup | null };

  const pushCurrentGroup = (completed: boolean) => {
    if (
      state.currentGroup &&
      (state.currentGroup.tools.length > 0 || state.currentGroup.description)
    ) {
      state.currentGroup.isCompleted = completed;
      groups.push(state.currentGroup);
      state.currentGroup = null;
    }
  };

  const ensureCurrentGroup = () => {
    if (!state.currentGroup) {
      state.currentGroup = {
        type: 'task',
        title: '执行任务',
        description: '',
        tools: [],
        isCompleted: false,
      };
    }
    return state.currentGroup;
  };

  let lastTextContent = '';
  // Track pending text message that might be standalone (no following tools)
  let pendingTextMessage: AgentMessage | null = null;

  filteredMessages.forEach((message, msgIndex) => {
    if (message.type === 'text' && message.content) {
      // Skip duplicate consecutive text messages
      if (message.content === lastTextContent) {
        return;
      }

      // Skip text messages that contain raw plan JSON
      // These are displayed by the PlanApproval component instead
      const trimmedContent = message.content.trim();
      if (
        trimmedContent.startsWith('{') &&
        trimmedContent.includes('"type"') &&
        trimmedContent.includes('"plan"')
      ) {
        return;
      }

      lastTextContent = message.content;

      // If there's a pending text message that had no tools, render it as standalone
      if (pendingTextMessage) {
        groups.push({ type: 'other', message: pendingTextMessage });
      }

      // Push any current tool group
      pushCurrentGroup(true);

      // Store this text as pending - we'll decide how to render it based on what follows
      pendingTextMessage = message;
      state.currentGroup = null;
    } else if (message.type === 'tool_use' && message.name) {
      // Text followed by tool_use - create a task group with the text as description
      if (pendingTextMessage) {
        const title =
          (pendingTextMessage.content || '').slice(0, 80) +
          ((pendingTextMessage.content || '').length > 80 ? '...' : '');
        state.currentGroup = {
          type: 'task',
          title,
          description: pendingTextMessage.content || '',
          tools: [],
          isCompleted: false,
        };
        pendingTextMessage = null;
      }
      const group = ensureCurrentGroup();
      // Find associated tool_result by index
      const result = getToolResult(toolUseIndex);
      group.tools.push({ message, globalIndex: toolGlobalIndex++, result });
      toolUseIndex++;
    } else if (message.type === 'tool_result') {
      // Skip tool_result messages as they're associated with tool_use
    } else if (message.type === 'user') {
      // Flush any pending text as standalone
      if (pendingTextMessage) {
        groups.push({ type: 'other', message: pendingTextMessage });
        pendingTextMessage = null;
      }
      pushCurrentGroup(true);
      groups.push({ type: 'other', message });
    } else if (message.type === 'result') {
      // Only show the last result message
      if (msgIndex === lastResultIndex) {
        // Flush any pending text as standalone
        if (pendingTextMessage) {
          groups.push({ type: 'other', message: pendingTextMessage });
          pendingTextMessage = null;
        }
        pushCurrentGroup(true);
        groups.push({ type: 'other', message });
      }
    } else if (message.type === 'error') {
      // Flush any pending text as standalone
      if (pendingTextMessage) {
        groups.push({ type: 'other', message: pendingTextMessage });
        pendingTextMessage = null;
      }
      pushCurrentGroup(true);
      groups.push({ type: 'other', message });
    } else if (message.type === 'plan') {
      // Plan message - render inline (duplicates already filtered out)
      if (pendingTextMessage) {
        groups.push({ type: 'other', message: pendingTextMessage });
        pendingTextMessage = null;
      }
      pushCurrentGroup(true);
      groups.push({ type: 'other', message });
    }
  });

  // Push any remaining pending text as standalone message
  if (pendingTextMessage) {
    groups.push({ type: 'other', message: pendingTextMessage });
  }

  // Push any remaining tool group
  pushCurrentGroup(!isRunning);

  return (
    <div className="space-y-4">
      {groups.map((group, index) => {
        if (group.type === 'task') {
          return (
            <TaskGroupComponent
              key={index}
              title={group.title}
              description={group.description}
              tools={group.tools}
              isCompleted={group.isCompleted}
              isRunning={isRunning}
              searchQuery={searchQuery}
            />
          );
        }
        return (
          <MessageItem
            key={index}
            message={group.message}
            phase={phase}
            onApprovePlan={onApprovePlan}
            onRejectPlan={onRejectPlan}
            allMessages={messages}
            taskId={taskId}
          />
        );
      })}
    </div>
  );
}

export { MessageList };
