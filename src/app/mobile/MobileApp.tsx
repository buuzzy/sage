/**
 * MobileApp — Root shell for narrow web/mobile layout.
 *
 * Single-page app with internal navigation:
 * - Home view (welcome + input)
 * - Chat view (messages + input)
 * - Drawer overlay (history list + settings entry)
 *
 * Shares all logic from useAgent, db, sync — only the UI layer is different.
 */

import { Component, useCallback, useEffect, useState, type ReactNode } from 'react';
import { useNavigate } from 'react-router-dom';
import { createSession, getAllTasks, type Task } from '@/shared/db';
import { isModelConfigured } from '@/shared/db/settings';
import { useAgent } from '@/shared/hooks/useAgent';
import {
  subscribeToBackgroundTasks,
  type BackgroundTask,
} from '@/shared/lib/background-tasks';
import { generateSessionId } from '@/shared/lib/session';
import { useLanguage } from '@/shared/providers/language-provider';

import { MobileChatPage } from './MobileChatPage';

// ─── Debug ErrorBoundary：捕获渲染异常并打印完整信息 ─────────────────────────
class MobileErrorBoundary extends Component<
  { children: ReactNode },
  { error: unknown; info: string }
> {
  state = { error: null as unknown, info: '' };

  static getDerivedStateFromError(error: unknown) {
    return { error };
  }

  componentDidCatch(error: unknown, errorInfo: { componentStack?: string }) {
    console.error('[MobileErrorBoundary] Caught render error:', error);
    console.error('[MobileErrorBoundary] Component stack:', errorInfo?.componentStack);
    console.error('[MobileErrorBoundary] Error type:', typeof error);
    console.error('[MobileErrorBoundary] Error constructor:', (error as any)?.constructor?.name);
    if (error instanceof Error) {
      console.error('[MobileErrorBoundary] Message:', error.message);
      console.error('[MobileErrorBoundary] Stack:', error.stack);
    } else {
      console.error('[MobileErrorBoundary] Raw error:', JSON.stringify(error, null, 2));
    }
    this.setState({ info: errorInfo?.componentStack || '' });
  }

  render() {
    if (this.state.error) {
      const errMsg = this.state.error instanceof Error
        ? this.state.error.message
        : JSON.stringify(this.state.error);
      return (
        <div className="flex h-full flex-col items-center justify-center p-6 text-center">
          <p className="text-destructive text-lg font-medium mb-2">渲染错误</p>
          <p className="text-muted-foreground text-sm mb-4 max-w-[300px] break-all">{errMsg}</p>
          <pre className="text-muted-foreground text-xs text-left max-w-full overflow-auto max-h-[200px] bg-muted p-3 rounded">
            {this.state.info}
          </pre>
          <button
            onClick={() => this.setState({ error: null, info: '' })}
            className="mt-4 bg-primary text-primary-foreground px-4 py-2 rounded-lg text-sm"
          >
            重试
          </button>
        </div>
      );
    }
    return this.props.children;
  }
}
import { MobileDrawer } from './MobileDrawer';
import { MobileHeader } from './MobileHeader';
import { MobileHomePage } from './MobileHomePage';
import { MobileSettings } from './MobileSettings';

export type MobileView = 'home' | 'chat' | 'settings';

