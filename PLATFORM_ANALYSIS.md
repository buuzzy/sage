# Sage Platform Architecture Analysis
## iOS (Capacitor) vs Desktop (Tauri) vs Web

**Last Updated:** 2026-05-19  
**Scope:** Platform-specific code paths, fallback behaviors, and potential iOS issues

---

## 1. Platform Detection (`src/shared/lib/platform.ts`)

### Detection Flags

| Platform | Flag | Detection Method | Priority |
|----------|------|------------------|----------|
| **Tauri** | `isTauri` | `'__TAURI_INTERNALS__' in window` (v2) or `'__TAURI__' in window` (v1) | Checked first |
| **Capacitor (iOS)** | `isCapacitor` | `window.Capacitor?.isNativePlatform?.()` or `/iPhone\|iPad\|iPod/` UA fallback | Checked second |
| **Web** | `isWeb` | `!isTauri && !isCapacitor` | Default fallback |
| **Mobile** | `isMobile` | `isCapacitor` (always) OR `window.innerWidth < 768` | Width-based heuristic for web |
| **Desktop** | `isDesktop` | `isTauri` OR (not Capacitor AND not mobile) | |

### Code Path
```typescript
// isTauri checked first → most specific
// isCapacitor checked second → iOS/Android
// isWeb default → fallback
// isMobile: Capacitor always counts as mobile (even if iPad width > 768)
```

**⚠️ iOS Consideration:** iPad detection may trigger desktop UI if width > 768, but `isCapacitor` should prevent that. Web Safari on iPad (non-Capacitor) will render mobile UI only if < 768px.

---

## 2. Database Layer (`src/shared/db/database.ts`)

### Architecture: User-Scoped SQLite + IndexedDB Dual Backend

```
┌─────────────────────┬─────────────────────┐
│   Tauri Desktop     │   iOS/Web Browser   │
├─────────────────────┼─────────────────────┤
│ SQLite (per user)   │  IndexedDB Browser  │
│ ~/.sage/users/      │  (in-page storage)  │
│ {uid}/sage.db       │                     │
└─────────────────────┴─────────────────────┘
```

### SQLite (Tauri Only)

**Location:** `~/.sage/users/{uid}/sage.db`  
**Plugin:** `@tauri-apps/plugin-sql` v2.4.0

**Key Points:**
- ✅ Per-user database via `bindUserId(uid)` call
- ✅ User binding is **serialized** (in-flight Promise lock) → safe concurrent access
- ✅ Schema: `tasks`, `messages`, `files`, `sessions`, `settings`, `sync_queue`
- ✅ Idempotent schema init via `ensureSchema()` (runs on every bind)
- ⚠️ **Phase 1 Breaking Change:** `messages.id` and `files.id` migrated from `INTEGER` autoincrement → `TEXT` (UUID v7)
  - Old records are **DROP TABLE** → data loss on first run
  - Users pre-agreed to this in beta

**User Binding Flow:**
```
AuthProvider.useEffect()
  ↓
supabase.auth.getSession() resolves
  ↓
bindUserId(uid) called
  ↓
1. Close old connection (if any)
2. ensureUserDirs(uid) → create ~/.sage/users/{uid}/sessions
3. getUserDbConnString(uid) → "sqlite:/Users/.../sage.db"
4. Database.load(connStr)
5. ensureSchema() → idempotent CREATE TABLE IF NOT EXISTS
6. Legacy migration (if first bind ever)
  ↓
currentUid set, dbReady = true
notifyBindChange() → observers refresh cache
```

### IndexedDB (iOS / Web / Browser Fallback)

**Database:** `sage` (IDB_VERSION = 4)

**Schema:**
- `sessions` (keyPath: `id`)
- `tasks` (keyPath: `id`, indices: `created_at`, `session_id`)
- `messages` (keyPath: `id`, indices: `task_id`, `user_id`, `updated_at`)
- `files` (keyPath: `id`, indices: `task_id`, `user_id`, `updated_at`)
- `sync_queue` (keyPath: `id`, indices: `next_retry_at`, `user_id`)

**Version History:**
- v3: Dropped old `messages`/`files` (autoincrement → UUID v7)
- v4: Added `sync_queue` store for cloud sync retries

**⚠️ iOS (IndexedDB in WebView):**
- ✅ Works: Basic CRUD, indexes, transactions
- ⚠️ **Limit:** ~50MB per app on iOS Safari (may vary by iOS version)
- ⚠️ **Persistence:** Clears if app data is cleared OR iOS cache pressure
- ⚠️ **Performance:** No warm cache on cold app start (must re-query cloud)

