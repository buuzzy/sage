/**
 * Error classification and fetch utilities.
 * Classifies HTTP/network errors into structured categories
 * and provides retry-capable fetch.
 */

import { getErrorMessages } from './config';
import type { ClassifiedAgentError } from './types';

const MODEL_EMPTY_RESPONSE_MESSAGE =
  '模型没有返回有效内容。本轮对话已经停止，请检查当前模型配置、API Key 或切换到可用模型后重试。';

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

export {
  MODEL_EMPTY_RESPONSE_MESSAGE,
  AgentHttpError,
  classifyFetchError,
  throwForBadResponse,
  fetchWithRetry,
};
