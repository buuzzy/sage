/**
 * Platform detection utilities.
 *
 * Provides unified platform detection for conditional behavior across
 * Tauri desktop and plain web environments.
 */

// ─── Platform Flags ─────────────────────────────────────────────────────────

/** Running inside Tauri desktop shell */
export const isTauri =
  typeof window !== 'undefined' && '__TAURI_INTERNALS__' in window;

/** Running in a plain browser (not wrapped by native shell) */
export const isWeb = !isTauri;

/** Running on a mobile-sized viewport */
export const isMobile =
  typeof window !== 'undefined' && window.innerWidth < 768;

/** Running on a desktop platform (Tauri or wide web) */
export const isDesktop = isTauri || !isMobile;

// ─── Platform Enum ──────────────────────────────────────────────────────────

export type Platform = 'tauri' | 'web';

export function getPlatform(): Platform {
  if (isTauri) return 'tauri';
  return 'web';
}
