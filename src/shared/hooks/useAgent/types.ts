/**
 * useAgent shared type definitions.
 * All types previously exported from useAgent.ts are here.
 *
 * NOTE: Function implementations (classifyFetchError, throwForBadResponse, etc.)
 * live in their respective sub-modules (errors.ts, config.ts, strategy.ts).
 * This file is TYPES ONLY.
 */

import type { Task } from '@/shared/db';
import type { BackgroundTask } from '@/shared/lib/background-tasks';

export type AgentExecutionRoute = 'direct' | 'plan';
export type AgentExecutionIntent =
  | 'conversation'
  | 'memory_recall'
  | 'simple_lookup'
  | 'multi_target'
  | 'complex_task'
  | 'image'
  | 'openai_provider';

export interface AgentExecutionStrategy {
  route: AgentExecutionRoute;
  intent: AgentExecutionIntent;
  boostPrompt?: boolean;
  reason: string;
}

export type AgentErrorCategory =
  | 'auth'
  | 'rate_limit'
  | 'timeout'
  | 'network'
  | 'context_overflow'
  | 'model_empty_response'
  | 'server_error'
  | 'tool_loop_limit'
  | 'unknown';

export interface ClassifiedAgentError {
  category: AgentErrorCategory;
  message: string;
  retryable: boolean;
  status?: number;
}

export interface PermissionRequest {
  id: string;
  tool: string;
  command?: string;
  description: string;
  risk_level?: 'low' | 'medium' | 'high';
}

// Question types for AskUserQuestion tool
export interface QuestionOption {
  label: string;
  description: string;
}

export interface AgentQuestion {
  question: string;
  header: string;
  options: QuestionOption[];
  multiSelect: boolean;
}

export interface PendingQuestion {
  id: string;
  toolUseId: string;
  questions: AgentQuestion[];
}

// Attachment type for messages with images/files
export interface MessageAttachment {
  id: string;
  type: 'image' | 'file';
  name: string;
  data: string; // Base64 data for images
  mimeType?: string;
  path?: string; // File path when loaded from disk
  isLoading?: boolean; // True when attachment is being loaded
}

export interface AgentMessage {
  type:
    | 'text'
    | 'tool_use'
    | 'tool_result'
    | 'result'
    | 'error'
    | 'session'
    | 'done'
    | 'user'
    | 'permission_request'
    | 'plan'
    | 'direct_answer'
    | 'session_action'
    | 'compact_result';
  content?: string;
  name?: string;
  id?: string; // tool_use id
  input?: unknown;
  subtype?: string;
  cost?: number;
  duration?: number;
  message?: string;
  errorCategory?: AgentErrorCategory;
  retryable?: boolean;
  status?: number;
  sessionId?: string;
  // Permission request fields
  permission?: PermissionRequest;
  // Tool result fields
  toolUseId?: string;
  output?: string;
  isError?: boolean;
  toolMetadata?: string; // JSON string of ToolMetadata for artifact mapping
  // Plan fields
  plan?: TaskPlan;
  // Attachments for user messages (images, files)
  attachments?: MessageAttachment[];
  // session_action fields (/new, /reset)
  action?: string;
  // compact_result fields
  conversation?: Array<{ role: string; content: string }>;
}

export interface PlanStep {
  id: string;
  description: string;
  status: 'pending' | 'in_progress' | 'completed' | 'failed' | 'cancelled';
}

export interface TaskPlan {
  id: string;
  goal: string;
  steps: PlanStep[];
  notes?: string;
  createdAt?: Date;
}

// Conversation message format for API
export interface ConversationMessage {
  role: 'user' | 'assistant';
  content: string;
  imagePaths?: string[]; // Image file paths for context
}

export type AgentPhase =
  | 'idle'
  | 'planning'
  | 'awaiting_approval'
  | 'executing';

export interface SessionInfo {
  sessionId: string;
  taskIndex: number;
}

export interface UseAgentReturn {
  messages: AgentMessage[];
  isRunning: boolean;
  taskId: string | null;
  sessionId: string | null;
  taskIndex: number;
  sessionFolder: string | null;
  taskFolder: string | null; // Full path to current task folder (sessionFolder/task-XX)
  filesVersion: number; // Incremented when files are added (e.g., attachments saved)
  pendingPermission: PermissionRequest | null;
  pendingQuestion: PendingQuestion | null;
  // Two-phase planning
  phase: AgentPhase;
  plan: TaskPlan | null;
  runAgent: (
    prompt: string,
    existingTaskId?: string,
    sessionInfo?: SessionInfo,
    attachments?: MessageAttachment[],
    mode?: 'auto' | 'chat' | 'task'
  ) => Promise<string>;
  approvePlan: () => Promise<void>;
  rejectPlan: () => void;
  continueConversation: (
    reply: string,
    attachments?: MessageAttachment[],
    mode?: 'auto' | 'chat' | 'task'
  ) => Promise<void>;
  stopAgent: () => Promise<void>;
  clearMessages: () => void;
  loadTask: (taskId: string) => Promise<Task | null>;
  loadMessages: (taskId: string) => Promise<void>;
  respondToPermission: (
    permissionId: string,
    approved: boolean
  ) => Promise<void>;
  respondToQuestion: (
    questionId: string,
    answers: Record<string, string>
  ) => Promise<void>;
  setSessionInfo: (sessionId: string, taskIndex: number) => void;
  // Generated title from LLM summarization (null until ready)
  generatedTitle: string | null;
  // Background tasks
  backgroundTasks: BackgroundTask[];
  runningBackgroundTaskCount: number;
}
