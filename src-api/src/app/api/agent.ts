import { Hono } from 'hono';

import type { SandboxConfig } from '@/core/agent/types';
import {
  createSession,
  deleteSession,
  getPlan,
  getSession,
  runAgent,
  runExecutionPhase,
  runPlanningPhase,
} from '@/shared/services/agent';
import { generateTitle, runChat } from '@/shared/services/chat';
import { appendEvent, getEvents, getTaskStatus, initTaskBuffer, markTaskComplete } from '@/shared/task-events';
import type { AgentRequest } from '@/shared/types/agent';
import { matchSlashCommand, executeSlashCommand } from '@/core/channel/slash-commands';

const agent = new Hono();

/**
 * Create SSE stream with event buffering.
 * Events are stored in task-events store for client reconnection/catchup.
 * If the HTTP connection closes (e.g. iOS goes to background),
 * the generator continues to run and events are still buffered.
 */
function createSSEStream(generator: AsyncGenerator<unknown>, taskId?: string) {
  const encoder = new TextEncoder();

  // Initialize event buffer for this task
  if (taskId) {
    initTaskBuffer(taskId);
  }

  return new ReadableStream({
    async start(controller) {
      try {
        for await (const message of generator) {
          // Store event in buffer (for reconnection)
          if (taskId) {
            appendEvent(taskId, message);
          }

          // Write to SSE stream (may fail if client disconnected)
          try {
            const data = `data: ${JSON.stringify(message)}\n\n`;
            controller.enqueue(encoder.encode(data));
          } catch {
            // Client disconnected — continue executing, events still buffered
            // Don't break the loop, let the agent finish its work
          }
        }
      } catch (error) {
        const errorEvent = {
          type: 'error',
          message: error instanceof Error ? error.message : String(error),
        };
        if (taskId) {
          appendEvent(taskId, errorEvent);
        }
        try {
          const errorData = `data: ${JSON.stringify(errorEvent)}\n\n`;
          controller.enqueue(encoder.encode(errorData));
        } catch {
          // Client already disconnected
        }
      } finally {
        // Mark task as complete in buffer
        if (taskId) {
          markTaskComplete(taskId);
        }
        try {
          controller.close();
        } catch {
          // Already closed
        }
      }
    },
  });
}

// SSE Response headers
const SSE_HEADERS = {
  'Content-Type': 'text/event-stream',
  'Cache-Control': 'no-cache, no-transform',
  Connection: 'keep-alive',
  'X-Accel-Buffering': 'no',
};

// Lightweight chat endpoint (bypasses Agent SDK for simple queries)
agent.post('/chat', async (c) => {
  const body = await c.req.json<AgentRequest>();

  console.log('[AgentAPI] POST /chat received:', {
    hasPrompt: !!body.prompt,
    hasModelConfig: !!body.modelConfig,
    hasConversation: !!(body.conversation && body.conversation.length > 0),
  });

  if (!body.prompt) {
    return c.json({ error: 'prompt is required' }, 400);
  }

  const abortController = new AbortController();
  const readable = createSSEStream(
    runChat(body.prompt, body.modelConfig, body.language, body.conversation, abortController)
  );

  return new Response(readable, { headers: SSE_HEADERS });
});

// Phase 1: Create a plan (no execution)
agent.post('/plan', async (c) => {
  const body = await c.req.json<AgentRequest>();

  console.log('[AgentAPI] POST /plan received:', {
    hasPrompt: !!body.prompt,
    hasModelConfig: !!body.modelConfig,
    modelConfig: body.modelConfig
      ? {
          hasApiKey: !!body.modelConfig.apiKey,
          baseUrl: body.modelConfig.baseUrl,
          model: body.modelConfig.model,
        }
      : null,
  });

  if (!body.prompt) {
    return c.json({ error: 'prompt is required' }, 400);
  }

  const session = createSession('plan');
  const readable = createSSEStream(
    runPlanningPhase(
      body.prompt,
      session,
      body.modelConfig,
      body.language,
      body.userId,
      body.accessToken
    )
  );

  return new Response(readable, { headers: SSE_HEADERS });
});

