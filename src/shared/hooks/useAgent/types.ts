/**
 * useAgent shared type definitions.
 * All types previously exported from useAgent.ts are here.
 */

import type { Task } from '@/shared/db';
import type { BackgroundTask } from '@/shared/lib/background-tasks';

type AgentExecutionRoute = 'direct' | 'plan';
type AgentExecutionIntent =
  | 'conversation'
  | 'memory_recall'
  | 'simple_lookup'
  | 'multi_target'
  | 'complex_task'
  | 'image'
  | 'openai_provider';

interface AgentExecutionStrategy {
  route: AgentExecutionRoute;
  intent: AgentExecutionIntent;
  boostPrompt?: boolean;
  reason: string;
}

type AgentErrorCategory =
  | 'auth'
  | 'rate_limit'
  | 'timeout'
  | 'network'
  | 'context_overflow'
  | 'model_empty_response'
  | 'server_error'
  | 'tool_loop_limit'
  | 'unknown';

interface ClassifiedAgentError {
  category: AgentErrorCategory;
  message: string;
  retryable: boolean;
  status?: number;
}

class AgentHttpError extends Error {
  constructor(
    public readonly status: number,
    public readonly endpoint: string,
    message?: string
  ) {
    super(message ?? `Server error: ${status}`);
    this.name = 'AgentHttpError';
  }
}

function isConversationalPrompt(lower: string): boolean {
  const chinesePatterns = [
    '你好',
    '您好',
    '在吗',
    '谢谢',
    '你是谁',
    '你能做什么',
    '你可以做什么',
  ];
  if (chinesePatterns.some((p) => lower.includes(p))) {
    return true;
  }

  return /\b(hello|hi|hey|thanks|thank you)\b/i.test(lower);
}

function isMemoryRecallPrompt(lower: string): boolean {
  const memoryRecallPatterns = [
    'memory',
    '记忆',
    '历史',
    '之前',
    '以前',
    '上次',
    '回顾',
    '回忆',
    '复盘',
    '找一下',
    '查一下之前',
    '聊过',
    '说过',
    '提到过',
    '回测',
    'backtest',
  ];

  return memoryRecallPatterns.some((p) => lower.includes(p));
}

function countExplicitSymbols(lower: string): number {
  const matches = lower.match(/\b(?:sh|sz|hk|bj)?\d{5,6}\b/g);
  return new Set(matches ?? []).size;
}

function isMultiTargetQuery(prompt: string): boolean {
  const lower = prompt.toLowerCase();
  const comparisonPatterns = ['对比', '比较', '分析', 'vs', '和', '与', '跟'];
  const hasComparisonIntent = comparisonPatterns.some((p) => lower.includes(p));
  const enumCount = (lower.match(/[、，,]/g) || []).length;
  const symbolCount = countExplicitSymbols(lower);

  return (
    (hasComparisonIntent && enumCount >= 1) ||
    enumCount >= 2 ||
    symbolCount >= 2
  );
}

function hasDirectLookupIntent(lower: string): boolean {
  const directPatterns = [
    // Simple quote queries
    '行情',
    '股价',
    '报价',
    '价格',
    '多少钱',
    '现在多少',
    '涨跌',
    '涨幅',
    '跌幅',
    '涨了',
    '跌了',
    // K-line / chart
    'k线',
    'kline',
    '走势',
    '日线',
    '周线',
    // Simple lookups
    '最新价',
    '收盘价',
    '开盘价',
    '换手率',
    '成交量',
    '市盈率',
    '市净率',
    'pe',
    'pb',
    // Fund NAV
    '净值',
    // Quick news
    '新闻',
    '资讯',
    '快讯',
    '早报',
    // Short question forms
    '怎么样',
    '什么情况',
    '表现如何',
  ];

  return directPatterns.some((p) => lower.includes(p));
}

function classifyAgentExecutionStrategy(
  prompt: string,
  options: { hasImages?: boolean; apiType?: string | null }
): AgentExecutionStrategy {
  const trimmed = prompt.trim();
  const lower = trimmed.toLowerCase();
  const isOpenAiProvider = options.apiType === 'openai-completions';
  const multiTarget = isMultiTargetQuery(trimmed);

  if (options.hasImages) {
    return {
      route: 'direct',
      intent: 'image',
      boostPrompt: multiTarget,
      reason: 'images require execution path',
    };
  }

  if (isOpenAiProvider) {
    return {
      route: 'direct',
      intent: multiTarget ? 'multi_target' : 'openai_provider',
      boostPrompt: multiTarget,
      reason: 'OpenAI-compatible providers use direct execution',
    };
  }

  if (trimmed.length > 300) {
    return {
      route: 'plan',
      intent: 'complex_task',
      reason: 'long request benefits from explicit plan',
    };
  }

  if (isConversationalPrompt(lower)) {
    return {
      route: 'direct',
      intent: 'conversation',
      reason: 'low-risk conversational prompt',
    };
  }

  if (isMemoryRecallPrompt(lower)) {
    return {
      route: 'direct',
      intent: 'memory_recall',
      reason: 'memory recall should execute tools directly',
    };
  }

  if (multiTarget) {
    return {
      route: 'plan',
      intent: 'multi_target',
      reason: 'multi-target comparison needs structured execution',
    };
  }

  if (hasDirectLookupIntent(lower)) {
    return {
      route: 'direct',
      intent: 'simple_lookup',
      reason: 'simple lookup can skip explicit approval',
    };
  }

  return {
    route: 'plan',
    intent: 'complex_task',
    reason: 'default explicit planning path',
  };
}