### Code Path in Message Creation (`src/shared/db/messages.ts`)

```typescript
async function createMessage(input: CreateMessageInput) {
  // 1. Generate UUID v7 client-side
  const id = uuidv7();
  
  // 2. Require currentUid to be set (set by bindUserId)
  const userId = currentUid;
  if (!userId) throw Error("AuthProvider must bindUserId first");
  
  // 3. Get the appropriate database
  const database = await getSQLiteDatabase();
  
  if (database) {
    // ✅ Tauri path: INSERT into SQLite
    await database.execute("INSERT INTO messages (...) VALUES (...)", [...]);
  } else {
    // ✅ iOS/Web path: INSERT into IndexedDB
    const db = await getIndexedDB();
    const tx = db.transaction('messages', 'readwrite');
    const store = tx.objectStore('messages');
    await idbRequest(store.add(message));
  }
  
  // 4. Queue for cloud sync (fire-and-forget)
  enqueueMessageInsert(message);
}
```

**What Works:**
- ✅ Tauri: Full SQLite semantics, schema migrations
- ✅ iOS: IndexedDB fallback, basic CRUD
- ✅ Web: IndexedDB fallback, same as iOS

**What Might Break on iOS:**
- ❌ If IndexedDB storage quota exceeded → errors on insert
- ❌ If IndexedDB cleared (user clears app data) → empty database
- ❌ No automatic retry if transaction fails (caller must handle)

---

## 3. Settings Storage (`src/shared/db/settings.ts`)

### Storage Priority

```
Tauri:
  1. SQLite (user-scoped settings table)
  2. Fallback: localStorage
  
iOS/Web:
  1. localStorage (direct)
  2. SQLite if database available (shouldn't be on iOS)
```

### Settings CRUD

**Load Flow:**
```typescript
async getSettingsAsync(): Settings {
  // 1. Check cache
  if (settingsCache) return settingsCache;
  
  // 2. Try database (Tauri only)
  const database = await getDatabase();
  if (database) {
    const result = await database.select("SELECT key, value FROM settings");
    // Parse JSON values, merge with defaults
  }
  
  // 3. Fallback to localStorage (all platforms)
  const stored = localStorage.getItem('sage_settings');
  if (stored) { /* parse and merge */ }
  
  // 4. Use defaultSettings
  return defaultSettings;
}
```

**Save Flow:**
```typescript
async saveSettingsAsync(settings: Settings): Promise<void> {
  // 1. Cache in memory
  settingsCache = settings;
  
  // 2. Try database (Tauri)
  if (database) {
    for (const key of Object.keys(settings)) {
      await database.execute(
        "INSERT OR REPLACE INTO settings (key, value) VALUES ($1, $2)",
        [key, JSON.stringify(settings[key])]
      );
    }
  }
  
  // 3. Save to localStorage (all platforms) as fallback
  localStorage.setItem('sage_settings', JSON.stringify(settings));
}
```

**Settings Cleared on User Bind:**
```typescript
subscribeUserBinding(() => {
  settingsCache = null; // Force reload from DB on next call
});
```

### What Works on iOS:
- ✅ localStorage persists settings
- ✅ Settings sync triggered on app startup
- ✅ User-specific settings isolated via `currentUid` tracking

### Potential Issues:
- ⚠️ **localStorage Quota (5-50MB):** If user has many providers/settings, could exceed quota
- ⚠️ **Settings Override on Login:** When switching users, `settingsCache` cleared but old localStorage may still exist
  - Mitigation: `normalizeSettingsProviders()` called on load merges defaults
- ❌ **MCP/Skills Paths:** Resolved on desktop to system paths; iOS has no filesystem access
  - On iOS, these settings are saved but **not used** (no sandbox/MCP support)

---

## 4. Cloud Sync Layer (`src/shared/sync/`)

### Architecture: Fire-and-Forget → Retry Queue

```
Local Write Success
  ↓
enqueueMessageInsert() [fire-and-forget]
  ↓
sync_queue INSERT (SQLite or IndexedDB)
  ↓
Worker loop (5s tick interval)
  ↓
drainBatch(size=10)
  ↓
supabase.from('messages').upsert()
  ↓
markDone() or markFailed(retry_count++)
  ↓
Exponential backoff: 5s → 15s → 45s → 2m → 5m → 30m
```

