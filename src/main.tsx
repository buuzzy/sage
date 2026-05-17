import '@ant-design/v5-patch-for-react-19';

import React, { useCallback, useEffect, useState } from 'react';
import ReactDOM from 'react-dom/client';
import { RouterProvider } from 'react-router-dom';

import { router } from './app/router';
import { ErrorBoundary } from './components/error-boundary';
import {
  StartupScreen,
  type StartupDiagnostic,
  type StartupStep,
} from './components/startup/StartupScreen';
import { API_BASE_URL } from './config';
import { initializeSettings } from './shared/db/settings';
import { AntdThemeProvider } from './shared/providers/antd-theme-provider';
import { AuthProvider } from './shared/providers/auth-provider';
import { LanguageProvider } from './shared/providers/language-provider';
import { ThemeProvider } from './shared/providers/theme-provider';
import { UpdateProvider } from './shared/providers/update-provider';
import {
  flushErrorQueue,
  ProfileProvider,
  reportError,
  retryFailedChannels,
  SessionSyncProvider,
  SettingsSyncProvider,
} from './shared/sync';

import '@/config/style/global.css';

function AppProviders() {
  return (
    <LanguageProvider>
      <ThemeProvider>
        <AntdThemeProvider>
          <StartupHealthGate>
            <AuthProvider>
              <ProfileProvider>
                <SettingsSyncProvider>
                  <SessionSyncProvider>
                    <UpdateProvider>
                      <RouterProvider router={router} />
                    </UpdateProvider>
                  </SessionSyncProvider>
                </SettingsSyncProvider>
              </ProfileProvider>
            </AuthProvider>
          </StartupHealthGate>
        </AntdThemeProvider>
      </ThemeProvider>
    </LanguageProvider>
  );
}

function StartupHealthGate({ children }: { children: React.ReactNode }) {
  const isDesktop =
    typeof window !== 'undefined' && '__TAURI_INTERNALS__' in window;
  const [apiReady, setApiReady] = useState(!isDesktop);
  const [apiError, setApiError] = useState<string | null>(null);
  const [apiDiagnostics, setApiDiagnostics] = useState<StartupDiagnostic[]>([
    {
      label: 'Runtime',
      value: isDesktop ? 'Tauri desktop' : 'Web / iOS',
      tone: isDesktop ? 'default' : 'success',
    },
    {
      label: 'Endpoint',
      value: `${API_BASE_URL}/health`,
    },
  ]);

  const checkApi = useCallback(async () => {
    if (!isDesktop) {
      setApiReady(true);
      setApiDiagnostics([
        { label: 'Runtime', value: 'Web / iOS', tone: 'success' },
        { label: 'Local sidecar', value: 'not required', tone: 'success' },
      ]);
      return;
    }

    const endpoint = `${API_BASE_URL}/health`;
    const startedAt = Date.now();
    const controller = new AbortController();
    const timeout = window.setTimeout(() => controller.abort(), 6000);

    setApiError(null);
    setApiReady(false);
    setApiDiagnostics([
      { label: 'Runtime', value: 'Tauri desktop' },
      { label: 'Endpoint', value: endpoint },
      { label: 'Started', value: new Date(startedAt).toLocaleTimeString() },
      { label: 'Timeout', value: '6000ms' },
    ]);

    try {
      const response = await fetch(endpoint, {
        cache: 'no-store',
        signal: controller.signal,
      });
      const elapsedMs = Date.now() - startedAt;
      if (!response.ok) {
        throw new Error(`Local service returned ${response.status}`);
      }
      const body = (await response.json().catch(() => null)) as {
        status?: string;
        uptime?: number;
      } | null;
      setApiDiagnostics([
        { label: 'Runtime', value: 'Tauri desktop' },
        { label: 'Endpoint', value: endpoint },
        { label: 'HTTP status', value: String(response.status), tone: 'success' },
        { label: 'Latency', value: `${elapsedMs}ms`, tone: 'success' },
        {
          label: 'Sidecar status',
          value: body?.status ?? 'ok',
          tone: 'success',
        },
        ...(typeof body?.uptime === 'number'
          ? [
              {
                label: 'Sidecar uptime',
                value: `${Math.round(body.uptime)}s`,
              } satisfies StartupDiagnostic,
            ]
          : []),
      ]);
      setApiReady(true);
    } catch (error) {
      const elapsedMs = Date.now() - startedAt;
      console.error('[startup] local API health check failed:', error);
      const message =
        error instanceof Error && error.name === 'AbortError'
          ? 'Local Sage service did not respond within 6000ms'
          : error instanceof Error
            ? error.message
            : 'Local Sage service is not responding';
      setApiDiagnostics([
        { label: 'Runtime', value: 'Tauri desktop' },
        { label: 'Endpoint', value: endpoint },
        { label: 'Latency', value: `${elapsedMs}ms`, tone: 'error' },
        { label: 'Failure', value: message, tone: 'error' },
      ]);
      setApiError(
        message
      );
    } finally {
      window.clearTimeout(timeout);
    }
  }, [isDesktop]);

  useEffect(() => {
    void checkApi();
  }, [checkApi]);

  if (!apiReady) {
    const steps: StartupStep[] = [
      {
        id: 'app-shell',
        label: 'App shell ready',
        description: 'Theme and interface are loaded.',
        status: 'done',
      },
      {
        id: 'sidecar',
        label: 'Connecting local Sage service',
        description: 'Checking the desktop sidecar API before conversations.',
        status: apiError ? 'error' : 'active',
      },
      {
        id: 'auth',
        label: 'Restoring account',
        description: 'Authentication starts after the local service is ready.',
        status: 'pending',
      },
    ];

    return (
      <StartupScreen
        title="Connecting Sage"
        subtitle="Checking the local service that powers desktop conversations."
        steps={steps}
        diagnostics={apiDiagnostics}
        error={apiError ?? undefined}
        onRetry={apiError ? checkApi : undefined}
        compact
      />
    );
  }

  return <>{children}</>;
}

