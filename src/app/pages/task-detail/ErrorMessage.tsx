/**
 * ErrorMessage — displays error messages with special handling for
 * API key issues, model configuration, and structured error categories.
 */

import { useState } from 'react';

import { SettingsModal } from '@/components/settings';
import { useLanguage } from '@/shared/providers/language-provider';

function ErrorMessage({ message }: { message: string }) {
  const { t } = useLanguage();
  const [settingsOpen, setSettingsOpen] = useState(false);

  // Check if model is not configured (highest priority)
  if (message === '__MODEL_NOT_CONFIGURED__') {
    return (
      <>
        <div className="flex items-start gap-3 py-2">
          <div className="mt-0.5 flex size-5 shrink-0 items-center justify-center">
            <svg
              viewBox="0 0 16 16"
              className="size-4 text-amber-500"
              fill="currentColor"
            >
              <path d="M8 1a7 7 0 100 14A7 7 0 008 1zM7 4.5a1 1 0 112 0v3a1 1 0 11-2 0v-3zm1 7a1 1 0 100-2 1 1 0 000 2z" />
            </svg>
          </div>
          <div className="flex flex-col gap-1">
            <p className="text-muted-foreground text-sm">
              {t.common.errors.modelNotConfigured}
            </p>
            <button
              onClick={() => setSettingsOpen(true)}
              className="text-primary hover:text-primary/80 cursor-pointer text-left text-sm underline underline-offset-2"
            >
              {t.common.errors.configureModel}
            </button>
          </div>
        </div>
        <SettingsModal
          open={settingsOpen}
          onOpenChange={setSettingsOpen}
          initialCategory="model"
        />
      </>
    );
  }

  // Check if this is a Claude Code not found error
  if (message === '__CLAUDE_CODE_NOT_FOUND__') {
    return (
      <>
        <div className="flex items-start gap-3 py-2">
          <div className="mt-0.5 flex size-5 shrink-0 items-center justify-center">
            <svg
              viewBox="0 0 16 16"
              className="size-4 text-amber-500"
              fill="currentColor"
            >
              <path d="M8 1a7 7 0 100 14A7 7 0 008 1zM7 4.5a1 1 0 112 0v3a1 1 0 11-2 0v-3zm1 7a1 1 0 100-2 1 1 0 000 2z" />
            </svg>
          </div>
          <div className="flex flex-col gap-1">
            <p className="text-muted-foreground text-sm">
              {t.common.errors.claudeCodeNotFound}
            </p>
            <button
              onClick={() => setSettingsOpen(true)}
              className="text-primary hover:text-primary/80 cursor-pointer text-left text-sm underline underline-offset-2"
            >
              {t.common.errors.configureModel}
            </button>
          </div>
        </div>
        <SettingsModal
          open={settingsOpen}
          onOpenChange={setSettingsOpen}
          initialCategory="model"
        />
      </>
    );
  }

  // Check if this is an API key error (marker from backend)
  if (message === '__API_KEY_ERROR__') {
    return (
      <>
        <div className="flex items-start gap-3 py-2">
          <div className="mt-0.5 flex size-5 shrink-0 items-center justify-center">
            <svg
              viewBox="0 0 16 16"
              className="size-4 text-amber-500"
              fill="currentColor"
            >
              <path d="M8 1a7 7 0 100 14A7 7 0 008 1zM7 4.5a1 1 0 112 0v3a1 1 0 11-2 0v-3zm1 7a1 1 0 100-2 1 1 0 000 2z" />
            </svg>
          </div>
          <div className="flex flex-col gap-1">
            <p className="text-muted-foreground text-sm">
              {t.common.errors.apiKeyError}
            </p>
            <button
              onClick={() => setSettingsOpen(true)}
              className="text-primary hover:text-primary/80 cursor-pointer text-left text-sm underline underline-offset-2"
            >
              {t.common.errors.configureApiKey}
            </button>
          </div>
        </div>
        <SettingsModal
          open={settingsOpen}
          onOpenChange={setSettingsOpen}
          initialCategory="model"
        />
      </>
    );
  }

  // Check if this is a custom API error (format: __CUSTOM_API_ERROR__|baseUrl|logPath)
  const isCustomApiError = message.startsWith('__CUSTOM_API_ERROR__|');
  if (isCustomApiError) {
    const parts = message.split('|');
    const baseUrl = parts[1] || '';
    const logPath = parts[2] || '~/.sage/logs/sage.log';
    const errorMessage = (
      t.common.errors.customApiError ||
      'Custom API ({baseUrl}) may not be compatible with Claude Code SDK. Please check the API configuration or try a different provider. Log file: {logPath}'
    )
      .replace('{baseUrl}', baseUrl)
      .replace('{logPath}', logPath);

    return (
      <div className="flex items-start gap-3 py-2">
        <div className="mt-0.5 flex size-5 shrink-0 items-center justify-center">
          <svg
            viewBox="0 0 16 16"
            className="size-4 text-amber-500"
            fill="currentColor"
          >
            <path d="M8 1a7 7 0 100 14A7 7 0 008 1zM7 4.5a1 1 0 112 0v3a1 1 0 11-2 0v-3zm1 7a1 1 0 100-2 1 1 0 000 2z" />
          </svg>
        </div>
        <p className="text-muted-foreground text-sm">{errorMessage}</p>
      </div>
    );
  }

  // Check if this is an internal error (format: __INTERNAL_ERROR__|logPath)
  const isInternalError = message.startsWith('__INTERNAL_ERROR__|');
  if (isInternalError) {
    const logPath = message.split('|')[1] || '~/.sage/logs/sage.log';
    const errorMessage = (
      t.common.errors.internalError ||
      'Internal server error. Please check log file: {logPath}'
    ).replace('{logPath}', logPath);

    return (
      <div className="flex items-start gap-3 py-2">
        <div className="mt-0.5 flex size-5 shrink-0 items-center justify-center">
          <svg
            viewBox="0 0 16 16"
            className="text-destructive size-4"
            fill="currentColor"
          >
            <path d="M8 1a7 7 0 100 14A7 7 0 008 1zM7 4.5a1 1 0 112 0v3a1 1 0 11-2 0v-3zm1 7a1 1 0 100-2 1 1 0 000 2z" />
          </svg>
        </div>
        <p className="text-muted-foreground text-sm">{errorMessage}</p>
      </div>
    );
  }

  // Fallback: Check if error text contains API key related keywords
  const isApiKeyError =
    /invalid api key|api key|authentication|unauthorized|please run \/login/i.test(
      message
    );

  if (isApiKeyError) {
    return (
      <>
        <div className="flex items-start gap-3 py-2">
          <div className="mt-0.5 flex size-5 shrink-0 items-center justify-center">
            <svg
              viewBox="0 0 16 16"
              className="size-4 text-amber-500"
              fill="currentColor"
            >
              <path d="M8 1a7 7 0 100 14A7 7 0 008 1zM7 4.5a1 1 0 112 0v3a1 1 0 11-2 0v-3zm1 7a1 1 0 100-2 1 1 0 000 2z" />
            </svg>
          </div>
          <div className="flex flex-col gap-1">
            <p className="text-muted-foreground text-sm">
              {t.common.errors.apiKeyError}
            </p>
            <button
              onClick={() => setSettingsOpen(true)}
              className="text-primary hover:text-primary/80 cursor-pointer text-left text-sm underline underline-offset-2"
            >
              {t.common.errors.configureApiKey}
            </button>
          </div>
        </div>
        <SettingsModal
          open={settingsOpen}
          onOpenChange={setSettingsOpen}
          initialCategory="model"
        />
      </>
    );
  }

  return (
    <div className="flex items-start gap-3 py-2">
      <div className="mt-0.5 flex size-5 shrink-0 items-center justify-center">
        <svg
          viewBox="0 0 16 16"
          className="text-destructive size-4"
          fill="currentColor"
        >
          <path d="M8 1a7 7 0 100 14A7 7 0 008 1zM7 4.5a1 1 0 112 0v3a1 1 0 11-2 0v-3zm1 7a1 1 0 100-2 1 1 0 000 2z" />
        </svg>
      </div>
      <p className="text-muted-foreground text-sm">{message}</p>
    </div>
  );
}

export { ErrorMessage };