### Messages Sync (`src/shared/sync/messages-sync.ts`)

**Supported Operations:**
- `messages × insert` → `supabase.from('messages').upsert()`
- `tasks × upsert` → `supabase.from('tasks').upsert()`
- `files × upsert` → `supabase.from('files').upsert()`
- `user_behavior × insert` → `supabase.from('user_behavior').insert()`

**Worker Loop:**
- Tick: Every 5 seconds
- Batch: Up to 10 items per tick
- Concurrency: Single worker (prevents duplicate inserts)
- Retry: Mark failed with exponential backoff

**What Works on iOS:**
- ✅ IndexedDB `sync_queue` persists retry state
- ✅ Worker loop starts on `startMessageSyncWorker()` (called from AuthProvider)
- ✅ Worker stops on logout via `stopMessageSyncWorker()`
- ✅ Supabase fetch works via browser `fetch()` API

### Session Sync (`src/shared/sync/session-sync.ts`)

**Cloud Payload (per session):**
```typescript
{
  id: string,
  title: string | null,           // session.prompt (first 80 chars)
  preview: string | null,         // last user message (first 120 chars)
  message_count: number,          // total user + text messages
  has_artifacts: boolean,         // any files in session?
  updated_at: string
}
```

**What Works:**
- ✅ Builds payload from local SQLite/IndexedDB on demand
- ✅ Upserts to `public.sessions` table
- ✅ Supports session deletion sync

**Potential Issue on iOS:**
- ⚠️ **Aggregation Query:** `buildCloudPayload()` loops through all tasks/messages/files
  - On large sessions (100+ messages), this may cause jank on iOS (single thread)
  - No pagination/lazy loading optimization

### Sync Queue (`src/shared/sync/sync-queue.ts`)

**Dual Backend:**
```typescript
if (isTauriSync()) {
  // SQLite backend: INSERT INTO sync_queue (...)
} else {
  // IndexedDB backend: sync_queue.add(row)
}
```

**Retry Policy:**
```
retryCount → delayMs
0          → 5s
1          → 15s
2          → 45s
3          → 2m
4          → 5m
5+         → 30m
```

**What Works on iOS:**
- ✅ IndexedDB `sync_queue` store
- ✅ Retry logic per platform
- ✅ User filtering: only drain `sync_queue` where `user_id = currentUid`

**Potential Issues:**
- ⚠️ **IndexedDB Size Limit:** If many retries queue up (network downtime), storage quota may exceed
- ⚠️ **30min Backoff:** Last retry at 30min means offline data may take 30+ min to sync when reconnected
  - Mitigation: Manual trigger on app resume (not implemented?)

---

## 5. File Handling (`src/shared/lib/attachments.ts` & `user-scoped-paths.ts`)

### Attachment Storage Path

**Tauri:**
```
~/.sage/users/{uid}/sessions/{sessionId}/attachments/{filename}
```

**iOS/Web:**
```
No filesystem access → Attachments stored in IndexedDB or memory
```

### Code Path (`attachments.ts`)

```typescript
function isTauri(): boolean {
  return '__TAURI_INTERNALS__' in window || '__TAURI__' in window;
}

// For Tauri: use filesystem operations via @tauri-apps/plugin-fs
// For iOS/Web: use Blob/FileReader APIs (IndexedDB can't store binary directly)
```

**Attachment Upload/Storage:**
```
Browser/iOS:
  1. User selects file
  2. Read as base64 via FileReader
  3. Store base64 string in IndexedDB (message.attachments JSON)
  4. On sync, send base64 to cloud

Tauri:
  1. User selects file
  2. Copy to ~/.sage/users/{uid}/sessions/{sessionId}/attachments/
  3. Store filename reference in SQLite
  4. On sync, send filename + metadata to cloud
```

**What Works on iOS:**
- ✅ Base64 attachment storage in IndexedDB
- ✅ Small attachments (< 100MB) fit in IDB
- ✅ Sync to cloud stores attachment metadata

**Potential Issues on iOS:**
- ⚠️ **IndexedDB Size Limit:** Large attachments (>10MB each) quickly consume quota
- ⚠️ **No File Preview:** Cannot preview files directly from filesystem
- ⚠️ **Memory Bloat:** Base64 encoding inflates size by ~33%
- ❌ **Cloud Fallback:** If iOS app clears data, attachments are lost
  - Mitigation: Rely on cloud sync for restore

