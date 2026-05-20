/**
 * MobileHomePage — welcome screen with centered input.
 * Shown when no task is active (similar to Gemini home screen).
 */

import { useCallback, useRef, useState } from 'react';
import { isModelConfigured } from '@/shared/db/settings';
import { AlertCircle, Send } from 'lucide-react';

interface MobileHomePageProps {
  onSubmit: (prompt: string) => void;
  onOpenSettings?: () => void;
}

export function MobileHomePage({
  onSubmit,
  onOpenSettings,
}: MobileHomePageProps) {
  const [value, setValue] = useState('');
  const inputRef = useRef<HTMLTextAreaElement>(null);
  const modelReady = isModelConfigured();

  const handleSubmit = useCallback(() => {
    const trimmed = value.trim();
    if (!trimmed) return;
    onSubmit(trimmed);
    setValue('');
  }, [value, onSubmit]);

  const handleKeyDown = (e: React.KeyboardEvent) => {
    if (e.key === 'Enter' && !e.shiftKey) {
      e.preventDefault();
      handleSubmit();
    }
  };

  return (
    <div className="flex h-full flex-col">
      {/* Center content */}
      <div className="flex flex-1 flex-col items-center justify-center px-6">
        <h1 className="text-foreground mb-2 text-3xl font-light tracking-tight">
          你好
        </h1>
        <p className="text-muted-foreground text-base">有什么可以帮你的？</p>

        {/* Model not configured banner */}
        {!modelReady && (
          <button
            onClick={onOpenSettings}
            className="mt-6 flex items-center gap-2.5 rounded-xl border border-amber-200 bg-amber-50 px-4 py-3 dark:border-amber-800 dark:bg-amber-950/30"
          >
            <AlertCircle className="size-5 shrink-0 text-amber-600 dark:text-amber-400" />
            <span className="text-sm text-amber-800 dark:text-amber-200">
              尚未配置模型，点击前往设置
            </span>
          </button>
        )}
      </div>

      {/* Bottom input */}
      <div className="shrink-0 px-4 pb-[calc(12px+var(--safe-area-bottom))]">
        <div className="border-border bg-muted/30 flex items-end gap-2 rounded-2xl border px-4 py-3">
          <textarea
            ref={inputRef}
            value={value}
            onChange={(e) => setValue(e.target.value)}
            onKeyDown={handleKeyDown}
            placeholder="问问 Sage..."
            className="text-foreground placeholder:text-muted-foreground max-h-32 min-h-[24px] flex-1 resize-none bg-transparent text-base leading-6 outline-none"
            rows={1}
          />
          <button
            onClick={handleSubmit}
            disabled={!value.trim() || !modelReady}
            className="bg-primary text-primary-foreground flex size-8 shrink-0 items-center justify-center rounded-full disabled:opacity-30"
          >
            <Send className="size-4" />
          </button>
        </div>
      </div>
    </div>
  );
}
