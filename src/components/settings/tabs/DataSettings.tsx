/**
 * Data Settings - Storage paths, Export, Cloud Restore, and Clear Data
 *
 * 合并了原「工作区」(Workspace) 和「数据」(Data) 两个 Tab。
 * 布局分三段：存储路径 → 备份与恢复 → 危险区域。
 */

import { useEffect, useState } from 'react';
import { API_BASE_URL } from '@/config';
import {
  deleteMessagesByTaskId,
  deleteTask,
  getAllFiles,
  getAllSessions,
  getAllTasks,
  getCurrentBoundUid,
  getMessagesByTaskId,
} from '@/shared/db';
import {
  clearAllSettings,
  getSettings,
  type Settings,
} from '@/shared/db/settings';
import { getPathSeparator, getSessionsDir } from '@/shared/lib/paths';
import { getUserSessionsDir } from '@/shared/lib/user-scoped-paths';
import { cn } from '@/shared/lib/utils';
import { useLanguage } from '@/shared/providers/language-provider';
import { clearCloudConversations } from '@/shared/sync';
import { restoreCloudConversations } from '@/shared/sync/cloud-restore';
import {
  AlertTriangle,
  CheckCircle2,
  Download,
  FileText,
  FolderOpen,
  Loader2,
  Trash2,
} from 'lucide-react';

// Check if running in Tauri environment
function isTauri(): boolean {
  if (typeof window === 'undefined') return false;
  return '__TAURI_INTERNALS__' in window || '__TAURI__' in window;
}

interface ExportData {
  version: number;
  exportedAt: string;
  sessions: unknown[];
  tasks: unknown[];
  messages: unknown[];
  files: unknown[];
  settings?: Settings;
}

type OperationStatus = 'idle' | 'loading' | 'success' | 'error';
type ClearType = 'tasks' | 'settings' | 'all' | null;

// Helper function to open folder/file in system file manager
const openInSystem = async (folderPath: string) => {
  try {
    const response = await fetch(`${API_BASE_URL}/files/open`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ path: folderPath, expandHome: true }),
    });
    const data = await response.json();
    if (!data.success) {
      console.error('[DataSettings] Failed to open path:', data.error);
    }
  } catch (err) {
    console.error('[DataSettings] Error opening path:', err);
  }
};

interface DataSettingsProps {
  settings: Settings;
  onSettingsChange: (settings: Settings) => void;
  defaultPaths: {
    workDir: string;
    mcpConfigPath: string;
    skillsPath: string;
  };
}