// Phase 2: Execute an approved plan
agent.post('/execute', async (c) => {
  const body = await c.req.json<{
    planId: string;
    prompt: string;
    workDir?: string;
    taskId?: string;
    modelConfig?: { apiKey?: string; baseUrl?: string; model?: string };
    sandboxConfig?: SandboxConfig;
    skillsConfig?: {
      enabled: boolean;
      userDirEnabled: boolean;
      appDirEnabled: boolean;
      skillsPath?: string;
    };
    mcpConfig?: {
      enabled: boolean;
      userDirEnabled: boolean;
      appDirEnabled: boolean;
      mcpConfigPath?: string;
    };
    language?: string;
    userId?: string;
    accessToken?: string;
  }>();

  console.log('[AgentAPI] POST /execute received:', {
    planId: body.planId,
    hasPrompt: !!body.prompt,
    sandboxConfig: body.sandboxConfig
      ? {
          enabled: body.sandboxConfig.enabled,
          provider: body.sandboxConfig.provider,
        }
      : null,
    skillsConfig: body.skillsConfig,
    mcpConfig: body.mcpConfig,
  });

  if (!body.planId) {
    return c.json({ error: 'planId is required' }, 400);
  }

  const plan = getPlan(body.planId);
  if (!plan) {
    return c.json({ error: 'Plan not found or expired' }, 404);
  }

  const session = createSession('execute');
  const readable = createSSEStream(
    runExecutionPhase(
      body.planId,
      session,
      body.prompt || '',
      body.workDir,
      body.taskId,
      body.modelConfig,
      body.sandboxConfig,
      body.skillsConfig,
      body.mcpConfig,
      body.language,
      body.userId,
      body.accessToken
    )
  );

  return new Response(readable, { headers: SSE_HEADERS });
});

// Legacy: Direct execution (plan + execute in one call)
agent.post('/', async (c) => {
  const body = await c.req.json<AgentRequest>();

  console.log('[AgentAPI] POST / received:', {
    hasPrompt: !!body.prompt,
    hasModelConfig: !!body.modelConfig,
    modelConfig: body.modelConfig
      ? {
          hasApiKey: !!body.modelConfig.apiKey,
          baseUrl: body.modelConfig.baseUrl,
          model: body.modelConfig.model,
        }
      : null,
    sandboxConfig: body.sandboxConfig
      ? {
          enabled: body.sandboxConfig.enabled,
          provider: body.sandboxConfig.provider,
        }
      : null,
    hasImages: !!body.images,
    imagesCount: body.images?.length || 0,
  });

  // Debug logging for images
  if (body.images && body.images.length > 0) {
    body.images.forEach(
      (img: { data: string; mimeType: string }, i: number) => {
        console.log(
          `[AgentAPI] Image ${i}: mimeType=${img.mimeType}, dataLength=${img.data?.length || 0}`
        );
      }
    );
  } else {
    console.log('[AgentAPI] No images in request');
  }

  // Allow empty prompt when images are attached
  if (!body.prompt && (!body.images || body.images.length === 0)) {
    return c.json({ error: 'prompt is required' }, 400);
  }

  const prompt = body.prompt || '请分析这张图片';

  // Slash command interception (unified with channel layer)
  const slashCmd = matchSlashCommand(prompt);
  if (slashCmd) {
    // /compact uses streaming SSE for progress updates
    if (slashCmd.name === 'compact') {
      const encoder = new TextEncoder();
      const readable = new ReadableStream({
        async start(controller) {
          const send = (msg: Record<string, unknown>) => {
            controller.enqueue(encoder.encode(`data: ${JSON.stringify(msg)}\n\n`));
          };
          try {
            const conv = body.conversation || [];
            const convTurns = Math.floor(conv.length / 2);
            if (convTurns < 3) {
              send({ type: 'text', content: `⚠️ 当前对话仅 ${convTurns} 轮，无需压缩（至少需要 3 轮）。` });
            } else {
              const { manualCompact } = await import('@/shared/context/assembler');
              const taskId = body.taskId || 'desktop';
              const result = await manualCompact(taskId, conv, (progress) => {
                send({ type: 'text', content: progress });
              });
              if (result.ok) {
                const reduction = result.tokensBefore > 0
                  ? Math.round((1 - result.tokensAfter / result.tokensBefore) * 100)
                  : 0;
                send({ type: 'text', content: `✅ 上下文已压缩（非破坏性，原始消息保留）\n\n📊 Token：${result.tokensBefore.toLocaleString()} → ${result.tokensAfter.toLocaleString()}（减少 ${reduction}%）\n\n${result.summary.slice(0, 300)}${result.summary.length > 300 ? '...' : ''}` });
              } else {
                send({ type: 'text', content: '⚠️ 压缩失败，请稍后重试。' });
              }
            }
          } catch (err) {
            send({ type: 'text', content: '⚠️ 压缩失败，请稍后重试。' });
          }
          send({ type: 'done' });
          controller.close();
        },
      });
      return new Response(readable, { headers: SSE_HEADERS });
    }

    // /new and /reset: return action signal for frontend to handle
    if (slashCmd.name === 'new' || slashCmd.name === 'reset') {
      // Clear compaction store for this task
      try {
        const { deleteCompaction } = await import('@/shared/context/compaction-store');
        if (body.taskId) deleteCompaction(body.taskId);
      } catch { /* ignore */ }

      const encoder = new TextEncoder();
      const readable = new ReadableStream({
        start(controller) {
          const send = (msg: Record<string, unknown>) => controller.enqueue(encoder.encode(`data: ${JSON.stringify(msg)}\n\n`));
          send({ type: 'text', content: slashCmd.name === 'new'
            ? '✅ 已开启新对话。之前的上下文已清除。'
            : '✅ 已重置会话。上下文和短期记忆已清除。' });
          send({ type: 'session_action', action: slashCmd.name });
          send({ type: 'done' });
          controller.close();
        },
      });
      return new Response(readable, { headers: SSE_HEADERS });
    }

    // Other slash commands: single response
    const result = await executeSlashCommand(slashCmd, {
      taskId: body.taskId,
      modelConfig: body.modelConfig,
      conversation: body.conversation,
    });
    const encoder = new TextEncoder();
    const readable = new ReadableStream({
      start(controller) {
        controller.enqueue(encoder.encode(`data: ${JSON.stringify({ type: 'text', content: result })}\n\n`));
        controller.enqueue(encoder.encode(`data: ${JSON.stringify({ type: 'done' })}\n\n`));
        controller.close();
      },
    });
    return new Response(readable, { headers: SSE_HEADERS });
  }

  const session = createSession();
  const taskId = body.taskId || session.id;
  const readable = createSSEStream(
    runAgent(
      prompt,
      session,
      body.conversation,
      body.workDir,
      body.taskId,
      body.modelConfig,
      body.sandboxConfig,
      body.images,
      body.skillsConfig,
      body.mcpConfig,
      body.language,
      body.userId,
      body.accessToken
    ),
    taskId
  );

  return new Response(readable, { headers: SSE_HEADERS });
});

