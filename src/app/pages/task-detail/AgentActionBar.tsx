/**
 * AgentActionBar — action buttons (copy, export, feedback) for agent responses.
 */

import { useEffect, useRef, useState } from 'react';
import { getSettings } from '@/shared/db/settings';
import type { AgentMessage } from '@/shared/hooks/useAgent';

import { serializeMessagesForCopy } from './helpers';

type BugCategory =
  | '回答错误'
  | '工具调用异常'
  | '界面问题'
  | '性能问题'
  | '其他';
const BUG_CATEGORIES: BugCategory[] = [
  '回答错误',
  '工具调用异常',
  '界面问题',
  '性能问题',
  '其他',
];

function AgentActionBar({
  cleanText,
  allMessages,
  taskId,
  containerRef,
}: {
  cleanText: string;
  allMessages: AgentMessage[];
  taskId?: string;
  containerRef?: React.RefObject<HTMLDivElement | null>;
}) {
  const [copiedAnswer, setCopiedAnswer] = useState(false);
  const [copiedProcess, setCopiedProcess] = useState(false);
  const [exportingImage, setExportingImage] = useState(false);
  const [bugOpen, setBugOpen] = useState(false);
  const [bugCategory, setBugCategory] = useState<BugCategory>('其他');
  const [bugDesc, setBugDesc] = useState('');
  const [bugSubmitting, setBugSubmitting] = useState(false);
  const [bugSubmitted, setBugSubmitted] = useState(false);
  const [bugIncludeTranscript, setBugIncludeTranscript] = useState(false);
  const bugPopoverRef = useRef<HTMLDivElement>(null);

  // Close popover when clicking outside
  useEffect(() => {
    if (!bugOpen) return;
    const handler = (e: MouseEvent) => {
      if (
        bugPopoverRef.current &&
        !bugPopoverRef.current.contains(e.target as Node)
      ) {
        setBugOpen(false);
        setBugSubmitted(false);
        setBugDesc('');
        setBugCategory('其他');
      }
    };
    document.addEventListener('mousedown', handler);
    return () => document.removeEventListener('mousedown', handler);
  }, [bugOpen]);

  const handleCopyAnswer = async () => {
    try {
      await navigator.clipboard.writeText(cleanText.trim());
      setCopiedAnswer(true);
      setTimeout(() => setCopiedAnswer(false), 2000);
    } catch {
      /* ignore */
    }
  };

  const handleCopyProcess = async () => {
    try {
      const text = serializeMessagesForCopy(allMessages);
      await navigator.clipboard.writeText(text);
      setCopiedProcess(true);
      setTimeout(() => setCopiedProcess(false), 2000);
    } catch {
      /* ignore */
    }
  };

  const handleExportImage = async () => {
    const node = containerRef?.current;
    if (!node || exportingImage) return;
    setExportingImage(true);

    // Hide action bar from screenshot via CSS class instead of inline style
    node.classList.add('exporting-screenshot');

    // Temporarily disable overflow clipping on ancestors so html-to-image
    // can capture content that would otherwise be hidden by scroll containers.
    const overflowOverrides: { el: HTMLElement; prev: string }[] = [];
    let ancestor: HTMLElement | null = node.parentElement;
    while (ancestor) {
      const computed = getComputedStyle(ancestor).overflow;
      if (computed !== 'visible') {
        overflowOverrides.push({ el: ancestor, prev: ancestor.style.overflow });
        ancestor.style.overflow = 'visible';
      }
      ancestor = ancestor.parentElement;
    }

    try {
      const { toPng } = await import('html-to-image');

      const dataUrl = await toPng(node, {
        pixelRatio: 2,
        backgroundColor: '#ffffff',
        skipFonts: false,
        filter: (el) => {
          // Exclude the action bar element from the screenshot
          if (
            el instanceof HTMLElement &&
            el.classList.contains('agent-action-bar')
          )
            return false;
          return true;
        },
      });

      // Convert data URL → Uint8Array
      const base64 = dataUrl.split(',')[1];
      const binary = atob(base64);
      const bytes = new Uint8Array(binary.length);
      for (let i = 0; i < binary.length; i++) bytes[i] = binary.charCodeAt(i);

      const ts = new Date().toISOString().replace(/[:.]/g, '-').slice(0, 19);
      const fileName = `sage-${ts}.png`;

      try {
        const { downloadDir } = await import('@tauri-apps/api/path');
        const { writeFile } = await import('@tauri-apps/plugin-fs');
        const dir = await downloadDir();
        await writeFile(`${dir}/${fileName}`, bytes);
      } catch {
        // Fallback: browser download
        const a = document.createElement('a');
        a.download = fileName;
        a.href = dataUrl;
        a.click();
      }
    } catch (err) {
      console.error('[ExportImage] failed:', err);
    } finally {
      // Restore original overflow styles
      for (const { el, prev } of overflowOverrides) {
        el.style.overflow = prev;
      }
      node.classList.remove('exporting-screenshot');
      setExportingImage(false);
    }
  };

  const handleSubmitBug = async () => {
    setBugSubmitting(true);
    try {
      const report = {
        id: `${Date.now()}-${Math.random().toString(36).slice(2, 8)}`,
        timestamp: new Date().toISOString(),
        taskId: taskId ?? null,
        category: bugCategory,
        description: bugDesc.trim() || null,
        messageCount: allMessages.length,
      };
      const line = JSON.stringify(report) + '\n';

      // Write to ~/.sage/feedback/bug-reports.jsonl via Tauri fs (本地备份)
      const { appDataDir } = await import('@tauri-apps/api/path');
      const { writeTextFile, mkdir } = await import('@tauri-apps/plugin-fs');

      const dataDir = await appDataDir();
      const feedbackDir = `${dataDir}/feedback`;

      // Ensure directory exists
      try {
        await mkdir(feedbackDir, { recursive: true });
      } catch {
        /* already exists */
      }

      // Append to JSONL file
      const filePath = `${feedbackDir}/bug-reports.jsonl`;
      try {
        const { readTextFile } = await import('@tauri-apps/plugin-fs');
        const existing = await readTextFile(filePath);
        await writeTextFile(filePath, existing + line);
      } catch {
        // File doesn't exist yet — create it
        await writeTextFile(filePath, line);
      }

      // ── 构造排查上下文 ──────────────────────────────────────────
      // 默认上报：轻量摘要（最近 3 条 user / 2 条 text，各截 240 字）+ 当前 provider/model
      // 可选附加：完整对话（用户勾选后才上传）
      const trunc = (
        s: string | null | undefined,
        max: number
      ): string | null => {
        if (!s) return null;
        const t = s.trim();
        return t.length <= max ? t : t.slice(0, max) + '…';
      };

      const userMessages = allMessages.filter((m) => m.type === 'user');
      const textMessages = allMessages.filter((m) => m.type === 'text');
      const recentUserMessages = userMessages
        .slice(-3)
        .map((m) => trunc(m.content, 240))
        .filter((x): x is string => !!x);
      const recentAgentReplies = textMessages
        .slice(-2)
        .map((m) => trunc(m.content, 240))
        .filter((x): x is string => !!x);

      // 找最近一条 result / error 消息的 subtype（发生过失败会有）
      const lastSystemMsg = [...allMessages]
        .reverse()
        .find((m) => m.type === 'result' || m.type === 'error');
      const lastSubtype = lastSystemMsg?.subtype ?? null;

      // 当前 AI 配置（不含 apiKey）
      const settings = getSettings();
      const aiConfig = {
        provider: settings.defaultProvider || null,
        model: settings.defaultModel || null,
        sandbox: settings.defaultSandboxProvider || null,
        agent_runtime: settings.defaultAgentRuntime || null,
      };

      const context: Record<string, unknown> = {
        local_report_id: report.id,
        task_id: taskId ?? null,
        ui_message_count: allMessages.length,
        recent_user_messages: recentUserMessages,
        recent_agent_replies: recentAgentReplies,
        last_system_subtype: lastSubtype,
        ai_config: aiConfig,
      };

      // 可选：完整对话（保留 type + content + tool 信息，去掉可能超大的 output）
      if (bugIncludeTranscript) {
        context.full_transcript = allMessages.map((m) => ({
          type: m.type,
          content: m.content ?? null,
          subtype: m.subtype ?? null,
          tool_name: m.name ?? null,
          // tool_use 的 input 截断防膨胀；tool_result 的 output 保留但截断
          tool_input:
            typeof m.input === 'string'
              ? trunc(m.input, 2000)
              : m.input
                ? trunc(JSON.stringify(m.input), 2000)
                : null,
          tool_output: trunc(m.output, 2000),
          is_error: m.isError ?? null,
          message: m.message ?? null,
        }));
      }

      // 同步上报到云端 error_logs（error_type='feedback'）
      const { reportError } = await import('@/shared/sync');
      void reportError({
        error_type: 'feedback',
        error_code: bugCategory,
        message: bugDesc.trim() || `(${bugCategory} - 无描述)`,
        context,
      });

      setBugSubmitted(true);
      setBugDesc('');
      setBugIncludeTranscript(false);
      setTimeout(() => {
        setBugOpen(false);
        setBugSubmitted(false);
        setBugCategory('其他');
      }, 1500);
    } catch (err) {
      console.error('Failed to write bug report:', err);
    } finally {
      setBugSubmitting(false);
    }
  };

  return (
    <div className="agent-action-bar mt-2 flex items-center gap-1 opacity-0 transition-opacity group-hover/msgitem:opacity-100">
      {/* Copy answer */}
      <button
        onClick={handleCopyAnswer}
        className="text-muted-foreground hover:text-foreground hover:bg-muted flex items-center gap-1.5 rounded px-2 py-1 text-xs transition-colors"
        title="复制回答"
      >
        <Copy className="size-3" />
        <span>{copiedAnswer ? '已复制' : '复制回答'}</span>
      </button>

      {/* Copy full process */}
      <button
        onClick={handleCopyProcess}
        className="text-muted-foreground hover:text-foreground hover:bg-muted flex items-center gap-1.5 rounded px-2 py-1 text-xs transition-colors"
        title="复制完整过程（含工具调用记录）"
      >
        <Copy className="size-3" />
        <span>{copiedProcess ? '已复制' : '复制完整过程'}</span>
      </button>

      {/* Export as image */}
      <button
        onClick={handleExportImage}
        disabled={exportingImage}
        className="text-muted-foreground hover:text-foreground hover:bg-muted flex items-center gap-1.5 rounded px-2 py-1 text-xs transition-colors disabled:opacity-40"
        title="导出为图片（保存到下载目录）"
      >
        <Image className="size-3" />
        <span>{exportingImage ? '导出中…' : '导出图片'}</span>
      </button>

      {/* Bug report */}
      <div className="relative" ref={bugPopoverRef}>
        <button
          onClick={() => {
            setBugOpen((v) => !v);
            setBugSubmitted(false);
          }}
          className="text-muted-foreground hover:text-foreground hover:bg-muted flex items-center gap-1.5 rounded px-2 py-1 text-xs transition-colors"
          title="反馈问题"
        >
          <AlertTriangle className="size-3" />
          <span>反馈问题</span>
        </button>

        {bugOpen && (
          <div className="bg-popover border-border absolute bottom-full left-0 z-50 mb-2 w-72 rounded-lg border p-3 shadow-lg">
            {bugSubmitted ? (
              <div className="flex items-center gap-2 py-2 text-sm text-green-600 dark:text-green-400">
                <CheckCircle2 className="size-4" />
                <span>感谢反馈！</span>
              </div>
            ) : (
              <div className="flex flex-col gap-3">
                <p className="text-foreground text-xs font-semibold">
                  反馈问题类型
                </p>
                <div className="flex flex-col gap-1.5">
                  {BUG_CATEGORIES.map((cat) => (
                    <label
                      key={cat}
                      className="flex cursor-pointer items-center gap-2"
                    >
                      <input
                        type="radio"
                        name="bug-category"
                        value={cat}
                        checked={bugCategory === cat}
                        onChange={() => setBugCategory(cat)}
                        className="accent-primary"
                      />
                      <span className="text-foreground text-xs">{cat}</span>
                    </label>
                  ))}
                </div>
                <textarea
                  value={bugDesc}
                  onChange={(e) => setBugDesc(e.target.value)}
                  placeholder="补充说明（可选）"
                  rows={2}
                  className="border-border bg-muted text-foreground placeholder:text-muted-foreground w-full resize-none rounded border px-2 py-1.5 text-xs outline-none focus:ring-1 focus:ring-offset-0"
                />
                <label className="flex cursor-pointer items-start gap-2">
                  <input
                    type="checkbox"
                    checked={bugIncludeTranscript}
                    onChange={(e) => setBugIncludeTranscript(e.target.checked)}
                    className="accent-primary mt-0.5"
                  />
                  <span className="text-muted-foreground text-xs leading-snug">
                    附上完整对话帮助排查
                    <span className="text-muted-foreground/70 block">
                      将包含你的完整对话内容用于问题定位
                    </span>
                  </span>
                </label>
                <div className="flex justify-end gap-2">
                  <button
                    onClick={() => setBugOpen(false)}
                    className="text-muted-foreground hover:text-foreground rounded px-2 py-1 text-xs"
                  >
                    取消
                  </button>
                  <button
                    onClick={handleSubmitBug}
                    disabled={bugSubmitting}
                    className="bg-primary text-primary-foreground hover:bg-primary/90 rounded px-3 py-1 text-xs disabled:opacity-50"
                  >
                    {bugSubmitting ? '提交中…' : '提交'}
                  </button>
                </div>
              </div>
            )}
          </div>
        )}
      </div>
    </div>
  );
}

export { AgentActionBar };
