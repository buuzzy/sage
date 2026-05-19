import {
  ensureUserDirs,
  getUserDbConnString,
} from '@/shared/lib/user-scoped-paths';
import { enqueueUserBehavior } from '@/shared/sync/behavior-sync';
import {
  enqueueFileUpsert,
  enqueueMessageInsert,
  enqueueTaskUpsert,
} from '@/shared/sync/messages-sync';
import {
  markSessionDeleted,
  markSessionDirty,
} from '@/shared/sync/session-dirty-queue';
import { uuidv7 } from 'uuidv7';

import type {
  CreateFileInput,
  CreateMessageInput,
  CreateSessionInput,
  CreateTaskInput,
  LibraryFile,
  Message,
  Session,
  Task,
  UpdateTaskInput,
} from './types';

export interface BackupImportData {
  sessions?: unknown[];
  tasks?: unknown[];
  messages?: unknown[];
  files?: unknown[];
}

export interface BackupImportResult {
  sessions: number;
  tasks: number;
  messages: number;
  files: number;
}

// ─── User-scoped DB binding ──────────────────────────────────────────────────
//
// M1 —— 按账号隔离本地数据。
//
// 核心变化：
//   - 不再使用固定的 `sqlite:sage.db` 连接（那是 Rust 端 migrations 注册的路径，
//     位于 ~/Library/Application Support/ai.sage.desktop/sage.db）。
//   - 改为按 user.id 懒加载 `sqlite:~/.sage/users/{uid}/sage.db`。
//   - Rust 端 migrations 不会对这些动态路径生效，所以 schema 由 JS 端的
//     `ensureSchema()` 幂等建表负责。
//
// bind/unbind 时序：
//   - AuthProvider 在 getSession() resolve / SIGNED_IN / TOKEN_REFRESHED /
//     超时兜底解析 JWT 成功时调 `bindUserId(uid)`。
//   - AuthProvider 在 SIGNED_OUT / 显式登出 时调 `unbindUser()`。
//   - 切换用户（A 登出 → B 登录）：unbindUser 关闭旧连接，bindUserId 打开新连接。
//
// 并发保护：
//   - 使用 inFlight Promise 串行化 bind/unbind，避免两个 auth 事件同时触发
//     竞争关闭/打开。
//   - getSQLiteDatabase() 在未 bind 时返回 null（与浏览器模式行为一致）。

const IDB_NAME = 'sage';
// v3: Phase 1 - messages/files 主键从 autoIncrement 改为客户端生成的 UUID v7（跨设备唯一）
//     已与用户达成共识：内测期数据丢弃，DROP 旧 store 重建
// v4: Phase 1 - 新增 sync_queue store（本地→云端双写失败的重试队列）
const IDB_VERSION = 4;

// Check if running in Tauri environment synchronously
function isTauriSync(): boolean {
  if (typeof window === 'undefined') {
    return false;
  }

  // Check for Tauri v2 internals
  const hasTauriInternals = '__TAURI_INTERNALS__' in window;
  // Check for legacy Tauri v1
  const hasTauri = '__TAURI__' in window;

  return hasTauriInternals || hasTauri;
}

function asRecord(value: unknown): Record<string, unknown> | null {
  return value && typeof value === 'object'
    ? (value as Record<string, unknown>)
    : null;
}

function str(value: unknown, fallback = ''): string {
  return typeof value === 'string' && value.length > 0 ? value : fallback;
}

function nullableStr(value: unknown): string | null {
  return typeof value === 'string' ? value : null;
}

function nullableJsonString(value: unknown): string | null {
  if (value === null || value === undefined) return null;
  return typeof value === 'string' ? value : JSON.stringify(value);
}

// ============ IndexedDB for Browser Mode ============
let idb: IDBDatabase | null = null;

