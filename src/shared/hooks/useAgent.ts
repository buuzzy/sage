import { useCallback, useEffect, useRef, useState } from 'react';
import { API_BASE_URL, API_PORT } from '@/config';
import { serializeToolMetadata } from '@/shared/config/artifactMapping';
import {
  createMessage,
  createTask,
  getMessagesByTaskId,
  getTask,
  updateTask,
  updateTaskFromMessage,
  type Task,
} from '@/shared/db';
import { getCurrentBoundUid } from '@/shared/db/database';
import { getSettings } from '@/shared/db/settings';
import {
  loadAttachments,
  saveAttachments,
  type AttachmentReference,
} from '@/shared/lib/attachments';
import {
  addBackgroundTask,
  getBackgroundTask,
  removeBackgroundTask,
  subscribeToBackgroundTasks,
  updateBackgroundTaskStatus,
  type BackgroundTask,
} from '@/shared/lib/background-tasks';
import { getAppDataDir } from '@/shared/lib/paths';
import { getCurrentAccessToken } from '@/shared/lib/supabase';
import { extractToolMetadata } from '@/shared/lib/toolMetadataExtractor';
import { getUserSessionsDir } from '@/shared/lib/user-scoped-paths';

import {
  getMcpConfig,
  getModelConfig,
  getPreferredLanguage,
  getSandboxConfig,
  getSkillsConfig,
} from './useAgent/config';
import { buildConversationHistory } from './useAgent/conversation';
import {
  classifyFetchError,
  fetchWithRetry,
  MODEL_EMPTY_RESPONSE_MESSAGE,
  throwForBadResponse,
} from './useAgent/errors';
import { extractAndSaveFiles, extractFilesFromText } from './useAgent/files';
import {
  applyAgentStrategyHint,
  classifyAgentExecutionStrategy,
} from './useAgent/strategy';
// Sub-module imports
import { sanitizeTitle } from './useAgent/title';
import type {
  AgentMessage,
  AgentPhase,
  AgentQuestion,
  MessageAttachment,
  PendingQuestion,
  PermissionRequest,
  SessionInfo,
  TaskPlan,
  UseAgentReturn,
} from './useAgent/types';

// Re-export types for backward compatibility
export type {
  PermissionRequest,
  QuestionOption,
  AgentQuestion,
  PendingQuestion,
  MessageAttachment,
  AgentMessage,
  PlanStep,
  TaskPlan,
  ConversationMessage,
  AgentPhase,
  SessionInfo,
  UseAgentReturn,
} from './useAgent/types';

// Re-export from sub-modules that external files might need
export type {
  AgentErrorCategory,
  ClassifiedAgentError,
} from './useAgent/types';

/**
 * 计算当前用户的 sessions 目录：`~/.sage/users/{uid}/sessions`。
 * 若尚未绑定 user（理论上不该发生在已登录态），回退到 legacy 共享目录
 * `~/.sage/sessions`，保证不崩溃但打印警告。
 */
async function getSessionsBaseDir(): Promise<string> {
  const uid = getCurrentBoundUid();
  if (uid) {
    return getUserSessionsDir(uid);
  }
  console.warn(
    '[useAgent] no bound user, falling back to legacy shared sessions dir'
  );
  const appDir = await getAppDataDir();
  return `${appDir}/sessions`;
}

const AGENT_SERVER_URL = API_BASE_URL;

// ─── 通用请求 header（非 Tauri 时自动注入 Bearer token）─────
const isTauriEnv =
  typeof window !== 'undefined' && '__TAURI_INTERNALS__' in window;

// Auth strategy for non-Tauri environments (Web):
// 1. Prefer: Supabase JWT from getCurrentAccessToken() (user-scoped)
// 2. Fallback: VITE_RAILWAY_API_TOKEN env var (for testing/CI)
//
// For Railway backend (cloud) deployment, either strategy works:
// - Supabase JWT: validated against supabase instance
// - Railway token: validated against SAGE_API_TOKEN environment variable
//
// See: CLAUDE.md > API Key 管理 section for token lifecycle

async function getRequestHeaders(): Promise<Record<string, string>> {
  const headers: Record<string, string> = {
    'Content-Type': 'application/json',
  };
  // Non-Tauri (Web) → Railway cloud backend requires Bearer auth
  if (!isTauriEnv) {
    // Try Supabase JWT first (preferred for authenticated users)
    const supabaseToken = await getCurrentAccessToken();
    if (supabaseToken) {
      headers['Authorization'] = `Bearer ${supabaseToken}`;
    } else {
      // Fallback to environment variable (for testing/CI)
      const fallbackToken = import.meta.env.VITE_RAILWAY_API_TOKEN;
      if (fallbackToken) {
        headers['Authorization'] = `Bearer ${fallbackToken}`;
        if (!import.meta.env.PROD) {
          console.warn(
            '[API] No Supabase token available, using VITE_RAILWAY_API_TOKEN fallback'
          );
        }
      }
    }
  }
  return headers;
}

console.log(
  `[API] Environment: ${import.meta.env.PROD ? 'production' : 'development'}, Port: ${API_PORT}`
);