function BootstrapRoot() {
  const [settingsReady, setSettingsReady] = useState(false);
  const [settingsError, setSettingsError] = useState<string | null>(null);
  const [settingsDiagnostics, setSettingsDiagnostics] = useState<
    StartupDiagnostic[]
  >([]);

  const boot = useCallback(async () => {
    const startedAt = Date.now();
    setSettingsError(null);
    setSettingsReady(false);
    setSettingsDiagnostics([
      { label: 'Stage', value: 'settings' },
      { label: 'Started', value: new Date(startedAt).toLocaleTimeString() },
    ]);
    try {
      await initializeSettings();
      const elapsedMs = Date.now() - startedAt;
      setSettingsDiagnostics([
        { label: 'Stage', value: 'settings', tone: 'success' },
        { label: 'Latency', value: `${elapsedMs}ms`, tone: 'success' },
        { label: 'Theme support', value: 'black / white / warm', tone: 'success' },
      ]);
      setSettingsReady(true);
      void flushErrorQueue();
    } catch (error) {
      const elapsedMs = Date.now() - startedAt;
      console.error('[startup] initializeSettings failed:', error);
      setSettingsDiagnostics([
        { label: 'Stage', value: 'settings', tone: 'error' },
        { label: 'Latency', value: `${elapsedMs}ms`, tone: 'error' },
        {
          label: 'Failure',
          value:
            error instanceof Error
              ? error.message
              : 'Failed to initialize settings',
          tone: 'error',
        },
      ]);
      setSettingsError(
        error instanceof Error ? error.message : 'Failed to initialize settings'
      );
    }
  }, []);

  useEffect(() => {
    void boot();
  }, [boot]);

  if (!settingsReady) {
    const steps: StartupStep[] = [
      {
        id: 'settings',
        label: 'Loading settings',
        description: 'Reading theme, language, and local preferences.',
        status: settingsError ? 'error' : 'active',
      },
      {
        id: 'theme',
        label: 'Applying Sage theme',
        description: 'Preparing the black, white, or warm background.',
        status: 'pending',
      },
      {
        id: 'app',
        label: 'Starting app shell',
        description: 'Mounting providers and conversation routes.',
        status: 'pending',
      },
    ];

    return (
      <StartupScreen
        title="Preparing Sage"
        subtitle="Setting up the app shell before your conversation starts."
        steps={steps}
        diagnostics={settingsDiagnostics}
        error={settingsError ?? undefined}
        onRetry={settingsError ? boot : undefined}
      />
    );
  }

  return <AppProviders />;
}

// ─── Global error listeners ──────────────────────────────────────────────────
//
// 注册一次即可，不会卸载。确保最早挂上，能抓到后续任何 React/异步错误。
// 注意：必须先挂 listener 再 render，免得首屏错误漏掉。

if (typeof window !== 'undefined') {
  window.addEventListener('error', (ev) => {
    // 忽略跨域 script error（window.onerror 的老 bug，message 就是字面量）
    if (ev.message === 'Script error.') return;
    void reportError({
      error_type: 'window_error',
      message: ev.message || 'Unknown window error',
      stack_trace: ev.error?.stack,
      context: {
        filename: ev.filename,
        lineno: ev.lineno,
        colno: ev.colno,
        url: window.location.href,
      },
    });
  });

  window.addEventListener('unhandledrejection', (ev) => {
    const reason = ev.reason;
    const message =
      (reason instanceof Error ? reason.message : null) ||
      (typeof reason === 'string' ? reason : null) ||
      'Unhandled promise rejection';
    void reportError({
      error_type: 'unhandled_rejection',
      message,
      stack_trace: reason instanceof Error ? reason.stack : undefined,
      context: {
        url: window.location.href,
        reason_type: typeof reason,
      },
    });
  });

  // 网络恢复时自动重试所有 failed 的同步链路
  //
  // 两条互补的触发源：
  //   1) `window.online` 事件 — 最理想情况，但 macOS WKWebView 常常不 emit
  //      （它维护自己的在线判断，和系统网络状态不一致）
  //   2) 定时轮询 — 兜底。每 5s 检查一次 failed 链路，但受指数退避控制：
  //      同一链路连续失败多次时不会频繁重试（15s → 30s → 60s → 120s 封顶）。
  //      这样长期断网时 UI 保持 failed 静止，不会反复闪"同步中"。
  //
  // force=true 表示忽略退避窗口，立刻试一次（online 事件和用户手动点击使用）。
  window.addEventListener('online', () => {
    console.log('[sync] window.online fired, retrying failed channels');
    void retryFailedChannels({ force: true });
    void flushErrorQueue();
  });

  const RETRY_POLL_MS = 5_000;
  setInterval(() => {
    void retryFailedChannels();
  }, RETRY_POLL_MS);
}

ReactDOM.createRoot(document.getElementById('root') as HTMLElement).render(
  <React.StrictMode>
    <ErrorBoundary>
      <BootstrapRoot />
    </ErrorBoundary>
  </React.StrictMode>
);
