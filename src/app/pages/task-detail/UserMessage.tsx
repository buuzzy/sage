/**
 * UserMessage — renders a user's message bubble with optional attachments.
 */

import { Image } from 'lucide-react';

import { LazyImage } from '@/components/shared/LazyImage';
import type { MessageAttachment } from '@/shared/hooks/useAgent';

function UserMessage({
  content,
  attachments,
}: {
  content: string;
  attachments?: MessageAttachment[];
}) {
  // Debug logging for attachments
  if (attachments && attachments.length > 0) {
    console.log('[UserMessage] Rendering attachments:', attachments.length);
    attachments.forEach((a, i) => {
      console.log(
        `[UserMessage] Attachment ${i}: type=${a.type}, name=${a.name}, hasData=${!!a.data}, dataLength=${a.data?.length || 0}`
      );
    });
  }

  return (
    <div className="flex min-w-0 gap-3">
      <div className="min-w-0 flex-1"></div>
      <div className="bg-accent/50 max-w-[85%] min-w-0 rounded-xl px-4 py-3">
        {/* Display attachments (images) */}
        {attachments && attachments.length > 0 && (
          <div className="mb-2 flex flex-wrap gap-2">
            {attachments.map((attachment) =>
              attachment.type === 'image' ? (
                <LazyImage
                  key={attachment.id}
                  src={attachment.data}
                  alt={attachment.name}
                  className="max-h-48 max-w-full"
                  isDataLoading={attachment.isLoading}
                />
              ) : (
                <div
                  key={attachment.id}
                  className="bg-muted flex items-center gap-2 rounded-lg px-3 py-2"
                >
                  <FileText className="text-muted-foreground size-4" />
                  <span className="text-foreground text-sm">
                    {attachment.name}
                  </span>
                </div>
              )
            )}
          </div>
        )}
        {content && (
          <p className="text-foreground text-sm wrap-break-word whitespace-pre-wrap">
            {content}
          </p>
        )}
      </div>
    </div>
  );
}



export { UserMessage };