### User-Scoped Paths (`user-scoped-paths.ts`)

**Directory Structure:**
```
~/.sage/users/{uid}/
  ├── sage.db                          # SQLite database
  └── sessions/
      ├── {sessionId}/attachments/
      │   └── {filename}
      └── {sessionId2}/...
```

**Validation:**
- UUID pattern required: `/^[0-9a-f]{8}-[0-9a-f]{4}-...$/i`
- Prevents path injection attacks

**Tauri Path Resolution:**
```typescript
async getUserDbConnString(uid: string): Promise<string> {
  const abs = await getUserDbAbsolutePath(uid);
  return `sqlite:${abs}`; // e.g., "sqlite:/Users/foo/.sage/users/abc.../sage.db"
}
```

**iOS/Web Path Resolution:**
```typescript
// On non-Tauri, returns placeholder paths like "~/.sage/users/{uid}/..."
// These paths are never actually used in IndexedDB mode
```

**What Works on iOS:**
- ✅ Paths are tracked but not used
- ✅ No filesystem errors on iOS

**What Might Break:**
- ❌ Desktop app trying to use iOS attachment paths → file not found
- ❌ Manual DB export/import on iOS → cannot resolve real paths

---

## 6. Capacitor Plugins (`package.json` + `ios/App/CapApp-SPM/Package.swift`)

### Installed Plugins

| Plugin | Version | Purpose |
|--------|---------|---------|
| `@capacitor/app` | 8.1.0 | Lifecycle events, deep links |
| `@capacitor/browser` | 8.0.3 | OAuth: ASWebAuthenticationSession |
| `@capacitor/cli` | 8.3.1 | Build tooling |
| `@capacitor/core` | 8.3.1 | Core APIs |
| `@capacitor/ios` | 8.3.1 | iOS native runtime |

### SPM Dependencies (`Package.swift`)

```swift
.package(url: "https://github.com/ionic-team/capacitor-swift-pm.git", exact: "8.3.1")
.package(name: "CapacitorApp", path: ".../node_modules/@capacitor/app")
.package(name: "CapacitorBrowser", path: ".../node_modules/@capacitor/browser")
```

**What's Included:**
- ✅ App lifecycle (pause/resume)
- ✅ Deep links (`ai.sage.app://auth/callback`)
- ✅ OAuth browser support (ASWebAuthenticationSession)

**What's NOT Included:**
- ❌ File system access (`@capacitor/filesystem`)
- ❌ SQLite (`@capacitor/sqlite`)
- ❌ HTTP/Network APIs
- ❌ Camera/Photos

### OAuth Flow on iOS (Capacitor)

**Auth Provider Flow:**
```typescript
if (isCapacitor) {
  // 1. Get OAuth URL with redirectTo = "ai.sage.app://auth/callback"
  const { data, error } = await supabase.auth.signInWithOAuth({
    provider,
    options: {
      redirectTo: 'ai.sage.app://auth/callback',
      skipBrowserRedirect: true,
    },
  });
  
  // 2. Open system browser (ASWebAuthenticationSession)
  const { Browser } = await import('@capacitor/browser');
  await Browser.open({ url: data.url, windowName: '_self' });
  
  // 3. OAuth completes, deep link fired
  App.addListener('appUrlOpen', async ({ url }) => {
    // Extract code from "ai.sage.app://auth/callback?code=..."
    const code = new URLSearchParams(url).get('code');
    
    // 4. Exchange code for session
    const { data, error } = await supabase.auth.exchangeCodeForSession(code);
    
    // 5. Trigger auth state change
    await supabase.auth.setSession(data.session);
  });
}
```

**What Works:**
- ✅ OAuth redirect via custom URL scheme
- ✅ Deep link listener captures callback
- ✅ Token exchange completes auth

**Potential Issues:**
- ⚠️ **Deep Link Not Fired:** If user manually closes browser, deep link listener never fires
  - Mitigation: Fallback to polling `supabase.auth.getSession()` after delay
- ⚠️ **Session Cache:** After OAuth, session cached in localStorage
  - On app resume, `getSession()` should detect cached session

---

## 7. Build Configuration (Vite + iOS)

### `vite.config.ts`