function applyAgentStrategyHint(
  prompt: string,
  strategy: AgentExecutionStrategy
): string {
  if (!strategy.boostPrompt && strategy.intent !== 'multi_target') {
    return prompt;
  }

  return `${prompt}

[Execution strategy]
- This is a multi-target or comparison request.
- Prefer batch-capable tools and aggregate results before writing the final answer.
- Keep tool calls bounded: fetch each required data category once per target group, then summarize.
- If web search is needed, search combined keywords instead of repeating one search per target.
- In the final answer, explicitly compare the targets and call out missing data instead of looping.`;
}

console.log(
  `[API] Environment: ${import.meta.env.PROD ? 'production' : 'development'}, Port: ${API_PORT}`
);

function classifyFetchError(
  error: unknown,
  endpoint: string
): ClassifiedAgentError {
  const err = error as Error;
  const message = err.message || String(error);
  const t = getErrorMessages();
  const status =
    error instanceof AgentHttpError
      ? error.status
      : Number(message.match(/Server error:\s*(\d+)/)?.[1]);

  if (status === 401 || status === 403) {
    return {
      category: 'auth',
      message: t.requestFailed.replace('{message}', '认证失败或权限不足'),
      retryable: false,
      status,
    };
  }

  if (status === 429) {
    return {
      category: 'rate_limit',
      message: t.requestFailed.replace('{message}', '请求过于频繁，请稍后重试'),
      retryable: true,
      status,
    };
  }

  if (status >= 500) {
    return {
      category: 'server_error',
      message: t.requestFailed.replace('{message}', `服务端错误 ${status}`),
      retryable: true,
      status,
    };
  }

  // Common error patterns - use friendly messages
  if (
    message === 'Load failed' ||
    message === 'Failed to fetch' ||
    message.includes('NetworkError')
  ) {
    return {
      category: 'network',
      message: t.connectionFailedFinal,
      retryable: true,
    };
  }

  if (message.includes('CORS') || message.includes('cross-origin')) {
    return { category: 'network', message: t.corsError, retryable: false };
  }

  if (message.includes('timeout') || message.includes('Timeout')) {
    return { category: 'timeout', message: t.timeout, retryable: true };
  }

  if (message.includes('ECONNREFUSED')) {
    return {
      category: 'network',
      message: t.serverNotRunning,
      retryable: true,
    };
  }

  if (message.includes(MODEL_EMPTY_RESPONSE_MESSAGE)) {
    return {
      category: 'model_empty_response',
      message: MODEL_EMPTY_RESPONSE_MESSAGE,
      retryable: true,
    };
  }

  if (/context|token|maximum context|上下文/i.test(message)) {
    return {
      category: 'context_overflow',
      message: t.requestFailed.replace('{message}', message),
      retryable: false,
    };
  }

  if (/tool.*limit|max.*tool|工具.*上限/i.test(message)) {
    return {
      category: 'tool_loop_limit',
      message: t.requestFailed.replace('{message}', message),
      retryable: false,
    };
  }

  // Return generic message for other errors
  return {
    category: 'unknown',
    message: t.requestFailed.replace('{message}', message || endpoint),
    retryable: false,
    status: Number.isFinite(status) ? status : undefined,
  };
}

function throwForBadResponse(response: Response, endpoint: string): void {
  if (!response.ok) {
    throw new AgentHttpError(response.status, endpoint);
  }
}

