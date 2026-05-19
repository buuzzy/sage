/**
 * Platform detection utilities.
 *
 * Provides unified platform detection for conditional behavior across
 * Tauri desktop, Capacitor iOS, and plain web environments.
 */

// ─── Platform Flags ─────────────────────────────────────────────────────────

/** Running inside Tauri desktop shell */
export const isTauri =
  typeof window !== 'undefined' && '__TAURI_INTERNALS__' in window;

/** Running inside Capacitor native shell (iOS/Android) */
export const isCapacitor =
  typeof window !== 'undefined' &&
  // Capacitor injects window.Capacitor before any JS runs in the WebView.
  // Check both the object existence and the native platform flag.
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  ('Capacitor' in window && !!(window as any).Capacitor?.isNativePlatform?.()) ||
  // Fallback: Capacitor also sets this on the navigator
  (typeof navigator !== 'undefined' && /iPhone|iPad|iPod/.test(navigator.userAgent) && !isTauri);

/** Running in a plain browser (not wrapped by native shell) */
export const isWeb = !isTauri && !isCapacitor;

/** Running on a mobile-sized viewport OR inside Capacitor */
export const isMobile =
  isCapacitor ||
  (typeof window !== 'undefined' && window.innerWidth < 768);

/** Running on a desktop platform (Tauri or wide web) */
export const isDesktop = isTauri || (!isCapacitor && !isMobile);

// ─── Platform Enum ──────────────────────────────────────────────────────────

export type Platform = 'tauri' | 'capacitor' | 'web';

export function getPlatform(): Platform {
  if (isTauri) return 'tauri';
  if (isCapacitor) return 'capacitor';
  return 'web';
}
