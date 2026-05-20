/**
 * MobileSettings — full-screen settings page for iOS.
 * Includes model provider config, theme, language, and account.
 */

import { useCallback, useState } from 'react';
import {
  getSettings,
  saveSettings,
  type AIProvider,
} from '@/shared/db/settings';
import { ChevronRight, Eye, EyeOff, LogOut, Moon, Sun, X } from 'lucide-react';
import { useAuth } from '@/shared/providers/auth-provider';
import { useLanguage } from '@/shared/providers/language-provider';
import { useTheme } from '@/shared/providers/theme-provider';

interface MobileSettingsProps {
  onClose: () => void;
}

export function MobileSettings({ onClose }: MobileSettingsProps) {
  const [settings, setSettings] = useState(getSettings());
  const [editingProvider, setEditingProvider] = useState<AIProvider | null>(
    null
  );
  const [showKey, setShowKey] = useState(false);
  const { user, signOut } = useAuth();
  const { language, setLanguage, t } = useLanguage();
  const { theme, setTheme } = useTheme();

  const handleSave = useCallback((updated: typeof settings) => {
    saveSettings(updated);
    setSettings({ ...updated });
  }, []);

  const handleProviderToggle = useCallback(
    (providerId: string, enabled: boolean) => {
      const updated = { ...settings };
      const provider = updated.providers.find((p) => p.id === providerId);
      if (provider) {
        provider.enabled = enabled;
        handleSave(updated);
      }
    },
    [settings, handleSave]
  );

  const handleSetDefault = useCallback(
    (providerId: string) => {
      const updated = { ...settings };
      const provider = updated.providers.find((p) => p.id === providerId);
      if (provider) {
        updated.defaultProvider = providerId;
        updated.defaultModel =
          provider.defaultModel || provider.models?.[0] || '';
        handleSave(updated);
      }
    },
    [settings, handleSave]
  );

  const handleSaveProvider = useCallback(
    (provider: AIProvider) => {
      const updated = { ...settings };
      const idx = updated.providers.findIndex((p) => p.id === provider.id);
      if (idx >= 0) {
        updated.providers[idx] = provider;
      } else {
        updated.providers.push(provider);
      }
      // Auto-set as default if it's the first configured provider
      if (provider.apiKey && !updated.defaultProvider) {
        updated.defaultProvider = provider.id;
        updated.defaultModel =
          provider.defaultModel || provider.models?.[0] || '';
      }
      handleSave(updated);
      setEditingProvider(null);
    },
    [settings, handleSave]
  );

  // Provider edit view
  if (editingProvider) {
    return (
      <ProviderEditView
        provider={editingProvider}
        onSave={handleSaveProvider}
        onCancel={() => setEditingProvider(null)}
        showKey={showKey}
        setShowKey={setShowKey}
      />
    );
  }

  // Main settings view
  const activeProvider = settings.providers.find(
    (p) => p.id === settings.defaultProvider
  );

  return (
    <div className="bg-background flex h-full flex-col">
      {/* Header */}
      <div className="flex shrink-0 items-center justify-between px-4 py-3">
        <h1 className="text-foreground text-lg font-semibold">设置</h1>
        <button
          onClick={onClose}
          className="text-muted-foreground hover:text-foreground flex size-8 items-center justify-center rounded-lg"
        >
          <X className="size-5" />
        </button>
      </div>

      {/* Content */}
      <div className="flex-1 overflow-y-auto px-4 pb-[var(--safe-area-bottom)]">
        {/* Current model */}
        <section className="mb-6">
          <h2 className="text-muted-foreground mb-2 text-xs font-medium tracking-wider uppercase">
            当前模型
          </h2>
          <div className="bg-muted/30 border-border rounded-xl border p-4">
            {activeProvider ? (
              <div>
                <div className="text-foreground font-medium">
                  {activeProvider.name}
                </div>
                <div className="text-muted-foreground mt-0.5 text-sm">
                  {settings.defaultModel || '未选择模型'}
                </div>
              </div>
            ) : (
              <div className="text-muted-foreground text-sm">
                未配置模型，请选择一个供应商并填入 API Key
              </div>
            )}
          </div>
        </section>

        {/* Provider list */}
        <section>
          <h2 className="text-muted-foreground mb-2 text-xs font-medium tracking-wider uppercase">
            供应商
          </h2>
          <div className="border-border divide-border divide-y rounded-xl border">
            {settings.providers.map((provider) => (
              <button
                key={provider.id}
                onClick={() => setEditingProvider({ ...provider })}
                className="flex w-full items-center gap-3 px-4 py-3.5 text-left"
              >
                <div className="bg-muted flex size-9 items-center justify-center rounded-lg text-sm font-medium">
                  {provider.icon || provider.name.charAt(0)}
                </div>
                <div className="min-w-0 flex-1">
                  <div className="text-foreground text-sm font-medium">
                    {provider.name}
                  </div>
                  <div className="text-muted-foreground text-xs">
                    {provider.apiKey ? '已配置' : '未配置'}
                    {provider.id === settings.defaultProvider && ' · 默认'}
                  </div>
                </div>
                <ChevronRight className="text-muted-foreground size-4 shrink-0" />
              </button>
            ))}
          </div>
        </section>

        {/* Theme */}
        <section className="mt-6">
          <h2 className="text-muted-foreground mb-2 text-xs font-medium tracking-wider uppercase">
            主题
          </h2>
          <div className="border-border divide-border flex divide-x rounded-xl border">
            {(['light', 'dark', 'system'] as const).map((t) => (
              <button
                key={t}
                onClick={() => setTheme(t)}
                className={`flex flex-1 items-center justify-center gap-2 py-3 text-sm ${
                  theme === t ? 'text-primary font-medium' : 'text-muted-foreground'
                }`}
              >
                {t === 'light' && <Sun className="size-4" />}
                {t === 'dark' && <Moon className="size-4" />}
                {t === 'light' ? '浅色' : t === 'dark' ? '深色' : '跟随系统'}
              </button>
            ))}
          </div>
        </section>

        {/* Language */}
        <section className="mt-6">
          <h2 className="text-muted-foreground mb-2 text-xs font-medium tracking-wider uppercase">
            语言
          </h2>
          <div className="border-border divide-border flex divide-x rounded-xl border">
            {(['zh', 'en'] as const).map((lang) => (
              <button
                key={lang}
                onClick={() => setLanguage(lang)}
                className={`flex-1 py-3 text-sm ${
                  language === lang ? 'text-primary font-medium' : 'text-muted-foreground'
                }`}
              >
                {lang === 'zh' ? '中文' : 'English'}
              </button>
            ))}
          </div>
        </section>

        {/* Account */}
        <section className="mt-6">
          <h2 className="text-muted-foreground mb-2 text-xs font-medium tracking-wider uppercase">
            账号
          </h2>
          <div className="border-border rounded-xl border">
            <div className="px-4 py-3.5">
              <div className="text-foreground text-sm font-medium">
                {user?.email || '未登录'}
              </div>
              <div className="text-muted-foreground text-xs mt-0.5">
                ID: {user?.id?.slice(0, 8) || '-'}
              </div>
            </div>
            <div className="border-border border-t">
              <button
                onClick={signOut}
                className="flex w-full items-center gap-3 px-4 py-3.5 text-left text-red-500"
              >
                <LogOut className="size-4" />
                <span className="text-sm font-medium">退出登录</span>
              </button>
            </div>
          </div>
        </section>

        {/* Version info */}
        <div className="mt-8 mb-4 text-center">
          <p className="text-muted-foreground text-xs">Sage iOS v1.0.0</p>
        </div>
      </div>
    </div>
  );
}

