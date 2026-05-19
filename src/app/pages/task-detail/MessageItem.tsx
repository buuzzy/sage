/**
 * MessageItem — routes each message to its appropriate renderer
 * based on message type (text, error, tool_use, etc.).
 */

import type { AgentMessage } from '@/shared/hooks/useAgent';
import { ErrorMessage } from './ErrorMessage';
import { TextMessageItem } from './TextMessageItem';

function MessageItem({
  message,
  phase,
  onApprovePlan,
  onRejectPlan,
  allMessages,
  taskId,
}: {
  message: AgentMessage;
  phase?: string;
  onApprovePlan?: () => void;
  onRejectPlan?: () => void;
  allMessages?: AgentMessage[];
  taskId?: string;
}) {
  if (message.type === 'user') {
    return (
      <UserMessage
        content={message.content || ''}
        attachments={message.attachments}
      />
    );
  }

  if (message.type === 'plan' && message.plan) {
    return (
      <PlanApproval
        plan={message.plan}
        isWaitingApproval={phase === 'awaiting_approval' && !isRunning}
        onApprove={onApprovePlan}
        onReject={onRejectPlan}
      />
    );
  }

  if (message.type === 'text') {
    return (
      <TextMessageItem
        message={message}
        allMessages={allMessages}
        taskId={taskId}
      />
    );
  }

  if (message.type === 'result') {
    return null;
  }

  if (message.type === 'error') {
    return <ErrorMessage message={message.message || ''} />;
  }

  return null;
}



export { MessageItem };