export function DataSettings({ settings, defaultPaths }: DataSettingsProps) {
  const { t } = useLanguage();
  const [pathSep, setPathSep] = useState('/');
  const [exportStatus, setExportStatus] = useState<OperationStatus>('idle');
  const [cloudRestoreStatus, setCloudRestoreStatus] =
    useState<OperationStatus>('idle');
  const [clearStatus, setClearStatus] = useState<OperationStatus>('idle');
  const [showClearDialog, setShowClearDialog] = useState(false);
  const [confirmClearType, setConfirmClearType] = useState<ClearType>(null);
  const [errorMessage, setErrorMessage] = useState<string>('');

  // Load platform-aware path separator
  useEffect(() => {
    getPathSeparator().then(setPathSep);
  }, []);

  const workDir = settings.workDir || defaultPaths.workDir;
  const logFilePath = `${workDir}${pathSep}logs${pathSep}sage.log`;

  // Export all data
  const handleExport = async () => {
    setExportStatus('loading');
    setErrorMessage('');

    try {
      // Gather all data
      const sessions = await getAllSessions();
      const tasks = await getAllTasks();
      const files = await getAllFiles();
      const currentSettings = getSettings();

      // Get messages for each task
      const allMessages: unknown[] = [];
      for (const task of tasks) {
        const messages = await getMessagesByTaskId(task.id);
        allMessages.push(...messages);
      }

      const exportData: ExportData = {
        version: 1,
        exportedAt: new Date().toISOString(),
        sessions,
        tasks,
        messages: allMessages,
        files,
        settings: currentSettings,
      };

      const jsonString = JSON.stringify(exportData, null, 2);
      const filename = `sage-backup-${new Date().toISOString().split('T')[0]}.json`;

      // Use Tauri native dialog
      const { save } = await import('@tauri-apps/plugin-dialog');
      const { writeTextFile } = await import('@tauri-apps/plugin-fs');

      const filePath = await save({
        filters: [{ name: 'JSON', extensions: ['json'] }],
        defaultPath: filename,
      });

      if (filePath) {
        await writeTextFile(filePath, jsonString);
        setExportStatus('success');
        setTimeout(() => setExportStatus('idle'), 2000);
      } else {
        // User cancelled
        setExportStatus('idle');
      }
    } catch (error) {
      console.error('[DataSettings] Export failed:', error);
      setErrorMessage(error instanceof Error ? error.message : 'Export failed');
      setExportStatus('error');
      setTimeout(() => setExportStatus('idle'), 3000);
    }
  };

  const handleCloudRestore = async () => {
    setCloudRestoreStatus('loading');
    setErrorMessage('');

    try {
      const shouldRestore = window.confirm(
        t.settings.dataCloudRestoreConfirm ||
          'Restore cloud sessions, tasks, messages, and files into this device? Existing records with the same IDs will be updated.'
      );
      if (!shouldRestore) {
        setCloudRestoreStatus('idle');
        return;
      }

      const result = await restoreCloudConversations();
      console.log('[DataSettings] Restored cloud conversations:', result);
      setCloudRestoreStatus('success');
      setTimeout(() => {
        setCloudRestoreStatus('idle');
        window.location.reload();
      }, 1500);
    } catch (error) {
      console.error('[DataSettings] Cloud restore failed:', error);
      setErrorMessage(
        error instanceof Error ? error.message : 'Cloud restore failed'
      );
      setCloudRestoreStatus('error');
      setTimeout(() => setCloudRestoreStatus('idle'), 3000);
    }
  };

  // Clear sidecar's in-memory channel conversation store.
  //
  // Without this, `useChannelSync` (polling every 3s) would re-fetch any
  // channel-originated conversation still living in the sidecar's memory
  // *after* the user wiped local DB — re-creating tasks for the very
  // messages we just deleted. Especially noticeable for the most recent
  // user message, since it sits at the top of the polling response.
  // Best-effort: never throw, never block the rest of the cleanup chain.
  const clearSidecarChannels = async () => {
    try {
      const res = await fetch(`${API_BASE_URL}/channels/conversations/all`, {
        method: 'DELETE',
      });
      if (!res.ok) {
        console.warn(
          '[DataSettings] Sidecar channel clear non-OK:',
          res.status
        );
      } else {
        const body = (await res.json().catch(() => null)) as {
          ok?: boolean;
          count?: number;
        } | null;
        console.log(
          '[DataSettings] Cleared sidecar channels:',
          body?.count ?? 0
        );
      }
    } catch (err) {
      console.warn('[DataSettings] Failed to clear sidecar channels:', err);
    }

    // Also drop the local "tombstone" set used by useChannelSync — it tracks
    // IDs the user previously deleted to suppress re-creation. After a full
    // wipe the set is no longer needed and risks growing unboundedly across
    // the user's lifetime.
    try {
      localStorage.removeItem('channelSync:deletedIds');
    } catch {
      /* ignore */
    }
  };

  // Clear workspace files (sessions directory for the CURRENT user only).
  const clearWorkspaceFiles = async () => {
    if (!isTauri()) return;

    try {
      const uid = getCurrentBoundUid();
      const sessionsDir = uid
        ? await getUserSessionsDir(uid)
        : await getSessionsDir();
      const { remove, exists } = await import('@tauri-apps/plugin-fs');

      const dirExists = await exists(sessionsDir);
      if (dirExists) {
        await remove(sessionsDir, { recursive: true });
        console.log('[DataSettings] Cleared workspace files:', sessionsDir);
      }
    } catch (error) {
      console.warn('[DataSettings] Failed to clear workspace files:', error);
    }
  };

  // Clear data
  const handleClear = async (type: ClearType) => {
    if (!type) return;

    setClearStatus('loading');
    setErrorMessage('');
    setShowClearDialog(false);
    setConfirmClearType(null);

    try {
      if (type === 'settings') {
        await clearAllSettings();
      } else if (type === 'tasks') {
        await clearSidecarChannels();
        await clearCloudConversations();
        await clearWorkspaceFiles();
        const tasks = await getAllTasks();
        for (const task of tasks) {
          await deleteMessagesByTaskId(task.id);
          await deleteTask(task.id);
        }
      } else if (type === 'all') {
        await clearSidecarChannels();
        await clearCloudConversations();
        await clearWorkspaceFiles();
        const tasks = await getAllTasks();
        for (const task of tasks) {
          await deleteMessagesByTaskId(task.id);
          await deleteTask(task.id);
        }
        await clearAllSettings();
      }

      setClearStatus('success');
      setTimeout(() => {
        setClearStatus('idle');
        window.location.reload();
      }, 1500);
    } catch (error) {
      console.error('[DataSettings] Clear failed:', error);
      setErrorMessage(error instanceof Error ? error.message : 'Clear failed');
      setClearStatus('error');
      setTimeout(() => setClearStatus('idle'), 3000);
    }
  };

  const handleClearOptionClick = (type: ClearType) => {
    setConfirmClearType(type);
  };

  const getConfirmMessage = (type: ClearType): string => {
    switch (type) {
      case 'tasks':
        return (
          t.settings.dataClearTasksConfirm ||
          'Are you sure you want to delete all tasks and messages? This action cannot be undone.'
        );
      case 'settings':
        return (
          t.settings.dataClearSettingsConfirm ||
          'Are you sure you want to reset all settings to defaults? This action cannot be undone.'
        );
      case 'all':
        return (
          t.settings.dataClearAllConfirm ||
          'Are you sure you want to delete ALL data including tasks, messages, and settings? This action cannot be undone.'
        );
      default:
        return '';
    }
  };

  const getButtonContent = (
    status: OperationStatus,
    icon: React.ReactNode,
    label: string,
    loadingLabel: string
  ) => {
    if (status === 'loading') {
      return (
        <>
          <Loader2 className="size-4 animate-spin" />
          <span>{loadingLabel}</span>
        </>
      );
    }
    if (status === 'success') {
      return (
        <>
          <CheckCircle2 className="size-4 text-green-500" />
          <span>{t.settings.dataSuccess || 'Success'}</span>
        </>
      );
    }
    return (
      <>
        {icon}
        <span>{label}</span>
      </>
    );
  };

  return (
    <div className="space-y-6">
      {/* Description */}
      <p className="text-muted-foreground text-sm">
        {t.settings.dataDescription}
      </p>

      {/* ── Storage Section ── */}
      <div className="space-y-4">
        <h3 className="text-foreground text-sm font-semibold tracking-wide uppercase">
          {t.settings.dataStorageSection}
        </h3>

        {/* Working Directory */}
        <div className="flex flex-col gap-1.5">
          <label className="text-foreground text-sm font-medium">
            {t.settings.workingDirectory}
          </label>
          <p className="text-muted-foreground text-xs">
            {t.settings.workingDirectoryDescription}
          </p>
          <div className="flex items-center gap-2">
            <div className="border-input bg-muted text-foreground flex h-9 max-w-md flex-1 items-center rounded-lg border px-3 text-sm">
              {workDir || 'Loading...'}
            </div>
            <button
              onClick={() => openInSystem(workDir)}
              className="text-muted-foreground hover:text-foreground hover:bg-accent rounded p-2 transition-colors"
              title={t.settings.skillsOpenFolder}
            >
              <FolderOpen className="size-4" />
            </button>
          </div>
        </div>

        {/* Log File */}
        <div className="flex flex-col gap-1.5">
          <label className="text-foreground text-sm font-medium">
            {t.settings.logFile}
          </label>
          <p className="text-muted-foreground text-xs">
            {t.settings.logFileDescription}
          </p>
          <div className="flex items-center gap-2">
            <div className="border-input bg-muted text-foreground flex h-9 max-w-md flex-1 items-center rounded-lg border px-3 text-sm">
              {logFilePath}
            </div>
            <button
              onClick={() => openInSystem(logFilePath)}
              className="text-muted-foreground hover:text-foreground hover:bg-accent rounded p-2 transition-colors"
              title={t.settings.logFileOpen}
            >
              <FileText className="size-4" />
            </button>
          </div>
        </div>
      </div>

      {/* Divider */}
      <div className="border-border border-t" />

      {/* ── Backup & Restore Section ── */}
      <div className="space-y-4">
        <h3 className="text-foreground text-sm font-semibold tracking-wide uppercase">
          {t.settings.dataBackupSection}
        </h3>

        {/* Export Data */}
        <div className="border-border rounded-lg border p-4">
          <div className="flex items-start justify-between">
            <div className="flex-1">
              <h3 className="text-foreground font-medium">
                {t.settings.dataExport}
              </h3>
              <p className="text-muted-foreground mt-1 text-sm">
                {t.settings.dataExportDescription}
              </p>
            </div>
            <button
              onClick={handleExport}
              disabled={exportStatus === 'loading'}
              className={cn(
                'flex items-center gap-2 rounded-lg px-4 py-2 text-sm font-medium transition-colors',
                'bg-primary text-primary-foreground hover:bg-primary/90',
                'disabled:cursor-not-allowed disabled:opacity-50'
              )}
            >
              {getButtonContent(
                exportStatus,
                <Download className="size-4" />,
                t.settings.dataExportButton || 'Export',
                t.settings.dataExporting || 'Exporting...'
              )}
            </button>
          </div>
        </div>

        {/* Restore Cloud Data */}
        <div className="border-border rounded-lg border p-4">
          <div className="flex items-start justify-between">
            <div className="flex-1">
              <h3 className="text-foreground font-medium">
                {t.settings.dataCloudRestore}
              </h3>
              <p className="text-muted-foreground mt-1 text-sm">
                {t.settings.dataCloudRestoreDescription}
              </p>
            </div>
            <button
              onClick={handleCloudRestore}
              disabled={cloudRestoreStatus === 'loading'}
              className={cn(
                'flex items-center gap-2 rounded-lg px-4 py-2 text-sm font-medium transition-colors',
                'border-border text-foreground hover:bg-accent border',
                'disabled:cursor-not-allowed disabled:opacity-50'
              )}
            >
              {getButtonContent(
                cloudRestoreStatus,
                <Download className="size-4" />,
                t.settings.dataCloudRestoreButton || 'Restore',
                t.settings.dataCloudRestoring || 'Restoring...'
              )}
            </button>
          </div>
        </div>
      </div>

      {/* Divider */}
      <div className="border-border border-t" />

      {/* ── Danger Zone ── */}
      <div className="space-y-4">
        <h3 className="text-sm font-semibold tracking-wide text-red-500 uppercase">
          {t.settings.dataDangerSection}
        </h3>

        <div className="rounded-lg border border-red-500/20 bg-red-500/5 p-4">
          <div className="flex items-start justify-between">
            <div className="flex-1">
              <h3 className="text-foreground font-medium">
                {t.settings.dataClear}
              </h3>
              <p className="text-muted-foreground mt-1 text-sm">
                {t.settings.dataClearDescription}
              </p>
            </div>
            <button
              onClick={() => setShowClearDialog(true)}
              disabled={clearStatus === 'loading'}
              className={cn(
                'flex items-center gap-2 rounded-lg px-4 py-2 text-sm font-medium transition-colors',
                'bg-red-500/10 text-red-500 hover:bg-red-500/20',
                'disabled:cursor-not-allowed disabled:opacity-50'
              )}
            >
              {getButtonContent(
                clearStatus,
                <Trash2 className="size-4" />,
                t.settings.dataClearButton || 'Clear',
                t.settings.dataClearing || 'Clearing...'
              )}
            </button>
          </div>
        </div>
      </div>

      {/* Error Message */}
      {errorMessage && (
        <div className="flex items-center gap-2 rounded-lg bg-red-500/10 p-3 text-red-500">
          <AlertTriangle className="size-4 shrink-0" />
          <span className="text-sm">{errorMessage}</span>
        </div>
      )}

      {/* Clear Confirmation Dialog */}
      {showClearDialog && (
        <div className="bg-background/80 fixed inset-0 z-50 flex items-center justify-center backdrop-blur-sm">
          <div className="border-border bg-background mx-4 w-full max-w-md rounded-xl border p-6 shadow-lg">
            <div className="mb-4 flex items-center gap-3">
              <div className="flex size-10 items-center justify-center rounded-full bg-red-500/10 text-red-500">
                <AlertTriangle className="size-5" />
              </div>
              <h3 className="text-foreground text-lg font-semibold">
                {t.settings.dataClearConfirmTitle}
              </h3>
            </div>

            <p className="text-muted-foreground mb-6 text-sm">
              {t.settings.dataClearConfirmDescription}
            </p>

            <div className="space-y-3">
              <button
                onClick={() => handleClearOptionClick('tasks')}
                className={cn(
                  'flex w-full items-center justify-between rounded-lg px-4 py-3 text-left transition-colors',
                  'border-border hover:bg-accent border'
                )}
              >
                <div>
                  <div className="text-foreground font-medium">
                    {t.settings.dataClearTasksOnly}
                  </div>
                  <div className="text-muted-foreground text-sm">
                    {t.settings.dataClearTasksOnlyDescription}
                  </div>
                </div>
              </button>

              <button
                onClick={() => handleClearOptionClick('settings')}
                className={cn(
                  'flex w-full items-center justify-between rounded-lg px-4 py-3 text-left transition-colors',
                  'border-border hover:bg-accent border'
                )}
              >
                <div>
                  <div className="text-foreground font-medium">
                    {t.settings.dataClearSettingsOnly}
                  </div>
                  <div className="text-muted-foreground text-sm">
                    {t.settings.dataClearSettingsOnlyDescription}
                  </div>
                </div>
              </button>

              <button
                onClick={() => handleClearOptionClick('all')}
                className={cn(
                  'flex w-full items-center justify-between rounded-lg px-4 py-3 text-left transition-colors',
                  'border border-red-500/30 bg-red-500/5 hover:bg-red-500/10'
                )}
              >
                <div>
                  <div className="font-medium text-red-500">
                    {t.settings.dataClearAll}
                  </div>
                  <div className="text-muted-foreground text-sm">
                    {t.settings.dataClearAllDescription}
                  </div>
                </div>
              </button>
            </div>

            <button
              onClick={() => setShowClearDialog(false)}
              className="text-muted-foreground hover:text-foreground mt-4 w-full py-2 text-center text-sm transition-colors"
            >
              {t.settings.dataCancel || 'Cancel'}
            </button>
          </div>
        </div>
      )}

      {/* Confirmation Dialog */}
      {confirmClearType && (
        <div className="bg-background/80 fixed inset-0 z-60 flex items-center justify-center backdrop-blur-sm">
          <div className="border-border bg-background mx-4 w-full max-w-md rounded-xl border p-6 shadow-lg">
            <div className="mb-4 flex items-center gap-3">
              <div className="flex size-10 items-center justify-center rounded-full bg-red-500/10 text-red-500">
                <AlertTriangle className="size-5" />
              </div>
              <h3 className="text-foreground text-lg font-semibold">
                {t.settings.dataConfirmTitle}
              </h3>
            </div>

            <p className="text-muted-foreground mb-6 text-sm">
              {getConfirmMessage(confirmClearType)}
            </p>

            <div className="flex gap-3">
              <button
                onClick={() => setConfirmClearType(null)}
                className={cn(
                  'flex-1 rounded-lg px-4 py-2 text-sm font-medium transition-colors',
                  'border-border text-foreground hover:bg-accent border'
                )}
              >
                {t.settings.dataCancel || 'Cancel'}
              </button>
              <button
                onClick={() => handleClear(confirmClearType)}
                className={cn(
                  'flex-1 rounded-lg px-4 py-2 text-sm font-medium transition-colors',
                  'bg-red-500 text-white hover:bg-red-600'
                )}
              >
                {t.settings.dataConfirmClear}
              </button>
            </div>
          </div>
        </div>
      )}
    </div>
  );
}
