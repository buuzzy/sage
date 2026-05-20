/**
 * MobileDrawer — overlay drawer with conversation history.
 * Slides in from the left, similar to ChatGPT iOS sidebar.
 */

import type { Task } from '@/shared/db';
import type { BackgroundTask } from '@/shared/lib/background-tasks';
import { cn } from '@/shared/lib/utils';
import { SquarePen } from 'lucide-react';

interface MobileDrawerProps {
  open: boolean;
  onClose: () => void;
  tasks: Task[];
  currentTaskId: string | null;
  onSelectTask: (id: string) => void;
  onNewChat: () => void;
  backgroundTasks: BackgroundTask[];
}

export function MobileDrawer({
  open,
  onClose,
  tasks,
  currentTaskId,
  onSelectTask,
  onNewChat,
  backgroundTasks,
}: MobileDrawerProps) {
  const runningIds = new Set(
    backgroundTasks.filter((t) => t.isRunning).map((t) => t.taskId)
  );

  return (
    <>
      {/* Backdrop */}
      {open && (
        <div
          className="fixed inset-0 z-40 bg-black/50 transition-opacity"
          onClick={onClose}
        />
      )}

      {/* Drawer panel */}
      <div
        className={cn(
          'bg-background fixed inset-y-0 left-0 z-50 flex w-[85vw] max-w-[320px] flex-col shadow-2xl transition-transform duration-300 ease-out',
          'pt-[var(--safe-area-top)] pb-[var(--safe-area-bottom)]',
          open ? 'translate-x-0' : '-translate-x-full'
        )}
      >
        {/* Header */}
        <div className="flex shrink-0 items-center justify-between px-5 py-4">
          <span className="text-foreground text-lg font-semibold">Sage</span>
          <button
            onClick={onNewChat}
            className="text-muted-foreground hover:text-foreground flex size-8 items-center justify-center rounded-lg"
          >
            <SquarePen className="size-5" />
          </button>
        </div>

        {/* Task list */}
        <div className="flex-1 overflow-y-auto px-3">
          <div className="text-muted-foreground mb-2 px-2 text-xs font-medium tracking-wider uppercase">
            对话
          </div>
          {tasks.length === 0 ? (
            <div className="text-muted-foreground px-2 py-8 text-center text-sm">
              暂无对话记录
            </div>
          ) : (
            <div className="space-y-0.5">
              {tasks.map((task) => (
                <button
                  key={task.id}
                  onClick={() => onSelectTask(task.id)}
                  className={cn(
                    'text-foreground flex w-full items-center gap-2 rounded-lg px-3 py-2.5 text-left text-sm transition-colors',
                    task.id === currentTaskId
                      ? 'bg-accent font-medium'
                      : 'hover:bg-accent/50'
                  )}
                >
                  <span className="min-w-0 flex-1 truncate">
                    {task.prompt?.slice(0, 40) || '新对话'}
                  </span>
                  {runningIds.has(task.id) && (
                    <span className="size-2 shrink-0 animate-pulse rounded-full bg-green-500" />
                  )}
                </button>
              ))}
            </div>
          )}
        </div>

        {/* Bottom: new chat FAB */}
        <div className="shrink-0 px-4 py-3">
          <button
            onClick={onNewChat}
            className="bg-primary text-primary-foreground flex w-full items-center justify-center gap-2 rounded-xl py-3 text-sm font-medium"
          >
            <SquarePen className="size-4" />
            新对话
          </button>
        </div>
      </div>
    </>
  );
}