// Generate a short title from a prompt
agent.post('/title', async (c) => {
  const body = await c.req.json<{
    prompt: string;
    modelConfig?: { apiKey?: string; baseUrl?: string; model?: string };
    language?: string;
  }>();

  console.log('[AgentAPI] POST /title received:', {
    promptLength: body.prompt?.length,
    promptPreview: body.prompt?.slice(0, 80),
    hasModelConfig: !!body.modelConfig,
    language: body.language,
  });

  if (!body.prompt) {
    return c.json({ error: 'prompt is required' }, 400);
  }

  const title = await generateTitle(body.prompt, body.modelConfig, body.language);
  console.log('[AgentAPI] POST /title result:', { title });
  return c.json({ title });
});

// Stop a running agent
agent.post('/stop/:sessionId', async (c) => {
  const sessionId = c.req.param('sessionId');
  const session = getSession(sessionId);

  if (!session) {
    return c.json({ error: 'Session not found' }, 404);
  }

  deleteSession(sessionId);
  return c.json({ status: 'stopped' });
});

// Get session status
agent.get('/session/:sessionId', async (c) => {
  const sessionId = c.req.param('sessionId');
  const session = getSession(sessionId);

  if (!session) {
    return c.json({ error: 'Session not found' }, 404);
  }

  return c.json({
    id: session.id,
    createdAt: session.createdAt,
    phase: session.phase,
    isAborted: session.abortController.signal.aborted,
  });
});

// Get plan by ID
agent.get('/plan/:planId', async (c) => {
  const planId = c.req.param('planId');
  const plan = getPlan(planId);

  if (!plan) {
    return c.json({ error: 'Plan not found' }, 404);
  }

  return c.json(plan);
});

// ─── Event Catchup (iOS 后台恢复) ─────────────────────────────────────────

/**
 * GET /agent/task/:taskId/events?after=<seq>
 *
 * 返回指定 taskId 在 seq 之后的所有事件。
 * iOS 客户端切后台 SSE 中断后，回到前台时调用此端点补偿缺失事件。
 *
 * Query params:
 *   - after: number (返回 seq > after 的事件，默认 -1 返回全部)
 *
 * Response:
 *   { events: [{seq, timestamp, data}], isComplete: boolean }
 */
agent.get('/task/:taskId/events', (c) => {
  const taskId = c.req.param('taskId');
  const afterParam = c.req.query('after');
  const afterSeq = afterParam ? parseInt(afterParam, 10) : -1;

  const result = getEvents(taskId, afterSeq);
  if (!result) {
    return c.json({ error: 'Task not found', events: [], isComplete: true }, 404);
  }

  return c.json(result);
});

/**
 * GET /agent/task/:taskId/status
 *
 * 返回 task 的执行状态。
 */
agent.get('/task/:taskId/status', (c) => {
  const taskId = c.req.param('taskId');
  return c.json(getTaskStatus(taskId));
});

export default agent;
