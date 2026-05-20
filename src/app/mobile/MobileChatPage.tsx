/**
 * MobileChatPage — full-screen conversation view for mobile.
 * Shows messages, running indicator, plan approval, and bottom input.
 */

import { useCallback, useEffect, useRef, useState } from 'react';
import { MessageList } from '@/app/pages/task-detail/MessageList';
import { RunningIndicator } from '@/app/pages/task-detail/RunningIndicator';
import type {
  AgentMessage,
  AgentPhase,
  PendingQuestion,
  TaskPlan,
} from '@/shared/hooks/useAgent';
import { Send, Square } from 'lucide-react';

import { PlanApproval } from '@/components/task/PlanApproval';
import { QuestionInput } from '@/components/task/QuestionInput';

interface MobileChatPageProps {
  messages: AgentMessage[];
  isRunning: boolean;
  phase: AgentPhase;
  plan: TaskPlan | null;
  approvePlan: () => Promise<void>;
  rejectPlan: () => void;
  pendingQuestion: PendingQuestion | null;
  respondToQuestion: (
    id: string,
    answers: Record<string, string>
  ) => Promise<void>;
  onSubmit: (text: string) => void;
  onStop: () => Promise<void>;
}

export function MobileChatPage({
  messages,
  isRunning,
  phase,
  plan,
  approvePlan,
  rejectPlan,
  pendingQuestion,
  respondToQuestion,
  onSubmit,
  onStop,
}: MobileChatPageProps) {
  const [value, setValue] = useState('');
  const scrollRef = useRef<HTMLDivElement>(null);

  // Auto-scroll to bottom on new messages
  useEffect(() => {
    if (scrollRef.current) {
      scrollRef.current.scrollTop = scrollRef.current.scrollHeight;
    }
  }, [messages, isRunning]);

  const handleSubmit = useCallback(() => {
    const trimmed = value.trim();
    if (!trimmed || isRunning) return;
    onSubmit(trimmed);
    setValue('');
  }, [value, isRunning, onSubmit]);

  const handleKeyDown = (e: React.KeyboardEvent) => {
    if (e.key === 'Enter' && !e.shiftKey) {
      e.preventDefault();
      handleSubmit();
    }
  };

  return (
    <div className="flex h-full flex-col">
      {/* Messages area */}
      <div ref={scrollRef} className="flex-1 overflow-y-auto px-4 py-3">
        {/* Message list */}
        <MessageList
          messages={messages}
          isRunning={isRunning}
          phase={phase}
          onApprovePlan={approvePlan}
          onRejectPlan={rejectPlan}
        />

        {/* Plan approval */}
        {phase === 'awaiting_approval' && plan && !isRunning && (
          <div className="my-3">
            <PlanApproval
              plan={plan}
              isWaitingApproval={true}
              onApprove={approvePlan}
              onReject={rejectPlan}
            />
          </div>
        )}

        {/* Question input */}
        {pendingQuestion && (
          <div className="my-3">
            <QuestionInput
              pendingQuestion={pendingQuestion}
              onSubmit={respondToQuestion}
            />
          </div>
        )}

        {/* Running indicator */}
        {isRunning && (
          <div className="my-3">
            <RunningIndicator messages={messages} phase={phase} />
          </div>
        )}
      </div>

      {/* Bottom input */}
      <div className="bg-background border-border/30 shrink-0 border-t px-4 pt-2 pb-[calc(8px+var(--safe-area-bottom))]">
        <div className="border-border bg-muted/30 flex items-end gap-2 rounded-2xl border px-4 py-2.5">
          <textarea
            value={value}
            onChange={(e) => setValue(e.target.value)}
            onKeyDown={handleKeyDown}
            placeholder={isRunning ? '等待回复...' : '继续对话...'}
            disabled={isRunning}
            className="text-foreground placeholder:text-muted-foreground max-h-32 min-h-[24px] flex-1 resize-none bg-transparent text-base leading-6 outline-none disabled:opacity-50"
            style={{ WebkitAppearance: 'none', backgroundColor: 'transparent' }}
            rows={1}
          />
          {isRunning ? (
            <button
              onClick={onStop}
              className="bg-destructive text-destructive-foreground flex size-8 shrink-0 items-center justify-center rounded-full"
            >
              <Square className="size-3.5" />
            </button>
          ) : (
            <button
              onClick={handleSubmit}
              disabled={!value.trim()}
              className="bg-primary text-primary-foreground flex size-8 shrink-0 items-center justify-center rounded-full disabled:opacity-30"
            >
              <Send className="size-4" />
            </button>
          )}
        </div>
      </div>
    </div>
  );
}