```typescript
export default defineConfig(async () => ({
  plugins: [react(), tailwindcss()],
  define: {
    __BUILD_DATE__: JSON.stringify(buildDate),
    __APP_VERSION__: JSON.stringify(pkg.version),
  },
  resolve: {
    alias: {
      "@": path.resolve(__dirname, "./src"),
    },
  },
  // No platform-specific build modes detected
}));
```

**Key Points:**
- ✅ No special iOS build mode → same output for web/iOS
- ✅ Vite Rollup chunks vendor libraries → smaller main bundle
- ⚠️ No `.env.ios` auto-loading in vite.config
  - Must be loaded by Capacitor or npm build script

### iOS Build Scripts (`package.json`)

```json
"build:ios": "vite build --mode ios && npx cap sync ios",
"open:ios": "npx cap open ios"
```

**Flow:**
1. `vite build --mode ios` → build dist (mode is not used in vite.config, so just standard build)
2. `npx cap sync ios` → copy dist to `ios/App/www`
3. `npx cap open ios` → opens Xcode

**Environment Variable Handling:**
```
.env.ios is present but vite.config.ts doesn't reference it
→ Vite uses .env first, then .env.local
→ .env.ios is for manual/shell usage only
```

**⚠️ Issue:** `.env.ios` sets `VITE_API_URL=https://sage-production-28e1.up.railway.app` but Vite config doesn't switch modes, so build might use default `.env` values.

---

## 8. Platform-Specific Code Paths Summary

### Tauri (Desktop)

| Component | Implementation |
|-----------|-----------------|
| **Database** | SQLite (per user) |
| **Settings** | SQLite + localStorage fallback |
| **Attachments** | Filesystem + path references |
| **Sync** | SQLite sync_queue |
| **Auth** | Deep link (system browser) |
| **File System** | Full access via Tauri plugins |
| **Performance** | Native speed |

### iOS (Capacitor)

| Component | Implementation |
|-----------|-----------------|
| **Database** | IndexedDB only |
| **Settings** | localStorage only |
| **Attachments** | Base64 in IndexedDB |
| **Sync** | IndexedDB sync_queue |
| **Auth** | ASWebAuthenticationSession |
| **File System** | No direct access (IndexedDB only) |
| **Performance** | WebView (slower than Tauri) |

### Web Browser

| Component | Implementation |
|-----------|-----------------|
| **Database** | IndexedDB only |
| **Settings** | localStorage only |
| **Attachments** | Base64 in IndexedDB |
| **Sync** | IndexedDB sync_queue |
| **Auth** | In-page redirect |
| **File System** | File input/download only |
| **Performance** | Browser-dependent |

---

## 9. Known Issues & Gaps

### Critical for iOS

| Issue | Severity | Impact | Mitigation |
|-------|----------|--------|-----------|
| **No Filesystem Access** | High | Can't save/load user files directly | Use IndexedDB + cloud sync |
| **IndexedDB Quota Limit** | Medium | Large sessions may fail storage | Implement quota monitoring |
| **Data Loss on Clear App Data** | High | User loses all local data | Force cloud sync on resume |
| **No Sandbox/MCP Support** | Medium | Advanced features unavailable | Skip on iOS |

### Medium Priority

| Issue | Severity | Impact | Mitigation |
|-------|----------|--------|-----------|
| **Session Aggregation Jank** | Low | Large sessions slow UI on iOS | Paginate/lazy-load messages |
| **30-min Sync Backoff** | Low | Stale data when offline long | Manual sync trigger on resume |
| **Deep Link Timeout** | Low | OAuth hangs if browser closed | Polling fallback + timeout |
| **Settings Path Resolution** | Low | Desktop paths in iOS settings | Graceful skip on non-desktop |

### Web-Only Issues

| Issue | Severity | Impact | Mitigation |
|-------|----------|--------|-----------|
| **OAuth Redirect Loss** | Medium | Page reload clears context | Session persistence via localStorage |
| **No Deep Link Support** | N/A | Not applicable | Web default behavior |

---

## 10. What Works on iOS: Feature Matrix

### ✅ Fully Working

- [x] Authentication (OAuth via Capacitor Browser)
- [x] Message creation & local storage (IndexedDB)
- [x] Task CRUD
- [x] Session management
- [x] Cloud sync (messages, tasks, files)
- [x] Settings storage (localStorage)
- [x] User binding & database switching
- [x] Sync queue retry logic
- [x] Mobile UI (responsive design)

### ⚠️ Partially Working