export function useAgent(): UseAgentReturn {
  const [messages, setMessages] = useState<AgentMessage[]>([]);
  const [isRunning, setIsRunning] = useState(false);
  const [taskId, setTaskId] = useState<string | null>(null);
  const [initialPrompt, setInitialPrompt] = useState<string>('');
  const [pendingPermission, setPendingPermission] =
    useState<PermissionRequest | null>(null);
  const [pendingQuestion, setPendingQuestion] =
    useState<PendingQuestion | null>(null);
  const [phase, setPhase] = useState<AgentPhase>('idle');
  const [plan, setPlan] = useState<TaskPlan | null>(null);
  // Session management
  const [currentSessionId, setCurrentSessionId] = useState<string | null>(null);
  const [currentTaskIndex, setCurrentTaskIndex] = useState<number>(1);
  // Track file changes to trigger refresh in UI
  const [filesVersion, setFilesVersion] = useState<number>(0);
  // Generated title from LLM summarization, scoped to the task that requested it.
  const [generatedTitleResult, setGeneratedTitleResult] = useState<{
    taskId: string;
    title: string;
  } | null>(null);
  const [sessionFolder, setSessionFolder] = useState<string | null>(null);
  const sessionIdRef = useRef<string | null>(null); // Backend session ID for API calls
  const abortControllerRef = useRef<AbortController | null>(null);
  const activeTaskIdRef = useRef<string | null>(null); // Track which task is currently active (for message isolation)
  const refreshIntervalRef = useRef<NodeJS.Timeout | null>(null); // For polling messages when restored from background
  // Use refs to track current values for callbacks (to avoid stale closures)
  const taskIdRef = useRef<string | null>(null);
  const isRunningRef = useRef<boolean>(false);
  const initialPromptRef = useRef<string>('');

  // Keep refs in sync with state (for use in callbacks to avoid stale closures)
  useEffect(() => {
    taskIdRef.current = taskId;
  }, [taskId]);

  useEffect(() => {
    isRunningRef.current = isRunning;
  }, [isRunning]);

  useEffect(() => {
    initialPromptRef.current = initialPrompt;
  }, [initialPrompt]);

  // Helper to set session info
  const setSessionInfo = useCallback((sessionId: string, taskIndex: number) => {
    setCurrentSessionId(sessionId);
    setCurrentTaskIndex(taskIndex);
  }, []);

  // Load existing task from database
  // This function handles task switching (moving running task to background)
  // and loading task metadata. Message loading and background restoration is done by loadMessages.
  const loadTask = useCallback(async (id: string): Promise<Task | null> => {
    // If there's a running task, move it to background instead of aborting
    // Use refs to get current values (avoid stale closures)
    const currentTaskId = taskIdRef.current;
    const currentIsRunning = isRunningRef.current;
    const currentPrompt = initialPromptRef.current;

    if (
      abortControllerRef.current &&
      currentTaskId &&
      currentIsRunning &&
      currentTaskId !== id
    ) {
      console.log('[useAgent] Moving task to background:', currentTaskId);
      addBackgroundTask({
        taskId: currentTaskId,
        sessionId: sessionIdRef.current || '',
        abortController: abortControllerRef.current,
        isRunning: true,
        prompt: currentPrompt,
      });
      // Clear refs but don't abort - task continues in background
      abortControllerRef.current = null;
      sessionIdRef.current = null;

      // Clear UI state for the old task
      setMessages([]);
      setPendingPermission(null);
      setPendingQuestion(null);
      setPlan(null);
    }

    // Stop any existing polling from previous task
    if (refreshIntervalRef.current) {
      clearInterval(refreshIntervalRef.current);
      refreshIntervalRef.current = null;
    }

    // Set this as the active task
    activeTaskIdRef.current = id;

    // Pre-emptively restore running state if this task is in the background.
    // This eliminates the brief "idle" flash that would otherwise appear between
    // this synchronous step and the async loadMessages() call that follows.
    const preCheckBgTask = getBackgroundTask(id);
    if (
      preCheckBgTask &&
      preCheckBgTask.isRunning &&
      !preCheckBgTask.abortController.signal.aborted
    ) {
      setIsRunning(true);
      isRunningRef.current = true;
      setPhase('executing');
    }

    try {
      const task = await getTask(id);
      if (task) {
        setInitialPrompt(task.prompt);

        // Set session info if available from the task
        if (task.session_id) {
          setCurrentSessionId(task.session_id);
          setCurrentTaskIndex(task.task_index || 1);

          // Compute and set session folder
          try {
            const base = await getSessionsBaseDir();
            const computedSessionFolder = `${base}/${task.session_id}`;
            setSessionFolder(computedSessionFolder);
            console.log(
              '[useAgent] Loaded sessionFolder from task:',
              computedSessionFolder
            );
          } catch (error) {
            console.error('Failed to compute session folder:', error);
          }
        }
      }
      return task;
    } catch (error) {
      console.error('Failed to load task:', error);
      return null;
    }
  }, []);

  // Load existing messages from database
  const loadMessages = useCallback(async (id: string): Promise<void> => {
    // Note: Task switching logic is handled by loadTask, not here
    // This function just loads messages for the specified task

    // Check if the task we're loading is running in background
    const backgroundTask = getBackgroundTask(id);
    const isRestoringFromBackground =
      backgroundTask && backgroundTask.isRunning;

    // Get task status to determine if plan should be restored
    const task = await getTask(id);
    const taskIsCompleted = task && task.status === 'completed';
    const taskIsStopped = task && task.status === 'stopped';

    console.log('[useAgent] loadMessages:', {
      taskId: id,
      taskStatus: task?.status,
      taskIsCompleted,
      hasBackgroundTask: !!backgroundTask,
      backgroundTaskIsRunning: backgroundTask?.isRunning,
      isRestoringFromBackground,
    });

    if (isRestoringFromBackground) {
      console.log(
        '[useAgent] Task is running in background (loadMessages), restoring:',
        id
      );
      abortControllerRef.current = backgroundTask.abortController;
      sessionIdRef.current = backgroundTask.sessionId;

      // Check if the abort controller is still valid (stream still running)
      if (abortControllerRef.current.signal.aborted) {
        console.log('[useAgent] Background task was already completed/aborted');
        setIsRunning(false);
        setPhase('idle');
        abortControllerRef.current = null;
        removeBackgroundTask(id);
      } else {
        setIsRunning(true);
        isRunningRef.current = true; // Sync update ref immediately to avoid race condition
        setPhase('executing'); // Note: might not be accurate if task was in planning phase
        // Delay removal from background tasks to avoid UI flicker
        // This ensures isRunning state is updated before task is removed from backgroundTasks
        setTimeout(() => {
          removeBackgroundTask(id);
        }, 50);

        // Start polling for new messages (messages will be loaded immediately below)
        if (refreshIntervalRef.current) {
          clearInterval(refreshIntervalRef.current);
        }
        const pollingTaskId = id;
        let lastMessageCount = 0;
        let stuckCount = 0; // Count how many polls without new messages
        // Long timeout for stuck detection - tools like Bash can take many minutes
        // The DB status check (completed/error/stopped) is the primary termination path.
        // This counter is only a last-resort safety net for truly hung tasks.
        const MAX_STUCK_COUNT = 1800; // Stop after 30 minutes of no progress

        refreshIntervalRef.current = setInterval(async () => {
          const isStillActive = activeTaskIdRef.current === pollingTaskId;

          // Check abort signal
          if (
            !abortControllerRef.current ||
            abortControllerRef.current.signal.aborted
          ) {
            if (refreshIntervalRef.current) {
              clearInterval(refreshIntervalRef.current);
              refreshIntervalRef.current = null;
            }
            if (isStillActive) {
              setIsRunning(false);
              setPhase('idle');
            }
            return;
          }

          // Also check task status in database - it might have completed
          try {
            const taskStatus = await getTask(pollingTaskId);
            if (
              taskStatus &&
              ['completed', 'error', 'stopped'].includes(taskStatus.status)
            ) {
              console.log(
                '[useAgent] Task completed in database, stopping poll:',
                taskStatus.status
              );
              if (refreshIntervalRef.current) {
                clearInterval(refreshIntervalRef.current);
                refreshIntervalRef.current = null;
              }
              if (isStillActive) {
                setIsRunning(false);
                setPhase('idle');
              }
              return;
            }
          } catch (error) {
            console.error('[useAgent] Failed to check task status:', error);
          }

          if (isStillActive) {
            // Refresh messages from database
            try {
              const dbMessages = await getMessagesByTaskId(pollingTaskId);
              const agentMessages: AgentMessage[] = dbMessages.map((msg) => {
                // Special handling for plan messages - parse the plan JSON
                if (msg.type === 'plan' && msg.content) {
                  try {
                    const planData = JSON.parse(msg.content) as TaskPlan;
                    return {
                      type: 'plan' as const,
                      plan: planData,
                    };
                  } catch {
                    // If parse fails, return basic message
                    return {
                      type: msg.type as AgentMessage['type'],
                      content: msg.content || undefined,
                    };
                  }
                }
                // Default handling for other message types
                return {
                  type: msg.type as AgentMessage['type'],
                  content: msg.content || undefined,
                  name: msg.tool_name || undefined,
                  input: msg.tool_input
                    ? JSON.parse(msg.tool_input)
                    : undefined,
                  output: msg.tool_output || undefined,
                  toolUseId: msg.tool_use_id || undefined,
                  subtype: msg.subtype as AgentMessage['subtype'],
                  message: msg.error_message || undefined,
                };
              });
              setMessages(agentMessages);

              // Check if there are pending tools (tool_use without matching tool_result)
              const toolUseIds = new Set<string>();
              const toolResultIds = new Set<string>();
              for (const msg of dbMessages) {
                if (msg.type === 'tool_use' && msg.tool_use_id) {
                  toolUseIds.add(msg.tool_use_id);
                } else if (msg.type === 'tool_result' && msg.tool_use_id) {
                  toolResultIds.add(msg.tool_use_id);
                }
              }
              const hasPendingTools = [...toolUseIds].some(
                (id) => !toolResultIds.has(id)
              );

              // Check if we're stuck (no new messages for too long AND no pending tools)
              if (dbMessages.length === lastMessageCount) {
                // Only count as stuck if there are no pending tools
                if (!hasPendingTools) {
                  stuckCount++;
                  if (stuckCount >= MAX_STUCK_COUNT) {
                    console.log(
                      '[useAgent] Task appears stuck, stopping poll after',
                      MAX_STUCK_COUNT,
                      'seconds'
                    );
                    if (refreshIntervalRef.current) {
                      clearInterval(refreshIntervalRef.current);
                      refreshIntervalRef.current = null;
                    }
                    setIsRunning(false);
                    setPhase('idle');
                    return;
                  }
                } else {
                  // Tools are pending, reset stuck counter
                  stuckCount = 0;
                }
              } else {
                // Got new messages, reset stuck counter
                stuckCount = 0;
                lastMessageCount = dbMessages.length;
              }
            } catch (error) {
              console.error('[useAgent] Failed to refresh messages:', error);
            }
          }
        }, 1000);
      }
    } else {
      // Task is NOT running in background - it's a completed/stopped task
      // Reset running state to ensure we don't show running indicators
      console.log('[useAgent] Loading messages for completed task:', id);
      setIsRunning(false);
      setPhase('idle');
      abortControllerRef.current = null;

      // Stop any existing polling
      if (refreshIntervalRef.current) {
        clearInterval(refreshIntervalRef.current);
        refreshIntervalRef.current = null;
      }
    }

    // Set this as the active task
    activeTaskIdRef.current = id;

    try {
      const dbMessages = await getMessagesByTaskId(id);

      // First pass: identify user messages with attachments that need loading
      const attachmentLoadTasks: {
        index: number;
        refs: AttachmentReference[];
      }[] = [];

      for (let i = 0; i < dbMessages.length; i++) {
        const msg = dbMessages[i];
        if (msg.type === 'user' && msg.attachments) {
          try {
            const refs = JSON.parse(msg.attachments) as AttachmentReference[];
            // Check if it's the new format (has path)
            if (refs.length > 0 && 'path' in refs[0]) {
              attachmentLoadTasks.push({ index: i, refs });
            }
          } catch {
            // Ignore parse errors
          }
        }
      }

      // Build agent messages immediately with placeholder attachments
      const agentMessages: AgentMessage[] = [];
      for (let i = 0; i < dbMessages.length; i++) {
        const msg = dbMessages[i];
        if (msg.type === 'user') {
          // Check if this message has attachments to load
          const loadTask = attachmentLoadTasks.find((t) => t.index === i);
          let attachments: MessageAttachment[] | undefined;

          if (loadTask) {
            // Create placeholder attachments (loading state)
            attachments = loadTask.refs.map((ref) => ({
              id: ref.id,
              type: ref.type,
              name: ref.name,
              data: '', // Empty data, will be loaded later
              mimeType: ref.mimeType,
              path: ref.path,
              isLoading: true,
            }));
          } else if (msg.attachments) {
            // Try old format
            try {
              const refs = JSON.parse(msg.attachments) as AttachmentReference[];
              if (refs.length > 0 && !('path' in refs[0])) {
                attachments = refs as unknown as MessageAttachment[];
              }
            } catch {
              // Ignore parse errors
            }
          }

          agentMessages.push({
            type: 'user' as const,
            content: msg.content || undefined,
            attachments,
          });
        } else if (msg.type === 'text') {
          agentMessages.push({
            type: 'text' as const,
            content: msg.content || undefined,
          });
        } else if (msg.type === 'tool_use') {
          agentMessages.push({
            type: 'tool_use' as const,
            name: msg.tool_name || undefined,
            input: msg.tool_input ? JSON.parse(msg.tool_input) : undefined,
          });
        } else if (msg.type === 'tool_result') {
          agentMessages.push({
            type: 'tool_result' as const,
            toolUseId: msg.tool_use_id || undefined,
            output: msg.tool_output || undefined,
            toolMetadata: msg.tool_metadata || undefined,
          });
        } else if (msg.type === 'result') {
          agentMessages.push({
            type: 'result' as const,
            subtype: msg.subtype || undefined,
          });
        } else if (msg.type === 'error') {
          agentMessages.push({
            type: 'error' as const,
            message: msg.error_message || undefined,
          });
        } else if (msg.type === 'plan') {
          // Restore plan message with parsed plan data
          try {
            const planData = msg.content
              ? (JSON.parse(msg.content) as TaskPlan)
              : undefined;
            if (planData) {
              // Determine how to mark plan steps based on task status
              let restoredPlan: TaskPlan;
              if (taskIsStopped && !isRestoringFromBackground) {
                // Task was cancelled - mark steps as cancelled
                restoredPlan = {
                  ...planData,
                  steps: planData.steps.map((s) => ({
                    ...s,
                    status: 'cancelled' as const,
                  })),
                };
              } else if (taskIsCompleted && !isRestoringFromBackground) {
                // Task completed - mark steps as completed
                restoredPlan = {
                  ...planData,
                  steps: planData.steps.map((s) => ({
                    ...s,
                    status: 'completed' as const,
                  })),
                };
              } else {
                // Task in progress or awaiting approval - keep original status
                restoredPlan = planData;
              }
              agentMessages.push({
                type: 'plan' as const,
                plan: restoredPlan,
              });
            }
          } catch {
            // Ignore parse errors
          }
        } else {
          agentMessages.push({ type: msg.type as AgentMessage['type'] });
        }
      }

      // Set messages immediately (with loading placeholders for attachments)
      setMessages(agentMessages);
      setTaskId(id);

      // Check if task has a pending plan awaiting approval
      // Only restore if NOT running in background (running tasks already have plan approved)
      if (!isRestoringFromBackground) {
        const lastPlanMessage = [...agentMessages]
          .reverse()
          .find((m) => m.type === 'plan' && m.plan);
        if (
          lastPlanMessage &&
          lastPlanMessage.type === 'plan' &&
          lastPlanMessage.plan
        ) {
          const planSteps = lastPlanMessage.plan.steps || [];
          // Check if plan has incomplete steps (pending or no status)
          const hasIncompleteSteps = planSteps.some(
            (s) => !s.status || s.status === 'pending'
          );

          // Restore plan if task is not completed/stopped and has incomplete steps
          if (hasIncompleteSteps && !taskIsCompleted && !taskIsStopped) {
            console.log(
              '[useAgent] Restoring plan awaiting approval for task:',
              id,
              {
                planSteps: planSteps.map((s) => ({
                  description: s.description,
                  status: s.status,
                })),
              }
            );
            setPlan(lastPlanMessage.plan);
            setPhase('awaiting_approval');
          }
        }
      }

      // Load attachments asynchronously in background
      if (attachmentLoadTasks.length > 0) {
        // Use setTimeout to ensure this runs after the initial render
        setTimeout(async () => {
          // Check if we're still on the same task
          if (activeTaskIdRef.current !== id) return;

          const MESSAGE_CONCURRENCY = 2;

          for (
            let i = 0;
            i < attachmentLoadTasks.length;
            i += MESSAGE_CONCURRENCY
          ) {
            // Check again if task changed
            if (activeTaskIdRef.current !== id) return;

            const batch = attachmentLoadTasks.slice(i, i + MESSAGE_CONCURRENCY);
            const results = await Promise.all(
              batch.map(async ({ index, refs }) => {
                const attachments = await loadAttachments(refs);
                return { index, attachments };
              })
            );

            // Update messages with loaded attachments
            setMessages((prevMessages) => {
              // Check if still on same task
              if (activeTaskIdRef.current !== id) return prevMessages;

              const newMessages = [...prevMessages];
              for (const { index, attachments } of results) {
                // Find user message with loading attachments that matches this index
                const task = attachmentLoadTasks.find((t) => t.index === index);
                if (!task) continue;

                for (let j = 0; j < newMessages.length; j++) {
                  const msg = newMessages[j];
                  if (
                    msg.type === 'user' &&
                    msg.attachments?.some((a) => a.isLoading) &&
                    msg.attachments?.length === task.refs.length &&
                    // Match by first attachment id
                    msg.attachments[0]?.id === task.refs[0]?.id
                  ) {
                    // Match found, update attachments
                    newMessages[j] = {
                      ...msg,
                      attachments: attachments.map((a) => ({
                        ...a,
                        isLoading: false,
                      })),
                    };
                    break;
                  }
                }
              }
              return newMessages;
            });
          }
        }, 0);
      }
    } catch (error) {
      console.error('Failed to load messages:', error);
    }
  }, []);

  // Process SSE stream
  const processStream = useCallback(
    async (
      response: Response,
      currentTaskId: string,
      _abortController: AbortController
    ) => {
      const reader = response.body?.getReader();
      if (!reader) {
        throw new Error('No response body');
      }

      const decoder = new TextDecoder();
      let buffer = '';

      // Track pending tool_use messages to match with tool_result
      const pendingToolUses: Map<
        string,
        { name: string; input: Record<string, unknown> }
      > = new Map();

      // Track tool execution progress for updating plan steps
      let completedToolCount = 0;
      let totalToolCount = 0;
      let sawToolActivity = false;
      let sawFinalTextAfterTool = false;
      let finalResultSubtype: string | undefined;
      let sawTerminalError = false;
      let sawResultMessage = false;
      let sawVisibleStreamOutput = false;

      // Helper to check if this stream is still for the active task
      const isActiveTask = () => activeTaskIdRef.current === currentTaskId;

      while (true) {
        const { done, value } = await reader.read();
        if (done) break;

        // Note: We no longer cancel the reader when task switches.
        // Background tasks continue to process the stream and save to database.
        // UI updates are skipped for inactive tasks via isActiveTask() checks below.

        buffer += decoder.decode(value, { stream: true });
        const lines = buffer.split('\n');
        buffer = lines.pop() || '';

        for (const line of lines) {
          if (line.startsWith('data: ')) {
            try {
              const data = JSON.parse(line.slice(6)) as AgentMessage;

              // Check if this is the active task for UI updates
              const isActive = isActiveTask();

              if (data.type === 'session') {
                if (isActive) {
                  sessionIdRef.current = data.sessionId || null;
                }
              } else if (data.type === 'done') {
                if (!sawVisibleStreamOutput && !sawTerminalError) {
                  const fallbackMessage: AgentMessage = {
                    type: 'error',
                    message: MODEL_EMPTY_RESPONSE_MESSAGE,
                  };
                  if (isActive) {
                    setMessages((prev) => [...prev, fallbackMessage]);
                  }
                  try {
                    await createMessage({
                      task_id: currentTaskId,
                      type: 'error',
                      error_message: MODEL_EMPTY_RESPONSE_MESSAGE,
                    });
                    await updateTask(currentTaskId, { status: 'error' });
                  } catch (dbError) {
                    console.error(
                      'Failed to save empty stream fallback:',
                      dbError
                    );
                  }
                } else if (
                  sawToolActivity &&
                  !sawFinalTextAfterTool &&
                  !sawTerminalError
                ) {
                  const reason =
                    finalResultSubtype && finalResultSubtype !== 'success'
                      ? `本轮执行结束状态：${finalResultSubtype}。`
                      : '本轮工具检索已经结束，但模型没有生成最终总结。';
                  const fallbackMessage: AgentMessage = {
                    type: 'text',
                    content:
                      `${reason}\n\n` +
                      '我已经停止继续调用工具，避免空转。你可以直接让我“基于已检索结果总结”，或把范围缩小后继续追问。',
                  };
                  if (isActive) {
                    setMessages((prev) => [...prev, fallbackMessage]);
                  }
                  try {
                    await createMessage({
                      task_id: currentTaskId,
                      type: 'text',
                      content: fallbackMessage.content,
                    });
                  } catch (dbError) {
                    console.error('Failed to save fallback message:', dbError);
                  }
                }
                if (sawToolActivity && !sawResultMessage && !sawTerminalError) {
                  try {
                    await updateTask(currentTaskId, { status: 'stopped' });
                  } catch (dbError) {
                    console.error('Failed to mark task stopped:', dbError);
                  }
                }

                // Update background task status (always, even if not active)
                updateBackgroundTaskStatus(currentTaskId, false);

                // UI updates only for active task
                if (isActive) {
                  // Stream ended - mark all plan steps as completed
                  setPendingPermission(null);
                  setPlan((currentPlan) => {
                    if (!currentPlan) return currentPlan;
                    return {
                      ...currentPlan,
                      steps: currentPlan.steps.map((step) => ({
                        ...step,
                        status: 'completed' as const,
                      })),
                    };
                  });
                }
              } else if (data.type === 'permission_request') {
                // Handle permission request - only for active task
                if (isActive && data.permission) {
                  setPendingPermission(data.permission);
                  setMessages((prev) => [...prev, data]);
                }
              } else if (data.type === 'session_action') {
                // /new or /reset: clear current session messages
                if (
                  isActive &&
                  (data.action === 'new' || data.action === 'reset')
                ) {
                  console.log(`[useAgent] Session action: ${data.action}`);
                  try {
                    const { deleteMessagesByTaskId } =
                      await import('@/shared/db');
                    await deleteMessagesByTaskId(currentTaskId);
                    setMessages([]);
                    // Also delete from backend channel-store so useChannelSync
                    // won't re-populate the cleared messages within 3 seconds
                    fetch(
                      `${AGENT_SERVER_URL}/channels/conversations/${currentTaskId}`,
                      { method: 'DELETE' }
                    ).catch(() => {});
                    // Mark as deleted in sessionStorage so sync ignores it even if backend still has it
                    const { markChannelTaskDeleted } =
                      await import('@/shared/hooks/useChannelSync');
                    markChannelTaskDeleted(currentTaskId);
                  } catch (err) {
                    console.error('[useAgent] Failed to clear messages:', err);
                  }
                }
              } else if (data.type === 'compact_result' && data.conversation) {
                // Legacy: /compact command replace (no longer used, kept for compat)
                if (isActive) {
                  console.log(
                    '[useAgent] Compact result received, replacing conversation with',
                    (data.conversation as unknown[]).length,
                    'messages'
                  );
                  // Replace messages in DB: delete old messages and insert compacted ones
                  try {
                    const { deleteMessagesByTaskId, createMessage } =
                      await import('@/shared/db');
                    await deleteMessagesByTaskId(currentTaskId);
                    const compactedConv = data.conversation as Array<{
                      role: string;
                      content: string;
                    }>;
                    for (const msg of compactedConv) {
                      await createMessage({
                        task_id: currentTaskId,
                        type: msg.role === 'user' ? 'user' : 'text',
                        content: msg.content,
                      });
                    }
                    // Reload messages in UI (map DB Message → AgentMessage to align types)
                    const { getMessagesByTaskId } = await import('@/shared/db');
                    const freshMessages =
                      await getMessagesByTaskId(currentTaskId);
                    const agentMsgs: AgentMessage[] = freshMessages.map(
                      (msg) => ({
                        type: msg.type as AgentMessage['type'],
                        content: msg.content ?? undefined,
                        name: msg.tool_name ?? undefined,
                        output: msg.tool_output ?? undefined,
                        toolUseId: msg.tool_use_id ?? undefined,
                        subtype: msg.subtype as AgentMessage['subtype'],
                      })
                    );
                    setMessages(agentMsgs);
                  } catch (err) {
                    console.error(
                      '[useAgent] Failed to apply compact result:',
                      err
                    );
                  }
                }
              } else {
                if (data.type === 'tool_use' || data.type === 'tool_result') {
                  sawToolActivity = true;
                  sawFinalTextAfterTool = false;
                } else if (
                  data.type === 'text' &&
                  data.content &&
                  !data.content.trim().startsWith('```artifact:')
                ) {
                  sawFinalTextAfterTool = true;
                } else if (data.type === 'result') {
                  finalResultSubtype = data.content || data.subtype;
                  sawResultMessage = true;
                } else if (data.type === 'error') {
                  sawTerminalError = true;
                }

                if (
                  (data.type === 'text' && Boolean(data.content?.trim())) ||
                  data.type === 'tool_use' ||
                  data.type === 'tool_result' ||
                  data.type === 'permission_request' ||
                  data.type === 'error'
                ) {
                  sawVisibleStreamOutput = true;
                }

                // UI update only for active task
                if (isActive) {
                  // For tool_result messages, extract metadata for artifact mapping
                  let messageToAdd = data;
                  if (data.type === 'tool_result' && data.output && data.name) {
                    const metadata = extractToolMetadata(
                      data.output,
                      data.name
                    );
                    if (metadata) {
                      messageToAdd = {
                        ...data,
                        toolMetadata: serializeToolMetadata(metadata),
                      };
                    }
                  }
                  setMessages((prev) => [...prev, messageToAdd]);
                }

                // Extract file paths from text messages
                if (data.type === 'text' && data.content) {
                  await extractFilesFromText(currentTaskId, data.content);
                }

                // Track tool_use messages for file extraction
                if (data.type === 'tool_use' && data.name) {
                  const toolUseId =
                    (data as { id?: string }).id || `tool_${Date.now()}`;
                  pendingToolUses.set(toolUseId, {
                    name: data.name,
                    input: (data.input as Record<string, unknown>) || {},
                  });
                  totalToolCount++;

                  // Handle AskUserQuestion tool - show question UI and pause execution
                  // Only handle for active task to avoid affecting wrong task's UI
                  if (
                    isActive &&
                    data.name === 'AskUserQuestion' &&
                    data.input
                  ) {
                    const input = data.input as { questions?: AgentQuestion[] };
                    if (input.questions && Array.isArray(input.questions)) {
                      setPendingQuestion({
                        id: `question_${Date.now()}`,
                        toolUseId,
                        questions: input.questions,
                      });
                      // Stop agent execution and wait for user response
                      // The user's answer will be sent via continueConversation
                      console.log(
                        '[useAgent] AskUserQuestion detected, pausing execution'
                      );
                      setIsRunning(false);
                      if (abortControllerRef.current) {
                        abortControllerRef.current.abort();
                        abortControllerRef.current = null;
                      }
                      // Also stop backend agent
                      if (sessionIdRef.current) {
                        getRequestHeaders().then(headers => fetch(
                          `${AGENT_SERVER_URL}/agent/stop/${sessionIdRef.current}`,
                          {
                            method: 'POST',
                            headers,
                          }
                        )).catch(() => {});
                      }
                      reader.cancel();
                      return; // Stop processing this stream
                    }
                  }
                }

                // When we get a tool_result, extract files from the matched tool_use
                if (data.type === 'tool_result' && data.toolUseId) {
                  const toolUse = pendingToolUses.get(data.toolUseId);
                  if (toolUse) {
                    await extractAndSaveFiles(
                      currentTaskId,
                      toolUse.name,
                      toolUse.input,
                      data.output
                    );
                    pendingToolUses.delete(data.toolUseId);

                    // Trigger working files refresh for file-writing tools
                    const fileWritingTools = [
                      'Write',
                      'Edit',
                      'Bash',
                      'NotebookEdit',
                    ];
                    if (
                      fileWritingTools.includes(toolUse.name) ||
                      toolUse.name.includes('sandbox')
                    ) {
                      setFilesVersion((v) => v + 1);
                    }
                  }

                  // Update plan step progress
                  completedToolCount++;
                  setPlan((currentPlan) => {
                    if (!currentPlan || !currentPlan.steps.length)
                      return currentPlan;

                    const stepCount = currentPlan.steps.length;
                    // Calculate how many steps should be completed based on tool progress
                    // Use a heuristic: distribute tool completions across steps
                    const progressRatio =
                      completedToolCount /
                      Math.max(totalToolCount, stepCount * 2);
                    const completedSteps = Math.min(
                      Math.floor(progressRatio * stepCount),
                      stepCount - 1 // Keep at least one step as in_progress until done
                    );

                    const updatedSteps = currentPlan.steps.map(
                      (step, index) => {
                        if (index < completedSteps) {
                          return { ...step, status: 'completed' as const };
                        } else if (index === completedSteps) {
                          return { ...step, status: 'in_progress' as const };
                        }
                        return { ...step, status: 'pending' as const };
                      }
                    );

                    return { ...currentPlan, steps: updatedSteps };
                  });
                }

                // Save message to database
                try {
                  // Extract tool metadata for artifact mapping
                  let toolMetadata: string | undefined;
                  if (data.type === 'tool_result' && data.output && data.name) {
                    const metadata = extractToolMetadata(
                      data.output,
                      data.name
                    );
                    if (metadata) {
                      toolMetadata = serializeToolMetadata(metadata);
                    }
                  }

                  await createMessage({
                    task_id: currentTaskId,
                    type: data.type as
                      | 'text'
                      | 'tool_use'
                      | 'tool_result'
                      | 'result'
                      | 'error'
                      | 'user',
                    content: data.content,
                    tool_name: data.name,
                    tool_input: data.input
                      ? JSON.stringify(data.input)
                      : undefined,
                    tool_output: data.output,
                    tool_use_id: data.toolUseId,
                    tool_metadata: toolMetadata,
                    subtype: data.subtype,
                    error_message: data.message,
                  });

                  // Update task status based on message
                  await updateTaskFromMessage(
                    currentTaskId,
                    data.type,
                    data.subtype,
                    data.cost,
                    data.duration
                  );
                } catch (dbError) {
                  console.error('Failed to save message:', dbError);
                }
              }
            } catch {
              // Ignore parse errors
            }
          }
        }
      }
    },
    []
  );

  // Phase 1: Planning - get a plan from the agent
  const runAgent = useCallback(
    async (
      prompt: string,
      existingTaskId?: string,
      sessionInfo?: SessionInfo,
      attachments?: MessageAttachment[],
      _mode?: 'auto' | 'chat' | 'task'
    ): Promise<string> => {
      // If there's already a running task, move it to background
      if (isRunning && abortControllerRef.current && taskId) {
        console.log(
          '[useAgent] Moving current task to background before starting new:',
          taskId
        );
        addBackgroundTask({
          taskId: taskId,
          sessionId: sessionIdRef.current || '',
          abortController: abortControllerRef.current,
          isRunning: true,
          prompt: initialPrompt,
        });
        abortControllerRef.current = null;
        sessionIdRef.current = null;
      }

      setIsRunning(true);
      isRunningRef.current = true; // Sync update ref immediately
      setMessages([]);
      setInitialPrompt(prompt);
      setPhase('planning');
      setPlan(null);

      // Handle session info
      const sessId = sessionInfo?.sessionId || currentSessionId || '';
      const taskIdx = sessionInfo?.taskIndex || currentTaskIndex;

      if (sessionInfo) {
        setCurrentSessionId(sessionInfo.sessionId);
        setCurrentTaskIndex(sessionInfo.taskIndex);
      }

      // Compute session folder path
      let computedSessionFolder: string | null = null;
      if (sessId) {
        try {
          const base = await getSessionsBaseDir();
          computedSessionFolder = `${base}/${sessId}`;
          setSessionFolder(computedSessionFolder);
        } catch (error) {
          console.error('Failed to compute session folder:', error);
        }
      }

      // Create or use existing task
      const currentTaskId = existingTaskId || Date.now().toString();
      setTaskId(currentTaskId);
      activeTaskIdRef.current = currentTaskId; // Set as active task for stream isolation

      // Save task to database - check if task exists first
      try {
        const existingTask = await getTask(currentTaskId);
        if (!existingTask) {
          await createTask({
            id: currentTaskId,
            session_id: sessId,
            task_index: taskIdx,
            prompt,
          });
          console.log(
            '[useAgent] Created new task:',
            currentTaskId,
            'in session:',
            sessId
          );

          // Generate a short title asynchronously
          (async () => {
            try {
              const modelConfig = getModelConfig();
              const language = getPreferredLanguage();
              console.log(
                '[useAgent] Requesting title generation for prompt:',
                prompt.slice(0, 80)
              );
              console.log(
                '[useAgent] Title request URL:',
                `${AGENT_SERVER_URL}/agent/title`
              );
              console.log('[useAgent] Title request payload:', {
                prompt: prompt.slice(0, 80),
                hasModelConfig: !!modelConfig,
                language,
              });
              const res = await fetch(`${AGENT_SERVER_URL}/agent/title`, {
                method: 'POST',
                headers: await getRequestHeaders(),
                body: JSON.stringify({ prompt, modelConfig, language }),
              });
              console.log('[useAgent] Title response status:', res.status);
              if (res.ok) {
                const data = await res.json();
                console.log('[useAgent] Title response data:', data);
                if (data.title) {
                  // 前端兜底 sanitize：即便后端失灵吐了 <think>...</think>，也不让污染本地 task
                  const cleaned = sanitizeTitle(data.title);
                  if (cleaned) {
                    await updateTask(currentTaskId, { prompt: cleaned });
                    setGeneratedTitleResult({
                      taskId: currentTaskId,
                      title: cleaned,
                    });
                    console.log('[useAgent] Updated task title:', cleaned);
                  } else {
                    console.warn(
                      '[useAgent] title sanitize rejected, keeping original prompt:',
                      data.title.slice(0, 60)
                    );
                  }
                }
              } else {
                const errorText = await res.text();
                console.error(
                  '[useAgent] Title generation failed:',
                  res.status,
                  errorText
                );
              }
            } catch (err) {
              console.error('[useAgent] Failed to generate title:', err);
            }
          })();
        } else {
          console.log('[useAgent] Task already exists:', currentTaskId);
        }
      } catch (error) {
        console.error('Failed to create task:', error);
      }

      const abortController = new AbortController();
      abortControllerRef.current = abortController;

      // Prepare images for API (only send image attachments with actual data)
      const images = attachments
        ?.filter((a) => a.type === 'image' && a.data && a.data.length > 0)
        .map((a) => ({
          data: a.data,
          mimeType: a.mimeType || 'image/png',
        }));

      const hasImages = images && images.length > 0;

      // Save file attachments to disk and augment prompt with file paths
      const fileAttachments =
        attachments?.filter((a) => a.type === 'file') || [];
      let augmentedPrompt = prompt;
      let savedFileRefs: AttachmentReference[] = [];

      if (fileAttachments.length > 0) {
        // Ensure we have a folder to save attachments to
        let saveFolder = computedSessionFolder;
        if (!saveFolder) {
          try {
            const base = await getSessionsBaseDir();
            saveFolder = `${base}/temp-${Date.now()}`;
          } catch {
            // ignore
          }
        }

        if (saveFolder) {
          try {
            savedFileRefs = await saveAttachments(saveFolder, fileAttachments);
            console.log(
              '[useAgent] Saved file attachments:',
              savedFileRefs.map((r) => r.path)
            );
            setFilesVersion((v) => v + 1);

            // Append file paths to prompt so the agent knows about them
            const filePaths = savedFileRefs.map((r) => r.path).join('\n');
            augmentedPrompt = `${prompt}\n\n[Attached files]\n${filePaths}`;
          } catch (error) {
            console.error('[useAgent] Failed to save file attachments:', error);
          }
        } else {
          // Can't save to disk — include file content inline for small text files
          console.warn(
            '[useAgent] No folder available, embedding file content in prompt'
          );
          const fileInfo = fileAttachments
            .map((a) => {
              // For text-based files, decode and include content
              if (
                a.data &&
                (a.mimeType?.startsWith('text/') ||
                  a.name.match(/\.(csv|txt|json|xml|tsv|md|log)$/i))
              ) {
                try {
                  const content = atob(
                    a.data.includes(',') ? a.data.split(',')[1] : a.data
                  );
                  return `[File: ${a.name}]\n${content}`;
                } catch {
                  return `[File: ${a.name}] (unable to decode)`;
                }
              }
              return `[File: ${a.name}] (binary file, unable to include inline)`;
            })
            .join('\n\n');
          augmentedPrompt = `${prompt}\n\n${fileInfo}`;
        }
      }

      // Debug logging for attachments
      if (attachments && attachments.length > 0) {
        console.log('[useAgent] Attachments received:', attachments.length);
        attachments.forEach((a, i) => {
          console.log(
            `[useAgent] Attachment ${i}: type=${a.type}, name=${a.name}, hasData=${!!a.data}, dataLength=${a.data?.length || 0}`
          );
        });
        console.log('[useAgent] Valid images for API:', images?.length || 0);
        console.log('[useAgent] File attachments:', fileAttachments.length);
        console.log('[useAgent] computedSessionFolder:', computedSessionFolder);
        console.log(
          '[useAgent] augmentedPrompt:',
          augmentedPrompt.slice(0, 200)
        );
      }

      try {
        const modelConfig = getModelConfig();

        // Note: We no longer check if model is configured here.
        // The backend will check if Claude Code is available locally.
        // If Claude Code is available, it will use it even without explicit model configuration.
        // If Claude Code is not available and no model is configured, the backend will return an error.

        // All queries go through the agent endpoint (with tools).
        // Fast chat was removed: it has no tools, so models cannot access
        // real-time data (time, weather, search) and incorrectly say "I can't".

        const isOpenAiProvider = modelConfig?.apiType === 'openai-completions';
        const executionStrategy = classifyAgentExecutionStrategy(prompt, {
          hasImages: Boolean(hasImages),
          apiType: modelConfig?.apiType,
        });
        const executionPrompt = applyAgentStrategyHint(
          augmentedPrompt,
          executionStrategy
        );

        // Direct execute: simple, image, or OpenAI-compatible provider queries
        // skip the explicit plan approval step.
        if (
          executionStrategy.route === 'direct' &&
          !hasImages &&
          !isOpenAiProvider
        ) {
          console.log(
            `[useAgent] ${executionStrategy.reason}, skipping plan → direct execute`
          );
          setPhase('executing');

          // Add user message to UI immediately
          const userMessage: AgentMessage = {
            type: 'user',
            content: prompt,
            attachments: attachments,
          };
          setMessages([userMessage]);

          try {
            const allRefs = [...savedFileRefs];
            await createMessage({
              task_id: currentTaskId,
              type: 'user',
              content: prompt,
              attachments:
                allRefs.length > 0 ? JSON.stringify(allRefs) : undefined,
            });
          } catch (error) {
            console.error('Failed to save user message:', error);
          }

          const workDir = computedSessionFolder || (await getAppDataDir());
          const sandboxConfig = getSandboxConfig();
          const skillsConfig = getSkillsConfig();
          const language = getPreferredLanguage();
          const mcpConfig = getMcpConfig();

          const response = await fetchWithRetry(`${AGENT_SERVER_URL}/agent`, {
            method: 'POST',
            headers: await getRequestHeaders(),
            body: JSON.stringify({
              prompt: executionPrompt,
              workDir,
              taskId: currentTaskId,
              modelConfig,
              sandboxConfig,
              skillsConfig,
              mcpConfig,
              language,
              userId: getCurrentBoundUid() ?? undefined,
              accessToken: await getCurrentAccessToken(),
            }),
            signal: abortController.signal,
          });

          throwForBadResponse(response, '/agent');

          await processStream(response, currentTaskId, abortController);
          return currentTaskId;
        }

        // If images are attached, or if using OpenAI-format provider,
        // use direct execution (skip planning).
        // - Images need to be processed during execution, not planning.
        // - OpenAI-format providers have unreliable plan generation; direct
        //   execution with tools is more robust.
        if (executionStrategy.route === 'direct') {
          if (hasImages) {
            console.log('[useAgent] Images attached, using direct execution');
          } else {
            console.log(
              `[useAgent] ${executionStrategy.reason}, skipping plan phase`
            );
          }
          setPhase('executing');

          // Add user message with attachments to UI
          const userMessage: AgentMessage = {
            type: 'user',
            content: prompt,
            attachments: attachments,
          };
          setMessages([userMessage]);

          // Save user message to database (save image attachments to files;
          // file attachments were already saved earlier)
          try {
            const allRefs: AttachmentReference[] = [...savedFileRefs];
            const imageAttachments =
              attachments?.filter((a) => a.type === 'image') || [];
            if (imageAttachments.length > 0 && computedSessionFolder) {
              const imageRefs = await saveAttachments(
                computedSessionFolder,
                imageAttachments
              );
              allRefs.push(...imageRefs);
              console.log(
                '[useAgent] Saved image attachments to files:',
                imageRefs.length
              );
            }
            await createMessage({
              task_id: currentTaskId,
              type: 'user',
              content: prompt,
              attachments:
                allRefs.length > 0 ? JSON.stringify(allRefs) : undefined,
            });
          } catch (error) {
            console.error('Failed to save user message:', error);
          }

          // Use session folder as workDir
          const workDir = computedSessionFolder || (await getAppDataDir());
          const sandboxConfig = getSandboxConfig();
          const skillsConfig = getSkillsConfig();
          const language = getPreferredLanguage();

          const mcpConfig = getMcpConfig();

          // Use direct execution endpoint with images
          const response = await fetchWithRetry(`${AGENT_SERVER_URL}/agent`, {
            method: 'POST',
            headers: await getRequestHeaders(),
            body: JSON.stringify({
              prompt: executionPrompt,
              workDir,
              taskId: currentTaskId,
              modelConfig,
              sandboxConfig,
              images,
              skillsConfig,
              mcpConfig,
              language,
              userId: getCurrentBoundUid() ?? undefined,
              accessToken: await getCurrentAccessToken(),
            }),
            signal: abortController.signal,
          });

          throwForBadResponse(response, '/agent');

          await processStream(response, currentTaskId, abortController);
          return currentTaskId;
        }

        // Save user message to database (for plan path)
        try {
          const allRefs = [...savedFileRefs];
          await createMessage({
            task_id: currentTaskId,
            type: 'user',
            content: prompt,
            attachments:
              allRefs.length > 0 ? JSON.stringify(allRefs) : undefined,
          });
        } catch (error) {
          console.error('Failed to save user message:', error);
        }

        // Phase 1: Request planning (no images)
        const response = await fetchWithRetry(
          `${AGENT_SERVER_URL}/agent/plan`,
          {
            method: 'POST',
            headers: await getRequestHeaders(),
            body: JSON.stringify({
              prompt: executionPrompt,
              modelConfig,
              language: getPreferredLanguage(),
              userId: getCurrentBoundUid() ?? undefined,
              accessToken: await getCurrentAccessToken(),
            }),
            signal: abortController.signal,
          }
        );

        throwForBadResponse(response, '/agent/plan');

        // Process planning stream
        const reader = response.body?.getReader();
        if (!reader) throw new Error('No response body');

        const decoder = new TextDecoder();
        let buffer = '';
        let sawPlanningOutcome = false;

        // Helper to check if this stream is still for the active task
        const isActiveTask = () => activeTaskIdRef.current === currentTaskId;

        while (true) {
          const { done, value } = await reader.read();
          if (done) break;

          // Note: We no longer cancel the reader when task switches.
          // Planning streams continue in background, UI updates are skipped for inactive tasks.

          buffer += decoder.decode(value, { stream: true });
          const lines = buffer.split('\n');
          buffer = lines.pop() || '';

          for (const line of lines) {
            if (line.startsWith('data: ')) {
              try {
                const data = JSON.parse(line.slice(6)) as AgentMessage;

                // Check if this task is still active for UI updates
                const isActive = isActiveTask();

                if (data.type === 'session') {
                  if (isActive) {
                    sessionIdRef.current = data.sessionId || null;
                  }
                } else if (data.type === 'direct_answer' && data.content) {
                  sawPlanningOutcome = true;
                  // Simple question - direct answer, no plan needed
                  console.log(
                    '[useAgent] Received direct answer, no plan needed'
                  );
                  // Extract actual answer if content is JSON
                  let actualContent = data.content;
                  try {
                    if (
                      typeof data.content === 'string' &&
                      data.content.trim().startsWith('{')
                    ) {
                      const parsed = JSON.parse(data.content);
                      if (parsed.answer && typeof parsed.answer === 'string') {
                        actualContent = parsed.answer;
                      }
                    }
                  } catch {
                    // Not JSON, use original content
                  }
                  // UI updates only for active task
                  if (isActive) {
                    setMessages((prev) => [
                      ...prev,
                      { type: 'text', content: actualContent },
                    ]);
                    setPlan(null); // Clear any plan when we get a direct answer
                    setPhase('idle');
                  }

                  // Save to database (always)
                  try {
                    await createMessage({
                      task_id: currentTaskId,
                      type: 'text',
                      content: actualContent,
                    });
                    await updateTask(currentTaskId, { status: 'completed' });
                  } catch (dbError) {
                    console.error('Failed to save direct answer:', dbError);
                  }
                } else if (data.type === 'plan' && data.plan) {
                  sawPlanningOutcome = true;
                  // Complex task - received the plan, wait for approval
                  // UI updates only for active task
                  if (isActive) {
                    setPlan(data.plan);
                    setPhase('awaiting_approval');
                    setMessages((prev) => [...prev, data]);
                  }

                  // Save plan to database (always, even if not active)
                  try {
                    await createMessage({
                      task_id: currentTaskId,
                      type: 'plan',
                      content: JSON.stringify(data.plan),
                    });
                  } catch (dbError) {
                    console.error('Failed to save plan:', dbError);
                  }
                } else if (data.type === 'text') {
                  // Skip text messages that contain plan JSON (will be rendered by PlanApproval)
                  const content = data.content || '';
                  const isPlanJson =
                    content.includes('"type"') &&
                    content.includes('"plan"') &&
                    (content.includes('"steps"') || content.includes('"goal"'));
                  if (isActive && !isPlanJson) {
                    setMessages((prev) => [...prev, data]);
                  }
                } else if (data.type === 'done') {
                  if (!sawPlanningOutcome) {
                    sawPlanningOutcome = true;
                    const fallbackMessage: AgentMessage = {
                      type: 'error',
                      message: MODEL_EMPTY_RESPONSE_MESSAGE,
                    };
                    if (isActive) {
                      setMessages((prev) => [...prev, fallbackMessage]);
                      setPhase('idle');
                    }
                    try {
                      await createMessage({
                        task_id: currentTaskId,
                        type: 'error',
                        error_message: MODEL_EMPTY_RESPONSE_MESSAGE,
                      });
                      await updateTask(currentTaskId, { status: 'error' });
                    } catch (dbError) {
                      console.error(
                        'Failed to save planning empty response fallback:',
                        dbError
                      );
                    }
                  }
                } else if (data.type === 'error') {
                  sawPlanningOutcome = true;
                  if (isActive) {
                    setMessages((prev) => [...prev, data]);
                    setPhase('idle');
                  }
                }
              } catch {
                // Ignore parse errors
              }
            }
          }
        }
      } catch (error) {
        if ((error as Error).name !== 'AbortError') {
          const classifiedError = classifyFetchError(error, '/agent/plan');
          const errorMessage = classifiedError.message;
          console.error('[useAgent] Request failed:', {
            error,
            category: classifiedError.category,
            retryable: classifiedError.retryable,
            status: classifiedError.status,
          });

          // UI updates only for active task
          if (activeTaskIdRef.current === currentTaskId) {
            setMessages((prev) => [
              ...prev,
              {
                type: 'error',
                message: errorMessage,
                errorCategory: classifiedError.category,
                retryable: classifiedError.retryable,
                status: classifiedError.status,
              },
            ]);
            setPhase('idle');
          }

          // Save to database (always)
          try {
            await createMessage({
              task_id: currentTaskId,
              type: 'error',
              error_message: errorMessage,
              tool_metadata: JSON.stringify({
                errorCategory: classifiedError.category,
                retryable: classifiedError.retryable,
                status: classifiedError.status,
              }),
            });
            await updateTask(currentTaskId, { status: 'error' });
          } catch (dbError) {
            console.error('Failed to save error:', dbError);
          }
        }
      } finally {
        // Only update running state if this is still the active task
        if (activeTaskIdRef.current === currentTaskId) {
          setIsRunning(false);
          abortControllerRef.current = null;
        }
      }

      return currentTaskId;
    },
    [isRunning, processStream]
  );

  // Phase 2: Execute the approved plan
  const approvePlan = useCallback(async (): Promise<void> => {
    if (
      !plan ||
      !taskId ||
      phase !== 'awaiting_approval' ||
      isRunningRef.current
    )
      return;

    // Ensure this task is the active one before execution
    activeTaskIdRef.current = taskId;

    setIsRunning(true);
    isRunningRef.current = true; // Sync update ref immediately
    setPhase('executing');

    // Initialize plan steps as pending in UI
    const updatedPlan: TaskPlan = {
      ...plan,
      steps: plan.steps.map((s) => ({ ...s, status: 'pending' as const })),
    };
    setPlan(updatedPlan);

    // Save the plan as a message to the database for persistence
    try {
      await createMessage({
        task_id: taskId,
        type: 'plan',
        content: JSON.stringify(plan),
      });
      console.log('[useAgent] Saved plan to database:', plan.id);
    } catch (error) {
      console.error('Failed to save plan to database:', error);
    }

    const abortController = new AbortController();
    abortControllerRef.current = abortController;

    try {
      // Use session folder directly as workDir (no task subfolder)
      let workDir: string;
      if (sessionFolder) {
        workDir = sessionFolder;
      } else {
        const settings = getSettings();
        workDir = settings.workDir || (await getAppDataDir());
      }
      const modelConfig = getModelConfig();
      const sandboxConfig = getSandboxConfig();
      const skillsConfig = getSkillsConfig();
      const mcpConfig = getMcpConfig();
      const language = getPreferredLanguage();

      const response = await fetchWithRetry(
        `${AGENT_SERVER_URL}/agent/execute`,
        {
          method: 'POST',
          headers: await getRequestHeaders(),
          body: JSON.stringify({
            planId: plan.id,
            prompt: initialPrompt,
            workDir,
            taskId,
            modelConfig,
            sandboxConfig,
            skillsConfig,
            mcpConfig,
            language,
            userId: getCurrentBoundUid() ?? undefined,
            accessToken: await getCurrentAccessToken(),
          }),
          signal: abortController.signal,
        }
      );

      throwForBadResponse(response, '/agent/execute');

      await processStream(response, taskId, abortController);
    } catch (error) {
      if ((error as Error).name !== 'AbortError') {
        const classifiedError = classifyFetchError(error, '/agent/execute');
        const errorMessage = classifiedError.message;
        console.error('[useAgent] Execute failed:', {
          error,
          category: classifiedError.category,
          retryable: classifiedError.retryable,
          status: classifiedError.status,
        });

        // UI updates only for active task
        if (activeTaskIdRef.current === taskId) {
          setMessages((prev) => [
            ...prev,
            {
              type: 'error',
              message: errorMessage,
              errorCategory: classifiedError.category,
              retryable: classifiedError.retryable,
              status: classifiedError.status,
            },
          ]);
        }

        // Save to database (always)
        try {
          await createMessage({
            task_id: taskId,
            type: 'error',
            error_message: errorMessage,
            tool_metadata: JSON.stringify({
              errorCategory: classifiedError.category,
              retryable: classifiedError.retryable,
              status: classifiedError.status,
            }),
          });
          await updateTask(taskId, { status: 'error' });
        } catch (dbError) {
          console.error('Failed to save error:', dbError);
        }
      }
    } finally {
      // Only update running state if this is still the active task
      if (activeTaskIdRef.current === taskId) {
        setIsRunning(false);
        setPhase('idle');
        setPlan(null); // Clear plan state to prevent showing confirmation box again
        abortControllerRef.current = null;

        // Mark task as completed in database
        try {
          await updateTask(taskId, { status: 'completed' });
        } catch (dbError) {
          console.error('Failed to mark task as completed:', dbError);
        }

        // Reload messages from database to ensure all are displayed
        // (in case some were missed during streaming)
        try {
          const dbMessages = await getMessagesByTaskId(taskId);
          const agentMessages: AgentMessage[] = [];
          for (const msg of dbMessages) {
            if (msg.type === 'user') {
              agentMessages.push({
                type: 'user' as const,
                content: msg.content || undefined,
              });
            } else if (msg.type === 'text') {
              agentMessages.push({
                type: 'text' as const,
                content: msg.content || undefined,
              });
            } else if (msg.type === 'tool_use') {
              agentMessages.push({
                type: 'tool_use' as const,
                name: msg.tool_name || undefined,
                input: msg.tool_input ? JSON.parse(msg.tool_input) : undefined,
              });
            } else if (msg.type === 'tool_result') {
              agentMessages.push({
                type: 'tool_result' as const,
                toolUseId: msg.tool_use_id || undefined,
                output: msg.tool_output || undefined,
              });
            } else if (msg.type === 'result') {
              agentMessages.push({
                type: 'result' as const,
                subtype: msg.subtype || undefined,
              });
            } else if (msg.type === 'error') {
              agentMessages.push({
                type: 'error' as const,
                message: msg.error_message || undefined,
              });
            } else if (msg.type === 'plan') {
              try {
                const planData = msg.content
                  ? (JSON.parse(msg.content) as TaskPlan)
                  : undefined;
                if (planData) {
                  const completedPlan: TaskPlan = {
                    ...planData,
                    steps: planData.steps.map((s) => ({
                      ...s,
                      status: 'completed' as const,
                    })),
                  };
                  agentMessages.push({
                    type: 'plan' as const,
                    plan: completedPlan,
                  });
                }
              } catch {
                // Ignore parse errors
              }
            } else {
              agentMessages.push({ type: msg.type as AgentMessage['type'] });
            }
          }
          setMessages(agentMessages);
        } catch (reloadError) {
          console.error(
            '[useAgent] Failed to reload messages after execution:',
            reloadError
          );
        }
      }
    }
  }, [plan, taskId, phase, initialPrompt, processStream, sessionFolder]);

  // Reject the plan
  const rejectPlan = useCallback(async (): Promise<void> => {
    setPlan(null);
    setPhase('idle');
    setMessages((prev) => [...prev, { type: 'text', content: '计划已取消。' }]);

    // Save rejection to database so it won't be restored when switching back
    if (taskId) {
      try {
        // Mark task as stopped (cancelled)
        await updateTask(taskId, { status: 'stopped' });
        // Save the cancellation message
        await createMessage({
          task_id: taskId,
          type: 'text',
          content: '计划已取消。',
        });
      } catch (error) {
        console.error('Failed to save plan rejection:', error);
      }
    }
  }, [taskId]);

  // Continue conversation with context
  const continueConversation = useCallback(
    async (
      reply: string,
      attachments?: MessageAttachment[],
      _mode?: 'auto' | 'chat' | 'task'
    ): Promise<void> => {
      if (isRunning || !taskId) return;

      // Add user message to UI immediately (with attachments if any)
      const userMessage: AgentMessage = {
        type: 'user',
        content: reply,
        attachments:
          attachments && attachments.length > 0 ? attachments : undefined,
      };
      setMessages((prev) => [...prev, userMessage]);

      // Save user message to database (save attachments to files first)
      try {
        let attachmentRefs: string | undefined;
        if (attachments && attachments.length > 0 && sessionFolder) {
          // Save attachments to file system and get references
          const refs = await saveAttachments(sessionFolder, attachments);
          attachmentRefs = JSON.stringify(refs);
          console.log('[useAgent] Saved attachments to files:', refs.length);
          // Trigger working files refresh
          setFilesVersion((v) => v + 1);
        }
        await createMessage({
          task_id: taskId,
          type: 'user',
          content: reply,
          attachments: attachmentRefs,
        });
      } catch (error) {
        console.error('Failed to save user message:', error);
      }

      setIsRunning(true);
      isRunningRef.current = true; // Sync update ref immediately

      const abortController = new AbortController();
      abortControllerRef.current = abortController;

      try {
        // Build conversation history including the new reply
        const currentMessages = [...messages, userMessage];
        const conversationHistory = buildConversationHistory(
          initialPrompt,
          currentMessages
        );

        // Use session folder directly as workDir (no task subfolder)
        let workDir: string;
        if (sessionFolder) {
          workDir = sessionFolder;
        } else {
          const settings = getSettings();
          workDir = settings.workDir || (await getAppDataDir());
        }
        const modelConfig = getModelConfig();
        const sandboxConfig = getSandboxConfig();
        const skillsConfig = getSkillsConfig();
        const mcpConfig = getMcpConfig();

        // Prepare images for API (only send image attachments with actual data)
        const images = attachments
          ?.filter((a) => a.type === 'image' && a.data && a.data.length > 0)
          .map((a) => ({
            data: a.data,
            mimeType: a.mimeType || 'image/png',
          }));

        const hasImages = images && images.length > 0;

        // Debug logging for image attachments
        if (attachments && attachments.length > 0) {
          console.log(
            '[useAgent] continueConversation attachments:',
            attachments.length
          );
          attachments.forEach((att, i) => {
            console.log(
              `[useAgent] Attachment ${i}: type=${att.type}, hasData=${!!att.data}, dataLength=${att.data?.length || 0}`
            );
          });
          console.log('[useAgent] Valid images for API:', images?.length || 0);
        }

        const followUpStrategy = classifyAgentExecutionStrategy(reply, {
          hasImages: Boolean(hasImages),
          apiType: modelConfig?.apiType,
        });
        const executionPrompt = applyAgentStrategyHint(reply, followUpStrategy);

        // Send conversation with full history (agent SDK path)
        const response = await fetchWithRetry(`${AGENT_SERVER_URL}/agent`, {
          method: 'POST',
          headers: await getRequestHeaders(),
          body: JSON.stringify({
            prompt: executionPrompt,
            conversation: conversationHistory,
            workDir,
            taskId,
            modelConfig,
            sandboxConfig,
            images: hasImages ? images : undefined,
            skillsConfig,
            mcpConfig,
            userId: getCurrentBoundUid() ?? undefined,
            accessToken: await getCurrentAccessToken(),
          }),
          signal: abortController.signal,
        });

        throwForBadResponse(response, '/agent');

        await processStream(response, taskId, abortController);
      } catch (error) {
        if ((error as Error).name !== 'AbortError') {
          const classifiedError = classifyFetchError(error, '/agent');
          const errorMessage = classifiedError.message;
          console.error('[useAgent] Continue conversation failed:', {
            error,
            category: classifiedError.category,
            retryable: classifiedError.retryable,
            status: classifiedError.status,
          });

          // UI updates only for active task
          if (activeTaskIdRef.current === taskId) {
            setMessages((prev) => [
              ...prev,
              {
                type: 'error',
                message: errorMessage,
                errorCategory: classifiedError.category,
                retryable: classifiedError.retryable,
                status: classifiedError.status,
              },
            ]);
          }

          // Save error to database (always)
          try {
            await createMessage({
              task_id: taskId,
              type: 'error',
              error_message: errorMessage,
              tool_metadata: JSON.stringify({
                errorCategory: classifiedError.category,
                retryable: classifiedError.retryable,
                status: classifiedError.status,
              }),
            });
            await updateTask(taskId, { status: 'error' });
          } catch (dbError) {
            console.error('Failed to save error:', dbError);
          }
        }
      } finally {
        // Only update running state if this is still the active task
        if (activeTaskIdRef.current === taskId) {
          setIsRunning(false);
          abortControllerRef.current = null;
        }
      }
    },
    [isRunning, taskId, messages, initialPrompt, processStream, sessionFolder]
  );

  const stopAgent = useCallback(async () => {
    // Stop polling if active
    if (refreshIntervalRef.current) {
      clearInterval(refreshIntervalRef.current);
      refreshIntervalRef.current = null;
    }

    // Abort the fetch request
    if (abortControllerRef.current) {
      abortControllerRef.current.abort();
    }

    // Also tell the server to stop
    if (sessionIdRef.current) {
      try {
        await fetch(`${AGENT_SERVER_URL}/agent/stop/${sessionIdRef.current}`, {
          method: 'POST',
          headers: await getRequestHeaders(),
        });
      } catch {
        // Ignore errors
      }
    }

    // Update task status
    if (taskId) {
      try {
        await updateTask(taskId, { status: 'stopped' });
      } catch (error) {
        console.error('Failed to update task status:', error);
      }
    }

    setIsRunning(false);
  }, [taskId]);

  const clearMessages = useCallback(() => {
    // Stop polling if active
    if (refreshIntervalRef.current) {
      clearInterval(refreshIntervalRef.current);
      refreshIntervalRef.current = null;
    }

    // This function is for complete cleanup (e.g., starting fresh)
    // For task switching, use loadTask which handles moving to background
    if (abortControllerRef.current) {
      abortControllerRef.current.abort();
      abortControllerRef.current = null;
    }

    setMessages([]);
    setTaskId(null);
    setInitialPrompt('');
    setPendingPermission(null);
    setPendingQuestion(null);
    setPhase('idle');
    setPlan(null);
    setIsRunning(false);
    sessionIdRef.current = null;
    activeTaskIdRef.current = null;
  }, []);

  // Respond to permission request
  const respondToPermission = useCallback(
    async (permissionId: string, approved: boolean): Promise<void> => {
      if (!sessionIdRef.current) {
        console.error('No active session to respond to permission');
        return;
      }

      try {
        const response = await fetch(`${AGENT_SERVER_URL}/agent/permission`, {
          method: 'POST',
          headers: await getRequestHeaders(),
          body: JSON.stringify({
            sessionId: sessionIdRef.current,
            permissionId,
            approved,
          }),
        });

        if (!response.ok) {
          throw new Error(
            `Failed to respond to permission: ${response.status}`
          );
        }

        // Clear pending permission
        setPendingPermission(null);

        // Add response message to UI
        const responseMessage: AgentMessage = {
          type: 'text',
          content: approved
            ? 'Permission granted. Continuing...'
            : 'Permission denied. Operation cancelled.',
        };
        setMessages((prev) => [...prev, responseMessage]);
      } catch (error) {
        console.error('Failed to respond to permission:', error);
        setPendingPermission(null);
      }
    },
    []
  );

  // Respond to question from AskUserQuestion tool
  const respondToQuestion = useCallback(
    async (
      _questionId: string,
      answers: Record<string, string>
    ): Promise<void> => {
      if (!taskId || !pendingQuestion) {
        console.error('No active task or pending question');
        return;
      }

      // Format answers as a readable message
      const answerText = Object.entries(answers)
        .map(([question, answer]) => `${question}: ${answer}`)
        .join('\n');

      // Clear pending question first
      setPendingQuestion(null);

      // Add user response as a message
      const userMessage: AgentMessage = { type: 'user', content: answerText };
      setMessages((prev) => [...prev, userMessage]);

      // Continue the conversation with the answers
      await continueConversation(answerText);
    },
    [taskId, pendingQuestion, continueConversation]
  );

  // taskFolder is now the same as sessionFolder (no task subfolders)
  const taskFolder = sessionFolder;

  // Track background tasks
  const [backgroundTasks, setBackgroundTasks] = useState<BackgroundTask[]>([]);

  // Subscribe to background task changes
  useEffect(() => {
    const unsubscribe = subscribeToBackgroundTasks((tasks) => {
      setBackgroundTasks(tasks);
    });
    return unsubscribe;
  }, []);

  // Cleanup on unmount - move running task to background instead of abandoning it
  useEffect(() => {
    return () => {
      // Stop polling if active
      if (refreshIntervalRef.current) {
        clearInterval(refreshIntervalRef.current);
        refreshIntervalRef.current = null;
      }

      // If there's a running task when unmounting, move it to background
      // so it continues running and shows in the sidebar
      const currentTaskId = taskIdRef.current;
      const currentIsRunning = isRunningRef.current;
      const currentPrompt = initialPromptRef.current;

      if (abortControllerRef.current && currentTaskId && currentIsRunning) {
        console.log(
          '[useAgent] Moving task to background on unmount:',
          currentTaskId
        );
        addBackgroundTask({
          taskId: currentTaskId,
          sessionId: sessionIdRef.current || '',
          abortController: abortControllerRef.current,
          isRunning: true,
          prompt: currentPrompt,
        });
        // Don't clear refs here since the effect is cleaning up
        // The stream will continue to run and save to database
      }
    };
  }, []);

  // Get count of running background tasks
  const runningBackgroundTaskCount = backgroundTasks.filter(
    (t) => t.isRunning
  ).length;

  const generatedTitle =
    generatedTitleResult?.taskId === taskId ? generatedTitleResult.title : null;

  return {
    messages,
    isRunning,
    taskId,
    sessionId: currentSessionId,
    taskIndex: currentTaskIndex,
    sessionFolder,
    taskFolder,
    filesVersion,
    pendingPermission,
    pendingQuestion,
    phase,
    plan,
    runAgent,
    approvePlan,
    rejectPlan,
    continueConversation,
    stopAgent,
    clearMessages,
    loadTask,
    loadMessages,
    respondToPermission,
    respondToQuestion,
    setSessionInfo,
    generatedTitle,
    // Background tasks
    backgroundTasks,
    runningBackgroundTaskCount,
  };
}