export default function MobileApp() {
  const { t } = useLanguage();
  const navigate = useNavigate();

  // ─── State ──────────────────────────────────────────────────────────────────
  const [currentView, setCurrentView] = useState<MobileView>('home');
  const [currentTaskId, setCurrentTaskId] = useState<string | null>(null);
  const [drawerOpen, setDrawerOpen] = useState(false);
  const [tasks, setTasks] = useState<Task[]>([]);
  const [backgroundTasks, setBackgroundTasks] = useState<BackgroundTask[]>([]);

  // ─── useAgent ───────────────────────────────────────────────────────────────
  const {
    messages,
    isRunning,
    runAgent,
    continueConversation,
    stopAgent,
    loadTask,
    loadMessages,
    phase,
    plan,
    approvePlan,
    rejectPlan,
    pendingQuestion,
    respondToQuestion,
    generatedTitle,
  } = useAgent();

  // ─── Load tasks for drawer ──────────────────────────────────────────────────
  const loadTasks = useCallback(async () => {
    try {
      const all = await getAllTasks();
      setTasks(all);
    } catch (err) {
      console.error('[MobileApp] loadTasks error:', err);
    }
  }, []);

  useEffect(() => {
    loadTasks();
  }, [loadTasks]);

  useEffect(() => {
    return subscribeToBackgroundTasks((bt) => setBackgroundTasks(bt));
  }, []);

  // ─── Handlers ───────────────────────────────────────────────────────────────
  const handleNewChat = useCallback(() => {
    setCurrentTaskId(null);
    setCurrentView('home');
    setDrawerOpen(false);
  }, []);

  const handleSelectTask = useCallback(
    async (taskId: string) => {
      setDrawerOpen(false);
      setCurrentTaskId(taskId);
      setCurrentView('chat');
      await loadTask(taskId);
      await loadMessages(taskId);
    },
    [loadTask, loadMessages]
  );

  const handleSubmit = useCallback(
    async (prompt: string) => {
      try {
        console.log('[MobileApp] handleSubmit called with:', prompt);
        const sessionId = generateSessionId(prompt);
        console.log('[MobileApp] sessionId:', sessionId);

        // createSession may fail if user not bound (no auth) — non-blocking
        try {
          await createSession({ id: sessionId, prompt });
          console.log('[MobileApp] session created');
        } catch (e) {
          console.warn('[MobileApp] createSession failed (non-fatal):', e);
        }

        const taskId = Date.now().toString();
        setCurrentTaskId(taskId);
        setCurrentView('chat');
        console.log('[MobileApp] calling runAgent with taskId:', taskId);

        await runAgent(prompt, taskId, {
          sessionId,
          taskIndex: 1,
        });

        console.log('[MobileApp] runAgent completed');
        loadTasks();
      } catch (error) {
        console.error('[MobileApp] handleSubmit error:', error);
        const msg =
          error instanceof Error ? error.message : JSON.stringify(error);
        alert(`发送失败: ${msg}`);
      }
    },
    [runAgent, loadTasks]
  );

  const handleContinue = useCallback(
    async (reply: string) => {
      await continueConversation(reply);
    },
    [continueConversation]
  );

  // ─── Render ─────────────────────────────────────────────────────────────────
  const displayTitle = generatedTitle || (currentTaskId ? '对话' : 'Sage');

  // Settings view (full-screen, no header/drawer)
  if (currentView === 'settings') {
    return (
      <div className="bg-background flex h-screen flex-col pt-[var(--safe-area-top)]">
        <MobileSettings onClose={() => setCurrentView('home')} />
      </div>
    );
  }

  return (
    <div className="bg-background flex h-screen flex-col overflow-hidden pt-[var(--safe-area-top)]">
      {/* Header */}
      <MobileHeader
        title={currentView === 'home' ? 'Sage' : displayTitle}
        onMenuPress={() => setDrawerOpen(true)}
        showBack={currentView === 'chat'}
        onBackPress={handleNewChat}
      />

      {/* Content */}
      <div className="flex-1 overflow-hidden">
        {currentView === 'home' ? (
          <MobileHomePage
            onSubmit={handleSubmit}
            onOpenSettings={() => setCurrentView('settings')}
          />
        ) : (
          <MobileErrorBoundary>
            <MobileChatPage
              messages={messages}
              isRunning={isRunning}
              phase={phase}
              plan={plan}
              approvePlan={approvePlan}
              rejectPlan={rejectPlan}
              pendingQuestion={pendingQuestion}
              respondToQuestion={respondToQuestion}
              onSubmit={handleContinue}
              onStop={stopAgent}
            />
          </MobileErrorBoundary>
        )}
      </div>

      {/* Drawer Overlay */}
      <MobileDrawer
        open={drawerOpen}
        onClose={() => setDrawerOpen(false)}
        tasks={tasks}
        currentTaskId={currentTaskId}
        onSelectTask={handleSelectTask}
        onNewChat={handleNewChat}
        backgroundTasks={backgroundTasks}
      />
    </div>
  );
}