async function getIndexedDB(): Promise<IDBDatabase> {
  if (idb) return idb;

  return new Promise((resolve, reject) => {
    const request = indexedDB.open(IDB_NAME, IDB_VERSION);

    request.onerror = () => {
      console.error('[IDB] Failed to open database:', request.error);
      reject(request.error);
    };

    request.onsuccess = () => {
      idb = request.result;
      console.log('[IDB] Database opened successfully');
      resolve(idb);
    };

    request.onupgradeneeded = (event) => {
      const db = (event.target as IDBOpenDBRequest).result;
      const oldVersion = event.oldVersion;
      console.log(
        `[IDB] Upgrading database from v${oldVersion} to v${IDB_VERSION}...`
      );

      // sessions store (v2 起)
      if (!db.objectStoreNames.contains('sessions')) {
        const sessionsStore = db.createObjectStore('sessions', {
          keyPath: 'id',
        });
        sessionsStore.createIndex('created_at', 'created_at', {
          unique: false,
        });
      }

      // tasks store
      if (!db.objectStoreNames.contains('tasks')) {
        const tasksStore = db.createObjectStore('tasks', { keyPath: 'id' });
        tasksStore.createIndex('created_at', 'created_at', { unique: false });
        tasksStore.createIndex('session_id', 'session_id', { unique: false });
      }

      // messages store
      // v3 破坏性变更：autoIncrement INTEGER → UUID v7 字符串
      // 老 store 的数据不兼容新主键，直接删除重建
      if (oldVersion < 3 && db.objectStoreNames.contains('messages')) {
        db.deleteObjectStore('messages');
        console.log(
          '[IDB] v3 migration: dropped old messages store (autoIncrement)'
        );
      }
      if (!db.objectStoreNames.contains('messages')) {
        const messagesStore = db.createObjectStore('messages', {
          keyPath: 'id',
        });
        messagesStore.createIndex('task_id', 'task_id', { unique: false });
        messagesStore.createIndex('user_id', 'user_id', { unique: false });
        messagesStore.createIndex('updated_at', 'updated_at', {
          unique: false,
        });
      }

      // files store - 同 messages 处理
      if (oldVersion < 3 && db.objectStoreNames.contains('files')) {
        db.deleteObjectStore('files');
        console.log(
          '[IDB] v3 migration: dropped old files store (autoIncrement)'
        );
      }
      if (!db.objectStoreNames.contains('files')) {
        const filesStore = db.createObjectStore('files', {
          keyPath: 'id',
        });
        filesStore.createIndex('task_id', 'task_id', { unique: false });
        filesStore.createIndex('user_id', 'user_id', { unique: false });
        filesStore.createIndex('updated_at', 'updated_at', { unique: false });
      }

      // sync_queue store (v4)
      if (!db.objectStoreNames.contains('sync_queue')) {
        const syncQueueStore = db.createObjectStore('sync_queue', {
          keyPath: 'id',
        });
        syncQueueStore.createIndex('next_retry_at', 'next_retry_at', {
          unique: false,
        });
        syncQueueStore.createIndex('user_id', 'user_id', { unique: false });
      }

      console.log('[IDB] Database upgraded successfully');
    };
  });
}

// Helper to promisify IDB requests
function idbRequest<T>(request: IDBRequest<T>): Promise<T> {
  return new Promise((resolve, reject) => {
    request.onsuccess = () => resolve(request.result);
    request.onerror = () => reject(request.error);
  });
}

// ============ Tauri SQLite ============
type SqliteHandle = Awaited<
  ReturnType<typeof import('@tauri-apps/plugin-sql').default.load>
>;

let sqliteDb: SqliteHandle | null = null;
let currentUid: string | null = null;
let bindInFlight: Promise<void> | null = null;
// 监听器：供 settings 缓存失效 / UI 重新查询使用
const bindListeners = new Set<(uid: string | null) => void>();

/**
 * 订阅 user binding 变化。
 * 回调参数：新的 uid（null 表示已 unbind）。
 * 触发时机：bindUserId / unbindUser 成功完成之后。
 */
export function subscribeUserBinding(
  cb: (uid: string | null) => void
): () => void {
  bindListeners.add(cb);
  return () => {
    bindListeners.delete(cb);
  };
}

function notifyBindChange() {
  for (const cb of bindListeners) {
    try {
      cb(currentUid);
    } catch (err) {
      console.error('[DB] bind listener error:', err);
    }
  }
}

/**
 * 获取当前绑定的 user id（未绑定时为 null）。
 * 用于 useAgent 等需要推导用户作用域路径的地方。
 */
export function getCurrentBoundUid(): string | null {
  return currentUid;
}

/**
 * 幂等建表。把 src-tauri/src/lib.rs 中 7 条 migrations 平展成
 * `CREATE TABLE IF NOT EXISTS` + 缺列时的 `ALTER TABLE`。
 *
 * 这个函数每次 bind 都跑一次，成本小，保证空 DB 也能用。
 */
/**
 * 检测某张表的某个列是否为指定类型（PRAGMA table_info）。
 * 用于判断 messages.id / files.id 是否还是老的 INTEGER schema。
 */
async function columnHasType(
  db: SqliteHandle,
  table: string,
  column: string,
  expectedType: string
): Promise<boolean> {
  try {
    const rows = await db.select<{ name: string; type: string }[]>(
      `PRAGMA table_info(${table})`
    );
    const col = rows.find((r) => r.name === column);
    return col?.type.toUpperCase() === expectedType.toUpperCase();
  } catch {
    return false;
  }
}

