/**
 * Configuration readers for agent settings.
 * Read user preferences from local settings store.
 */

import { API_BASE_URL } from '@/config';
import { translations, type Language } from '@/config/locale';
import { getSettings } from '@/shared/db/settings';

const AGENT_SERVER_URL = API_BASE_URL;

// Helper to get current language translations
function getErrorMessages() {
  const settings = getSettings();
  const lang = (settings.language || 'zh-CN') as Language;
  return (
    translations[lang]?.common?.errors || translations['zh-CN'].common.errors
  );
}

function getPreferredLanguage(): string | undefined {
  const lang = getSettings().language;
  return lang && lang.trim() !== '' ? lang : undefined;
}

function getModelConfig():
  | { apiKey?: string; baseUrl?: string; model?: string; apiType?: string }
  | undefined {
  try {
    const settings = getSettings();

    // No provider configured — user needs to set one up
    if (!settings.defaultProvider || settings.defaultProvider === 'default') {
      return undefined;
    }

    const provider = settings.providers.find(
      (p) => p.id === settings.defaultProvider
    );

    if (!provider) return undefined;

    const config: {
      apiKey?: string;
      baseUrl?: string;
      model?: string;
      apiType?: string;
    } = {};

    if (provider.apiKey) {
      config.apiKey = provider.apiKey;
    }
    if (provider.baseUrl) {
      config.baseUrl = provider.baseUrl;
    }
    if (settings.defaultModel) {
      config.model = settings.defaultModel;
    }
    if (provider.apiType) {
      config.apiType = provider.apiType;
    }

    // Return undefined if no API key configured
    if (!config.apiKey) {
      return undefined;
    }

    return config;
  } catch (error) {
    console.error('[useAgent] getModelConfig error:', error);
    return undefined;
  }
}

// Helper to get sandbox configuration from settings
function getSandboxConfig():
  | { enabled: boolean; provider?: string; apiEndpoint?: string }
  | undefined {
  try {
    const settings = getSettings();

    // More detailed logging for debugging production issues
    console.log('[useAgent] getSandboxConfig - Full settings check:', {
      sandboxEnabled: settings.sandboxEnabled,
      sandboxEnabledType: typeof settings.sandboxEnabled,
      defaultSandboxProvider: settings.defaultSandboxProvider,
      hasSettings: !!settings,
      settingsKeys: Object.keys(settings),
    });

    // Only return if sandbox is enabled
    if (!settings.sandboxEnabled) {
      console.warn(
        '[useAgent] ⚠️ Sandbox is DISABLED in settings - sandboxEnabled:',
        settings.sandboxEnabled
      );
      return undefined;
    }

    const config = {
      enabled: true,
      provider: settings.defaultSandboxProvider, // Use selected sandbox provider
      apiEndpoint: AGENT_SERVER_URL, // Use the same server
    };

    console.log('[useAgent] ✅ Sandbox ENABLED, returning config:', config);
    return config;
  } catch (error) {
    console.error('[useAgent] ❌ Error getting sandbox config:', error);
    return undefined;
  }
}

// Helper to get skills configuration from settings
function getSkillsConfig():
  | {
      enabled: boolean;
      userDirEnabled: boolean;
      appDirEnabled: boolean;
      skillsPath?: string;
    }
  | undefined {
  try {
    const settings = getSettings();

    // If global switch is off, return undefined (no skills)
    if (settings.skillsEnabled === false) {
      console.log('[useAgent] Skills disabled globally');
      return undefined;
    }

    const config = {
      enabled: true,
      userDirEnabled: settings.skillsUserDirEnabled !== false,
      appDirEnabled: settings.skillsAppDirEnabled !== false,
      skillsPath: settings.skillsPath || undefined,
    };

    console.log('[useAgent] Skills config:', config);
    return config;
  } catch {
    return undefined;
  }
}

// Helper to get MCP configuration from settings
function getMcpConfig():
  | {
      enabled: boolean;
      userDirEnabled: boolean;
      appDirEnabled: boolean;
      mcpConfigPath?: string;
    }
  | undefined {
  try {
    const settings = getSettings();

    // If global switch is off, return undefined (no MCP)
    if (settings.mcpEnabled === false) {
      console.log('[useAgent] MCP disabled globally');
      return undefined;
    }

    const config = {
      enabled: true,
      userDirEnabled: settings.mcpUserDirEnabled !== false,
      appDirEnabled: settings.mcpAppDirEnabled !== false,
      mcpConfigPath: settings.mcpConfigPath || undefined,
    };

    console.log('[useAgent] MCP config:', config);
    return config;
  } catch {
    return undefined;
  }
}

export {
  getErrorMessages,
  getPreferredLanguage,
  getModelConfig,
  getSandboxConfig,
  getSkillsConfig,
  getMcpConfig,
};
