/**
 * TaskGroupComponent — collapsible group of tool executions with a text header.
 */

import { useEffect, useState } from 'react';
import type { AgentMessage } from '@/shared/hooks/useAgent';
import { cn } from '@/shared/lib/utils';
import { useLanguage } from '@/shared/providers/language-provider';
import { CheckCircle2, ChevronDown } from 'lucide-react';

import { ToolExecutionItem } from '@/components/task/ToolExecutionItem';

function TaskGroupComponent({
  title,
  description,
  tools,
  isCompleted,
  isRunning,
  searchQuery,
}: {
  title: string;
  description: string;
  tools: {
    message: AgentMessage;
    globalIndex: number;
    result?: AgentMessage;
  }[];
  isCompleted: boolean;
  isRunning: boolean;
  searchQuery?: string;
}) {
  const { t } = useLanguage();
  // Default: collapsed when completed, expanded when running or in progress
  const [isExpanded, setIsExpanded] = useState(!isCompleted || isRunning);

  // Auto-collapse when task completes
  useEffect(() => {
    if (isCompleted && !isRunning) {
      setIsExpanded(false);
    }
  }, [isCompleted, isRunning]);

  return (
    <div className="min-w-0 space-y-3">
      {/* Task description with Logo */}
      {description && (
        <div className="flex min-w-0 flex-col gap-2">
          <div className="flex min-w-0 items-start gap-2">
            {isCompleted ? (
              <CheckCircle2 className="mt-0.5 size-4 shrink-0 text-emerald-500" />
            ) : (
              <div className="mt-0.5 flex size-4 shrink-0 items-center justify-center">
                <div className="bg-primary size-2 animate-pulse rounded-full" />
              </div>
            )}
            <span className="text-foreground line-clamp-2 min-w-0 text-sm font-medium wrap-break-word">
              {title}
            </span>
          </div>
        </div>
      )}

      {/* Collapsible tool list */}
      {tools.length > 0 && (
        <div className="border-border/40 bg-accent/20 min-w-0 overflow-hidden rounded-xl border">
          {/* Header */}
          <button
            onClick={() => setIsExpanded(!isExpanded)}
            className="text-muted-foreground hover:text-foreground hover:bg-accent/30 flex w-full cursor-pointer items-center gap-2 px-4 py-2.5 text-sm transition-colors"
          >
            <ChevronDown
              className={cn(
                'size-4 shrink-0 transition-transform',
                !isExpanded && '-rotate-90'
              )}
            />
            <span className="flex-1 text-left">
              {isExpanded
                ? t.task.hideSteps
                : t.task.showSteps.replace('{count}', String(tools.length))}
            </span>
          </button>

          {/* Tool list */}
          {isExpanded && (
            <div className="px-2 pb-2">
              {tools.map(({ message, globalIndex, result }, index) => (
                <ToolExecutionItem
                  key={globalIndex}
                  message={message}
                  result={result}
                  isFirst={index === 0}
                  isLast={
                    globalIndex === tools[tools.length - 1].globalIndex &&
                    isRunning
                  }
                  searchQuery={searchQuery}
                />
              ))}
            </div>
          )}
        </div>
      )}
    </div>
  );
}

export { TaskGroupComponent };
