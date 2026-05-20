# iOS Platform Support: Quick Reference

## Core Finding: iOS Works for Core Features ✅

The Sage app successfully runs on iOS via Capacitor with most core features working. However, advanced features like MCP, sandbox, and filesystem access are **not available**.

---

## What Works ✅

```
✅ Authentication (OAuth via Safari ASWebAuthenticationSession)
✅ Message creation & persistence (IndexedDB in WebView)
✅ Chat sessions & task management
✅ Cloud sync (fire-and-forget to Supabase)
✅ Settings storage (localStorage)
✅ Mobile-optimized UI
✅ User switching & data isolation
```

---

## What's Different vs Desktop

| Feature | Desktop (Tauri) | iOS (Capacitor) | Web |
|---------|---|---|---|
| Database | SQLite (native) | IndexedDB (WebView) | IndexedDB |
| Settings | SQLite/localStorage | localStorage | localStorage |
| Attachments | Filesystem paths | Base64 in IndexedDB | Base64 in IndexedDB |
| Sync Storage | SQLite queue | IndexedDB queue | IndexedDB queue |
| File Access | Full via Tauri | None | Input/download only |
| Performance | ~Instant | Slight delay | Browser-dependent |

---

## Known Limitations 🚨

1. **No Filesystem Access**
   - Can't save files to device directly
   - Attachments stored as base64 (increases storage size)
   - File preview limited to inline display

2. **IndexedDB Size Limit (~50MB)**
   - Large sessions may exceed quota
   - No warning before quota exceeded
   - **Mitigation:** Use cloud sync as primary storage

3. **No MCP/Sandbox Support**
   - Advanced features disabled on iOS
   - Settings for these features are saved but ignored
   - UI should gracefully hide these options

4. **Data Loss Risk**
   - If user clears app data → IndexedDB cleared
   - Recovery only via cloud sync
   - **Mitigation:** Encourage cloud backup

---

## Critical Implementation Details

### Database Fallback Chain
```
1. Check if Tauri (Desktop)
   ↓ YES: Use SQLite
   ↓ NO: Continue

2. Check if getIndexedDB() available (Browser/iOS)
   ↓ YES: Use IndexedDB
   ↓ NO: Error (shouldn't happen)
```

### Platform Detection Flags
```typescript
import { isTauri, isCapacitor, isWeb, isMobile } from '@/shared/lib/platform';

// Desktop only
if (isTauri) { /* filesystem ops */ }

// Mobile (iOS/Android)
if (isCapacitor) { /* use Capacitor APIs */ }

// Browser/web
if (isWeb) { /* standard web APIs */ }

// Mobile layout
if (isMobile) { /* show mobile UI */ }
```

### Settings on iOS

**Priority:**
1. localStorage (immediate access)
2. Cloud sync on changes

**Note:** MCP/skills paths saved but not used on iOS

### Attachments on iOS

**Storage:** Base64 strings in IndexedDB  
**Max Size:** ~50MB total (all attachments + data)  
**No:** Direct filesystem access  
**Yes:** Cloud sync backup

---

## Testing Checklist for iOS

```
Auth:
  [ ] OAuth login works
  [ ] Deep link captured (ai.sage.app://auth/callback)
  [ ] Session persists on app resume
  
Database:
  [ ] Messages created and stored
  [ ] Sessions list populates
  [ ] Data survives app restart
  
Sync:
  [ ] Messages appear in cloud console
  [ ] Works offline (retry queue holds data)
  [ ] Resumes on network restore
  
UI:
  [ ] Mobile layout active
  [ ] No "MCP"/"Sandbox" settings shown
  [ ] Settings saved and reloaded
```

---

## For Developers

### Adding iOS-Specific Code

```typescript
import { isCapacitor } from '@/shared/lib/platform';

if (isCapacitor) {
  // iOS-specific logic
  const { App } = await import('@capacitor/app');
  App.addListener('pause', () => { /* save state */ });
}
```

### Checking Database Type

```typescript
const db = await getSQLiteDatabase();
if (db) {
  // Tauri path: use SQLite
} else {
  // iOS path: fallback to IndexedDB (already handles it internally)
}
```

### Handling File Operations

```typescript
import { isTauri } from '@/shared/lib/platform';

if (isTauri) {
  // Save to filesystem
  const { writeFile } = await import('@tauri-apps/plugin-fs');
  await writeFile(path, data);
} else {
  // iOS: Save to IndexedDB or offer download
  // Web: Offer file download
  const blob = new Blob([data]);
  const url = URL.createObjectURL(blob);
  // ... trigger download
}
```

---

## Common Issues & Solutions

### Issue: Settings not persisting on iOS
**Cause:** localStorage quota exceeded  
**Fix:** Implement quota monitoring, offer to clear old sessions

### Issue: Attachments fail to upload
**Cause:** IndexedDB quota exceeded  
**Fix:** Check `navigator.storage.estimate()`, reject large files

### Issue: OAuth deep link not working
**Cause:** User closed browser manually  
**Fix:** Fallback polling with timeout (already in code)

### Issue: Slow session view on iOS
**Cause:** Aggregating 100+ messages in single query  
**Fix:** Paginate/lazy-load messages

---

## Architecture Overview

```
iOS WebView
    ↓
JavaScript (React app)
    ↓
    ├─ Platform Detection
    │   └─ isCapacitor = true
    │
    ├─ Database Layer
    │   └─ IndexedDB (not SQLite)
    │
    ├─ Settings
    │   └─ localStorage (not SQLite)
    │
    ├─ Sync Queue
    │   └─ IndexedDB (for retry logic)
    │
    ├─ Capacitor Plugins
    │   ├─ @capacitor/app (lifecycle)
    │   ├─ @capacitor/browser (OAuth)
    │   └─ @capacitor/core (system APIs)
    │
    └─ Cloud Sync (Supabase)
        └─ fetch() API (standard)
```

---

## References

**Main Documentation:** `PLATFORM_ANALYSIS.md` (this directory)

**Key Files:**
- Platform detection: `src/shared/lib/platform.ts`
- Database: `src/shared/db/database.ts`
- Settings: `src/shared/db/settings.ts`
- Auth: `src/shared/providers/auth-provider.tsx`
- Sync: `src/shared/sync/*.ts`

**Build:**
- `package.json` → `"build:ios"` script
- `capacitor.config.ts` → app configuration
- `.env.ios` → build environment variables