// ─── Provider Edit Sub-view ─────────────────────────────────────────────────

interface ProviderEditViewProps {
  provider: AIProvider;
  onSave: (provider: AIProvider) => void;
  onCancel: () => void;
  showKey: boolean;
  setShowKey: (show: boolean) => void;
}

function ProviderEditView({
  provider,
  onSave,
  onCancel,
  showKey,
  setShowKey,
}: ProviderEditViewProps) {
  const [draft, setDraft] = useState<AIProvider>({ ...provider });

  return (
    <div className="bg-background flex h-full flex-col">
      {/* Header */}
      <div className="flex shrink-0 items-center justify-between px-4 py-3">
        <button onClick={onCancel} className="text-primary text-sm font-medium">
          取消
        </button>
        <h1 className="text-foreground text-base font-semibold">
          {draft.name}
        </h1>
        <button
          onClick={() => onSave(draft)}
          className="text-primary text-sm font-semibold"
        >
          保存
        </button>
      </div>

      {/* Form */}
      <div className="flex-1 overflow-y-auto px-4 pb-[var(--safe-area-bottom)]">
        {/* API Key */}
        <section className="mb-5">
          <label className="text-muted-foreground mb-1.5 block text-xs font-medium uppercase">
            API Key
          </label>
          <div className="border-border flex items-center gap-2 rounded-xl border px-4 py-3">
            <input
              type="text"
              value={draft.apiKey}
              onChange={(e) => setDraft({ ...draft, apiKey: e.target.value })}
              placeholder="sk-..."
              className="text-foreground placeholder:text-muted-foreground flex-1 bg-transparent text-base outline-none"
              style={
                showKey
                  ? undefined
                  : ({ WebkitTextSecurity: 'disc' } as React.CSSProperties)
              }
              autoComplete="off"
              autoCorrect="off"
              autoCapitalize="off"
              spellCheck={false}
            />
            <button
              onClick={() => setShowKey(!showKey)}
              className="text-muted-foreground"
            >
              {showKey ? (
                <EyeOff className="size-4" />
              ) : (
                <Eye className="size-4" />
              )}
            </button>
          </div>
          {provider.apiKeyUrl && (
            <a
              href={provider.apiKeyUrl}
              target="_blank"
              rel="noopener noreferrer"
              className="text-primary mt-1.5 block text-xs"
            >
              获取 API Key →
            </a>
          )}
        </section>

        {/* Base URL */}
        <section className="mb-5">
          <label className="text-muted-foreground mb-1.5 block text-xs font-medium uppercase">
            Base URL
          </label>
          <div className="border-border rounded-xl border px-4 py-3">
            <input
              type="url"
              value={draft.baseUrl}
              onChange={(e) => setDraft({ ...draft, baseUrl: e.target.value })}
              placeholder="https://api.openai.com"
              className="text-foreground placeholder:text-muted-foreground w-full bg-transparent text-base outline-none"
            />
          </div>
        </section>

        {/* Model selection */}
        <section className="mb-5">
          <label className="text-muted-foreground mb-1.5 block text-xs font-medium uppercase">
            默认模型
          </label>
          <div className="border-border divide-border divide-y rounded-xl border">
            {draft.models.map((model) => (
              <button
                key={model}
                onClick={() => setDraft({ ...draft, defaultModel: model })}
                className="flex w-full items-center gap-3 px-4 py-3 text-left"
              >
                <div
                  className={`size-4 rounded-full border-2 ${
                    draft.defaultModel === model
                      ? 'border-primary bg-primary'
                      : 'border-muted-foreground'
                  }`}
                />
                <span className="text-foreground text-sm">{model}</span>
              </button>
            ))}
          </div>
        </section>

        {/* Set as default provider */}
        <section className="mb-5">
          <button
            onClick={() => onSave({ ...draft })}
            className="bg-primary text-primary-foreground w-full rounded-xl py-3 text-sm font-medium"
          >
            保存并设为默认
          </button>
        </section>
      </div>
    </div>
  );
}
