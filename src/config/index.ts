/**
 * Application Configuration
 *
 * Centralized configuration for the application.
 */

// =============================================================================
// API Configuration
// =============================================================================

/**
 * API port — unified at 2026 for both dev and production.
 * WeClaw and other channel integrations always connect to this port.
 */
export const API_PORT = 2026;

/**
 * API base URL
 *
 * Both Tauri desktop and Web connect to the same Railway cloud backend.
 * This ensures consistent data (sessions, skills, MCP) across all platforms.
 *
 * Dev mode: override with VITE_API_URL=http://localhost:2026 if needed.
 */
const isTauri =
  typeof window !== 'undefined' && '__TAURI_INTERNALS__' in window;

const RAILWAY_URL = 'https://sage-production-28e1.up.railway.app';

export const API_BASE_URL =
  import.meta.env.VITE_API_URL || RAILWAY_URL;

/**
 * Whether to use local SQLite as the primary data store.
 *
 * When connecting to Railway cloud backend, we skip local SQLite and use
 * IndexedDB + Supabase instead (same as iOS/Web). This ensures session
 * history is consistent across all platforms.
 *
 * Set VITE_USE_LOCAL_SQLITE=1 to force local SQLite (for offline dev).
 */
export const USE_LOCAL_SQLITE =
  import.meta.env.VITE_USE_LOCAL_SQLITE === '1' ||
  (isTauri && !!import.meta.env.VITE_API_URL);

// =============================================================================
// App Configuration
// =============================================================================

/**
 * App name（用户可见品牌名）
 */
export const APP_NAME = 'Sage';

/**
 * App identifier (must match tauri.conf.json)
 */
export const APP_IDENTIFIER = 'ai.sage.app';