// Fetch with retry logic for better resilience
async function fetchWithRetry(
  url: string,
  options: RequestInit,
  maxRetries: number = 3,
  retryDelay: number = 1000
): Promise<Response> {
  let lastError: Error | null = null;
  const t = getErrorMessages();

  for (let attempt = 0; attempt < maxRetries; attempt++) {
    try {
      const response = await fetch(url, options);
      return response;
    } catch (error) {
      lastError = error as Error;
      const errorMessage = lastError.message || '';

      // Don't retry if aborted
      if (lastError.name === 'AbortError') {
        throw lastError;
      }

      // Only retry on network errors
      const isNetworkError =
        errorMessage === 'Load failed' ||
        errorMessage === 'Failed to fetch' ||
        errorMessage.includes('NetworkError') ||
        errorMessage.includes('ECONNREFUSED');

      if (!isNetworkError) {
        throw lastError;
      }

      // Wait before retrying (exponential backoff)
      if (attempt < maxRetries - 1) {
        const delay = retryDelay * Math.pow(2, attempt);
        const retryMsg = t.retrying
          .replace('{attempt}', String(attempt + 1))
          .replace('{max}', String(maxRetries));
        console.log(`[useAgent] ${retryMsg} (${delay}ms)`);
        await new Promise((resolve) => setTimeout(resolve, delay));
      }
    }
  }

  throw lastError || new Error('Fetch failed after retries');
}

// Helper to get model configuration from user settings
function getModelConfig():
  | { apiKey?: string; baseUrl?: string; model?: string; apiType?: string }
  | undefined {
  try {
    const settings = getSettings();

    // No provider configured — user needs to set one up
    if (!settings.defaultProvider || settings.defaultProvider === 'default') {
      return undefined;
    }

    const provider = settings.providers.find(
      (p) => p.id === settings.defaultProvider
    );

    if (!provider) return undefined;

    const config: {
      apiKey?: string;
      baseUrl?: string;
      model?: string;
      apiType?: string;
    } = {};

    if (provider.apiKey) {
      config.apiKey = provider.apiKey;
    }
    if (provider.baseUrl) {
      config.baseUrl = provider.baseUrl;
    }
    if (settings.defaultModel) {
      config.model = settings.defaultModel;
    }
    if (provider.apiType) {
      config.apiType = provider.apiType;
    }

    // Return undefined if no API key configured
    if (!config.apiKey) {
      return undefined;
    }

    return config;
  } catch (error) {
    console.error('[useAgent] getModelConfig error:', error);
    return undefined;
  }
}

// Helper to get sandbox configuration from settings
function getSandboxConfig():
  | { enabled: boolean; provider?: string; apiEndpoint?: string }
  | undefined {
  try {
    const settings = getSettings();

    // More detailed logging for debugging production issues
    console.log('[useAgent] getSandboxConfig - Full settings check:', {
      sandboxEnabled: settings.sandboxEnabled,
      sandboxEnabledType: typeof settings.sandboxEnabled,
      defaultSandboxProvider: settings.defaultSandboxProvider,
      hasSettings: !!settings,
      settingsKeys: Object.keys(settings),
    });

    // Only return if sandbox is enabled
    if (!settings.sandboxEnabled) {
      console.warn(
        '[useAgent] ⚠️ Sandbox is DISABLED in settings - sandboxEnabled:',
        settings.sandboxEnabled
      );
      return undefined;
    }

    const config = {
      enabled: true,
      provider: settings.defaultSandboxProvider, // Use selected sandbox provider
      apiEndpoint: AGENT_SERVER_URL, // Use the same server
    };

    console.log('[useAgent] ✅ Sandbox ENABLED, returning config:', config);
    return config;
  } catch (error) {
    console.error('[useAgent] ❌ Error getting sandbox config:', error);
    return undefined;
  }
}

// Helper to get skills configuration from settings
function getSkillsConfig():
  | {
      enabled: boolean;
      userDirEnabled: boolean;
      appDirEnabled: boolean;
      skillsPath?: string;
    }
  | undefined {
  try {
    const settings = getSettings();

    // If global switch is off, return undefined (no skills)
    if (settings.skillsEnabled === false) {
      console.log('[useAgent] Skills disabled globally');
      return undefined;
    }

    const config = {
      enabled: true,
      userDirEnabled: settings.skillsUserDirEnabled !== false,
      appDirEnabled: settings.skillsAppDirEnabled !== false,
      skillsPath: settings.skillsPath || undefined,
    };

    console.log('[useAgent] Skills config:', config);
    return config;
  } catch {
    return undefined;
  }
}

// Helper to get MCP configuration from settings
function getMcpConfig():
  | {
      enabled: boolean;
      userDirEnabled: boolean;
      appDirEnabled: boolean;
      mcpConfigPath?: string;
    }
  | undefined {
  try {
    const settings = getSettings();

    // If global switch is off, return undefined (no MCP)
    if (settings.mcpEnabled === false) {
      console.log('[useAgent] MCP disabled globally');
      return undefined;
    }

    const config = {
      enabled: true,
      userDirEnabled: settings.mcpUserDirEnabled !== false,
      appDirEnabled: settings.mcpAppDirEnabled !== false,
      mcpConfigPath: settings.mcpConfigPath || undefined,
    };

    console.log('[useAgent] MCP config:', config);
    return config;
  } catch {
    return undefined;
  }
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