async function ensureSchema(db: SqliteHandle): Promise<void> {
  // tasks（合并 v1 + v5 + v7：session_id / task_index / favorite）
  await db.execute(`
    CREATE TABLE IF NOT EXISTS tasks (
      id TEXT PRIMARY KEY NOT NULL,
      prompt TEXT NOT NULL,
      status TEXT NOT NULL DEFAULT 'running',
      cost REAL,
      duration INTEGER,
      provider_usage TEXT,
      session_id TEXT,
      task_index INTEGER DEFAULT 1,
      favorite INTEGER DEFAULT 0,
      created_at TEXT NOT NULL DEFAULT (datetime('now')),
      updated_at TEXT NOT NULL DEFAULT (datetime('now'))
    )
  `);

  // ─── Phase 1 破坏性升级：messages.id INTEGER → TEXT (UUID v7) ────────────
  // 检测老 schema 并 DROP；内测期数据丢弃（用户已确认）
  if (await columnHasType(db, 'messages', 'id', 'INTEGER')) {
    console.warn(
      '[DB] Phase 1 migration: dropping legacy messages table (autoincrement INTEGER → UUID v7)'
    );
    await db.execute('DROP TABLE IF EXISTS messages');
  }

  await db.execute(`
    CREATE TABLE IF NOT EXISTS messages (
      id TEXT PRIMARY KEY NOT NULL,
      user_id TEXT NOT NULL,
      task_id TEXT NOT NULL,
      type TEXT NOT NULL,
      content TEXT,
      tool_name TEXT,
      tool_input TEXT,
      tool_output TEXT,
      tool_use_id TEXT,
      tool_metadata TEXT,
      subtype TEXT,
      error_message TEXT,
      attachments TEXT,
      created_at TEXT NOT NULL DEFAULT (datetime('now')),
      updated_at TEXT NOT NULL DEFAULT (datetime('now')),
      FOREIGN KEY (task_id) REFERENCES tasks(id) ON DELETE CASCADE
    )
  `);

  // ─── Phase 1 破坏性升级：files.id INTEGER → TEXT (UUID v7) ────────────
  if (await columnHasType(db, 'files', 'id', 'INTEGER')) {
    console.warn(
      '[DB] Phase 1 migration: dropping legacy files table (autoincrement INTEGER → UUID v7)'
    );
    await db.execute('DROP TABLE IF EXISTS files');
  }

  await db.execute(`
    CREATE TABLE IF NOT EXISTS files (
      id TEXT PRIMARY KEY NOT NULL,
      user_id TEXT NOT NULL,
      task_id TEXT NOT NULL,
      name TEXT NOT NULL,
      type TEXT NOT NULL,
      path TEXT NOT NULL,
      preview TEXT,
      thumbnail TEXT,
      is_favorite INTEGER NOT NULL DEFAULT 0,
      created_at TEXT NOT NULL DEFAULT (datetime('now')),
      updated_at TEXT NOT NULL DEFAULT (datetime('now')),
      FOREIGN KEY (task_id) REFERENCES tasks(id) ON DELETE CASCADE
    )
  `);

  // settings（v4）
  await db.execute(`
    CREATE TABLE IF NOT EXISTS settings (
      key TEXT PRIMARY KEY NOT NULL,
      value TEXT NOT NULL,
      updated_at TEXT NOT NULL DEFAULT (datetime('now'))
    )
  `);

  // sessions（v5）
  await db.execute(`
    CREATE TABLE IF NOT EXISTS sessions (
      id TEXT PRIMARY KEY NOT NULL,
      prompt TEXT NOT NULL,
      task_count INTEGER NOT NULL DEFAULT 0,
      created_at TEXT NOT NULL DEFAULT (datetime('now')),
      updated_at TEXT NOT NULL DEFAULT (datetime('now'))
    )
  `);

  // sync_queue（Phase 1）：本地→云端双写失败时的重试队列
  // 表设计为通用，未来扩展 tasks/files 同步无需改 schema
  await db.execute(`
    CREATE TABLE IF NOT EXISTS sync_queue (
      id TEXT PRIMARY KEY NOT NULL,
      user_id TEXT NOT NULL,
      table_name TEXT NOT NULL,
      operation TEXT NOT NULL,
      payload TEXT NOT NULL,
      retry_count INTEGER NOT NULL DEFAULT 0,
      last_error TEXT,
      next_retry_at TEXT NOT NULL DEFAULT (datetime('now')),
      created_at TEXT NOT NULL DEFAULT (datetime('now'))
    )
  `);

  // Indexes
  await db.execute(
    `CREATE INDEX IF NOT EXISTS idx_messages_task_id ON messages(task_id)`
  );
  await db.execute(
    `CREATE INDEX IF NOT EXISTS idx_messages_user_updated ON messages(user_id, updated_at DESC)`
  );
  await db.execute(
    `CREATE INDEX IF NOT EXISTS idx_files_task_id ON files(task_id)`
  );
  await db.execute(
    `CREATE INDEX IF NOT EXISTS idx_files_user_updated ON files(user_id, updated_at DESC)`
  );
  await db.execute(
    `CREATE INDEX IF NOT EXISTS idx_tasks_session_id ON tasks(session_id)`
  );
  await db.execute(
    `CREATE INDEX IF NOT EXISTS idx_sync_queue_next_retry ON sync_queue(next_retry_at)`
  );

  // 迁移过来的旧 DB 可能缺列（仅 tasks 现在还需要 ALTER；messages/files 已 DROP 重建）
  const alters = [
    'ALTER TABLE tasks ADD COLUMN session_id TEXT',
    'ALTER TABLE tasks ADD COLUMN task_index INTEGER DEFAULT 1',
    'ALTER TABLE tasks ADD COLUMN favorite INTEGER DEFAULT 0',
    'ALTER TABLE tasks ADD COLUMN provider_usage TEXT',
  ];
  for (const sql of alters) {
    try {
      await db.execute(sql);
    } catch {
      /* column already exists */
    }
  }
}

