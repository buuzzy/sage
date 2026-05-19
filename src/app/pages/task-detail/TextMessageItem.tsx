/**
 * TextMessageItem — renders an agent's text response with markdown,
 * embedded artifacts, and the action bar.
 */

import { useRef } from 'react';
import ReactMarkdown from 'react-markdown';
import remarkGfm from 'remark-gfm';

import { ArtifactRenderer } from '@/components/htui/ArtifactRenderer';
import type { AgentMessage } from '@/shared/hooks/useAgent';
import { extractArtifacts } from '@/shared/lib/artifactParser';
import { AgentActionBar } from './AgentActionBar';

function TextMessageItem({
  message,
  allMessages,
  taskId,
}: {
  message: AgentMessage;
  allMessages?: AgentMessage[];
  taskId?: string;
}) {
  const msgContainerRef = useRef<HTMLDivElement>(null);
  const { cleanText, artifacts: extractedArtifacts } = extractArtifacts(
    message.content || ''
  );

  return (
    <div
      ref={msgContainerRef}
      className="group/msgitem flex min-w-0 flex-col gap-3"
    >
      <Logo />
      <ArtifactRenderer artifacts={extractedArtifacts} />
      {cleanText.trim() && (
        <div className="prose prose-sm text-foreground max-w-none min-w-0 flex-1 overflow-hidden">
          <ReactMarkdown
            remarkPlugins={[remarkGfm]}
            components={{
              pre: ({ children }: any) => (
                <pre className="bg-muted max-w-full overflow-x-auto rounded-lg p-4">
                  {children}
                </pre>
              ),

              code: ({ className, children, ...props }: any) => {
                const isInline = !className;
                if (isInline) {
                  return (
                    <code
                      className="bg-muted rounded px-1.5 py-0.5 text-sm"
                      {...props}
                    >
                      {children}
                    </code>
                  );
                }
                return (
                  <code className={className} {...props}>
                    {children}
                  </code>
                );
              },

              a: ({ children, href }: any) => (
                <a
                  href={href}
                  onClick={async (e) => {
                    e.preventDefault();
                    if (href) {
                      try {
                        const { openUrl } =
                          await import('@tauri-apps/plugin-opener');
                        await openUrl(href);
                      } catch {
                        window.open(href, '_blank');
                      }
                    }
                  }}
                  className="text-primary cursor-pointer hover:underline"
                >
                  {children}
                </a>
              ),

              table: ({ children }: any) => (
                <div className="overflow-x-auto">
                  <table className="border-border border-collapse border">
                    {children}
                  </table>
                </div>
              ),

              th: ({ children }: any) => (
                <th className="border-border bg-muted border px-3 py-2 text-left">
                  {children}
                </th>
              ),

              td: ({ children }: any) => (
                <td className="border-border border px-3 py-2">{children}</td>
              ),
            }}
          >
            {cleanText}
          </ReactMarkdown>
        </div>
      )}
      {(cleanText.trim() || extractedArtifacts.length > 0) && (
        <AgentActionBar
          cleanText={cleanText}
          allMessages={allMessages ?? [message]}
          taskId={taskId}
          containerRef={msgContainerRef}
        />
      )}
    </div>
  );
}



export { TextMessageItem };