- [ ] Attachment handling (limited by IndexedDB size)
- [ ] File preview (no filesystem, base64 only)
- [ ] Settings with complex paths (MCP, skills ignored)
- [ ] Large dataset handling (may exceed IndexedDB quota)
- [ ] Offline mode (depends on IndexedDB persistence)

### ❌ Not Available on iOS

- [ ] Local file system access
- [ ] Sandbox execution
- [ ] MCP server mounting
- [ ] Custom skills loading
- [ ] Direct database exports

---

## 11. Recommendations

### Immediate Actions

1. **Implement IndexedDB Quota Monitoring**
   - Add utility to check quota before insert
   - Alert user if >80% usage
   - Implement cleanup strategy (e.g., delete old sessions)

2. **Add iOS-Specific Documentation**
   - Document limitations (no filesystem, MCP disabled)
   - Warn about IndexedDB clearing
   - Recommend cloud backup

3. **Fix Vite .env.ios Loading**
   ```typescript
   // In vite.config.ts
   const isDev = process.env.NODE_ENV === 'development';
   const iosMode = process.argv.includes('--mode ios');
   
   // Load .env.ios if --mode ios passed
   if (iosMode) {
     // Load .env.ios variables
   }
   ```

4. **Add Sync Resume Handler**
   - On app resume (pause/resume listener), trigger manual sync
   - Clear any stale retry timers

### Medium-Term Improvements

5. **Pagination for Large Sessions**
   - Load messages in chunks (50 per page)
   - Lazy-load files
   - Prevents jank on session view

6. **Quota-Aware Attachment Handling**
   - Reject uploads if would exceed quota
   - Compress images before storage
   - Offer cloud-only storage option

7. **Better Offline Support**
   - Detect network changes via Capacitor Network plugin
   - Indicate sync status in UI
   - Allow manual "retry sync" button

8. **Platform Feature Flags**
   - Add settings to disable MCP/skills on iOS
   - Prevent invalid paths from being saved
   - Graceful degradation in UI

### Long-Term Architecture

9. **SQLite on iOS?**
   - Evaluate `@capacitor/sqlite` for better performance
   - Trade-off: Added native dependency vs. IndexedDB simplicity
   - Recommendation: Keep IndexedDB for now (simpler, works)

10. **Streaming File Upload**
    - Support multipart uploads for large files
    - Show progress to user
    - Retry individual chunks on failure

---

## Summary Matrix

```
Feature                 Tauri   iOS     Web     Notes
─────────────────────────────────────────────────────────
Local DB                ✅ SQL  ⚠️ IDB  ⚠️ IDB  Tauri best
Settings Sync           ✅      ✅      ✅      All work
Message Sync            ✅      ✅      ✅      Fire-and-forget queue
Cloud Restore           ✅      ✅      ✅      Via Supabase
Auth (OAuth)            ✅      ✅      ✅      Different mechanisms
Attachments             ✅      ⚠️      ⚠️      Size limits on mobile
Filesystem              ✅      ❌      ⚠️      Desktop only
Sandbox/MCP             ✅      ❌      ❌      Desktop only
Session Aggregation     ✅      ⚠️      ⚠️      May jank on large data
Offline Sync Retry      ✅      ✅      ✅      Works but slow
─────────────────────────────────────────────────────────
Overall                 ✅ Full ⚠️ Core ⚠️ Core Core features work
```

---

## File Reference Map

| File | Purpose | Platform-Specific |
|------|---------|------------------|
| `src/shared/lib/platform.ts` | Platform detection flags | All |
| `src/shared/db/database.ts` | DB layer (SQLite/IndexedDB) | All |
| `src/shared/db/settings.ts` | Settings CRUD | All |
| `src/shared/db/messages.ts` | Message operations | All |
| `src/shared/sync/sync-queue.ts` | Retry queue | All |
| `src/shared/sync/messages-sync.ts` | Cloud sync worker | All |
| `src/shared/sync/session-sync.ts` | Session metadata sync | All |
| `src/shared/lib/attachments.ts` | Attachment handling | All |
| `src/shared/lib/user-scoped-paths.ts` | Path resolution | Tauri-only |
| `src/shared/providers/auth-provider.tsx` | Auth flow | All (different paths) |
| `capacitor.config.ts` | Capacitor app config | iOS |
| `ios/App/CapApp-SPM/Package.swift` | iOS dependencies | iOS |
| `vite.config.ts` | Build config | All |
| `package.json` | Dependencies | All |
| `.env.ios` | iOS build vars | iOS |