/**
 * 绑定指定 uid 的 DB 连接。
 *
 * 幂等：若当前已绑定相同 uid，则 no-op。
 * 并发安全：同时多次调用会串行执行。
 *
 * 抛错时机：
 *   - uid 非法 UUID
 *   - Tauri fs/sql 插件不可用
 */
export async function bindUserId(uid: string): Promise<void> {
  // IDB 模式（iOS / 浏览器）也要 track 当前 uid，让 createMessage 等能注入 user_id
  if (!isTauriSync()) {
    currentUid = uid;
    notifyBindChange();
    return;
  }

  // 串行化：等待任何 in-flight bind/unbind 先完成
  if (bindInFlight) {
    await bindInFlight.catch(() => {});
  }

  if (sqliteDb && currentUid === uid) {
    return; // 已绑定到同一 uid
  }

  bindInFlight = (async () => {
    // 1. 关闭旧连接（若有）
    if (sqliteDb) {
      try {
        await sqliteDb.close();
      } catch (err) {
        console.warn('[DB] close old connection failed:', err);
      }
      sqliteDb = null;
    }

    // 2. 确保目录 + 解析新连接串
    await ensureUserDirs(uid);
    const connStr = await getUserDbConnString(uid);

    // 3. 一次性迁移 legacy 数据（仅第一次绑定触发；见 user-scope-migration.ts）
    //    在打开连接之前 copy DB 文件，避免 sqlx 持有旧文件的锁
    try {
      const { maybeMigrateLegacyData } =
        await import('@/shared/lib/user-scope-migration');
      await maybeMigrateLegacyData(uid);
    } catch (err) {
      // 迁移失败不应阻塞登录 —— 用户至少能使用空 DB
      console.error('[DB] legacy migration failed (continuing):', err);
    }

    // 4. 打开新连接 + 幂等建表
    const Database = (await import('@tauri-apps/plugin-sql')).default;
    const db = await Database.load(connStr);
    await ensureSchema(db);

    sqliteDb = db;
    currentUid = uid;
    console.log(
      `[DB] bound to user ${uid.slice(0, 8)}… at ${connStr.replace(/^sqlite:/, '')}`
    );
  })();

  try {
    await bindInFlight;
  } finally {
    bindInFlight = null;
  }

  notifyBindChange();
}

/**
 * 解除 user 绑定。关闭当前连接，后续 `getSQLiteDatabase()` 返回 null。
 * 用于登出流程。
 */
export async function unbindUser(): Promise<void> {
  if (!isTauriSync()) {
    currentUid = null;
    notifyBindChange();
    return;
  }

  if (bindInFlight) {
    await bindInFlight.catch(() => {});
  }

  bindInFlight = (async () => {
    if (sqliteDb) {
      try {
        await sqliteDb.close();
      } catch (err) {
        console.warn('[DB] close on unbind failed:', err);
      }
      sqliteDb = null;
    }
    currentUid = null;
  })();

  try {
    await bindInFlight;
  } finally {
    bindInFlight = null;
  }

  notifyBindChange();
}

export async function getSQLiteDatabase() {
  if (!isTauriSync()) {
    return null;
  }

  // 等待任何 in-flight bind/unbind 先完成
  if (bindInFlight) {
    try {
      await bindInFlight;
    } catch {
      /* 失败不在这里抛，返回 null 让调用方走浏览器/空数据路径 */
    }
  }

  // 未绑定 user → 返回 null（调用方已有 null-handling）
  if (!currentUid || !sqliteDb) {
    return null;
  }

  return sqliteDb;
}

// ============ Session Operations ============
