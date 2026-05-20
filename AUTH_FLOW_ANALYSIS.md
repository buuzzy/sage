# Sage Authentication Flow Analysis

**Date**: 2026-05-19  
**Project Root**: `/Users/nakocai/Documents/Projects/项目/Sage/sage/`  
**Goal**: Understand auth mechanisms for iOS (Capacitor) vs Desktop (Tauri), with a focus on Railway backend integration

---

## Executive Summary

**Current State**:
- **Tauri Desktop**: Uses localhost:2026 sidecar. Auth via IP-based loopback check (no secrets needed locally).
- **iOS / Railway**: Uses Supabase JWT access token passed in request body. The backend middleware validates `SAGE_API_TOKEN` if set (cloud mode).
- **Problem**: iOS cannot authenticate to Railway because:
  1. The frontend doesn't send the `Authorization: Bearer` header
  2. If it did, the token would need to be hardcoded in the app (insecure)

**Ideal Solution**:
Use Supabase JWT (which iOS already obtains after login) as the auth token for Railway, validated by the backend. This way:
- No hardcoded secrets in the frontend
- User authentication is tied to Supabase identity
- The backend uses the JWT to create a user-scoped Supabase client with RLS enforcement

---

## 1. Frontend Architecture

### 1.1 API Configuration (`src/config/index.ts`)

```typescript
const isTauri = typeof window !== 'undefined' && '__TAURI_INTERNALS__' in window;

export const API_BASE_URL = isTauri
  ? `http://127.0.0.1:${API_PORT}`  // Desktop: localhost sidecar
  : import.meta.env.VITE_API_URL ||  // iOS/Web: Railway (from .env.ios)
    `http://localhost:${API_PORT}`;
```

**Current Values**:
- **Desktop (Tauri)**: `http://127.0.0.1:2026`
- **iOS (.env.ios)**: `https://sage-production-28e1.up.railway.app`

---

### 1.2 Supabase Client & JWT (`src/shared/lib/supabase.ts`)

```typescript
export const supabase = createClient(SUPABASE_URL, SUPABASE_ANON_KEY, {
  auth: {
    persistSession: true,
    autoRefreshToken: true,
    detectSessionInUrl: !isTauri,     // iOS/Web auto-detect session
    flowType: isTauri ? 'pkce' : 'implicit',  // Different flows
  },
});

// Gets Supabase JWT (returns undefined if not logged in)
export async function getCurrentAccessToken(): Promise<string | undefined> {
  try {
    const { data, error } = await supabase.auth.getSession();
    if (error) return undefined;
    return data.session?.access_token ?? undefined;
  } catch {
    return undefined;
  }
}
```

**JWT Characteristics**:
- Issued by Supabase auth service
- Contains `sub` (user UUID), `aud: "authenticated"`, `iss: <supabase-url>`
- Automatically refreshed by Supabase client
- Valid for ~1 hour (configurable)

---

### 1.3 Frontend API Calls (`src/shared/hooks/useAgent.ts`)

**Line 1422**: Direct execution request
```typescript
const response = await fetchWithRetry(`${AGENT_SERVER_URL}/agent`, {
  method: 'POST',
  headers: { 'Content-Type': 'application/json' },
  body: JSON.stringify({
    prompt: executionPrompt,
    workDir,
    taskId: currentTaskId,
    // ... other fields ...
    userId: getCurrentBoundUid() ?? undefined,
    accessToken: await getCurrentAccessToken(),  // ← JWT from Supabase
  }),
  signal: abortController.signal,
});
```

**Lines 1545, 1809, 2087**: Similar pattern in planning, execution, and continue endpoints.

**Key Issue**: `accessToken` is sent in the **request body**, NOT in the `Authorization` header.

---

## 2. Backend Architecture

### 2.1 Server Setup & Middleware (`src-api/src/index.ts`)

```typescript
// Apply local-only middleware to execution-capable routes
app.use('/agent/*', localOnlyMiddleware);
app.use('/sandbox/*', localOnlyMiddleware);
app.use('/preview/*', localOnlyMiddleware);
app.use('/files/*', localOnlyMiddleware);
app.use('/mcp/*', localOnlyMiddleware);
app.use('/mcp-memory/*', localOnlyMiddleware);
app.use('/skills/*', localOnlyMiddleware);

app.use('/providers/*', localOnlyMiddleware);
app.use('/cron/*', localOnlyMiddleware);

// Note: /channels/* and /v1/chat/completions are NOT protected
// They use HTCLAW_CHANNEL_API_KEY authentication
```

---

### 2.2 Local-Only Middleware (`src-api/src/app/middleware/local-only.ts`)

**Two authentication modes**:

```typescript
const API_TOKEN = process.env.SAGE_API_TOKEN;

export async function localOnlyMiddleware(c: Context, next: Next): Promise<Response | void> {
  // MODE 1: Cloud mode (Railway/hosted)
  if (API_TOKEN) {
    const authHeader = c.req.header('authorization');
    const token = authHeader?.startsWith('Bearer ')
      ? authHeader.slice(7)
      : undefined;

    if (token !== API_TOKEN) {
      return c.json({ error: 'Unauthorized' }, 401);
    }
    await next();
    return;
  }

  // MODE 2: Local mode (Tauri desktop sidecar)
  let remoteAddr: string | undefined;
  try {
    const info = getConnInfo(c);
    remoteAddr = info.remote.address;
  } catch {
    remoteAddr = c.req.header('x-real-ip') || 
                 c.req.header('x-forwarded-for')?.split(',')[0]?.trim();
  }

  if (!isLoopback(remoteAddr)) {
    return c.json(
      { error: 'Forbidden: this endpoint is only accessible from localhost' },
      403
    );
  }

  await next();
}

// Loopback detection
function isLoopback(addr: string | undefined): boolean {
  if (!addr) return false;
  const clean = addr.replace(/^::ffff:/i, '').replace(/^\[|\]$/g, '').trim();
  return clean === '127.0.0.1' || clean === '::1' || 
         clean === 'localhost' || clean.startsWith('127.');
}
```

**Behavior**:
- **Desktop (127.0.0.1)**: IP check passes, no token needed
- **Railway (cloud IP)**: Requires `Authorization: Bearer ${SAGE_API_TOKEN}` header

---

### 2.3 Backend Agent Route (`src-api/src/app/api/agent.ts`)

```typescript
agent.post('/', async (c) => {
  const body = await c.req.json<AgentRequest>();

  const session = createSession();
  const readable = createSSEStream(
    runAgent(
      prompt,
      session,
      body.conversation,
      body.workDir,
      body.taskId,
      body.modelConfig,
      body.sandboxConfig,
      body.images,
      body.skillsConfig,
      body.mcpConfig,
      body.language,
      body.userId,
      body.accessToken  // ← Extracted from request body
    )
  );

  return new Response(readable, { headers: SSE_HEADERS });
});
```

**AgentRequest Type**:
```typescript
interface AgentRequest {
  prompt: string;
  conversation?: ConversationMessage[];
  workDir?: string;
  taskId?: string;
  modelConfig?: { apiKey?: string; baseUrl?: string; model?: string };
  sandboxConfig?: SandboxConfig;
  images?: ImageAttachment[];
  skillsConfig?: SkillsConfig;
  mcpConfig?: McpConfig;
  language?: string;
  userId?: string;
  accessToken?: string;  // Supabase JWT (currently optional & unused)
}
```

---

### 2.4 Agent Service (`src-api/src/shared/services/agent.ts`)

Passes `accessToken` through execution chain:

```typescript
// Planning phase
export async function* runPlanningPhase(
  prompt: string,
  session: AgentSession,
  modelConfig?: ModelConfig,
  language?: string,
  userId?: string,
  accessToken?: string
): AsyncGenerator<AgentMessage> {
  const agent = await getAgent(modelConfig);
  for await (const message of agent.plan(prompt, {
    sessionId: session.id,
    abortController: session.abortController,
    language,
    userId,
    accessToken,  // ← Forwarded to Claude SDK
  })) {
    yield message;
  }
}

// Execution & direct agent also follow same pattern
```

---

### 2.5 Supabase Client Factory (`src-api/src/shared/supabase/client.ts`)

**Two client types**:

```typescript
// Service-role client (Railway only)
export function getServiceSupabase(): SupabaseClient {
  const url = process.env.SUPABASE_URL;
  const key = process.env.SUPABASE_SERVICE_ROLE_KEY;  // From Railway env
  if (!url || !key) throw new Error('[supabase] keys missing');
  
  return createClient(url, key, {
    auth: { persistSession: false, autoRefreshToken: false },
  });
}

// User-scoped client (Desktop + iOS, respects RLS)
export function createUserScopedSupabase(accessToken: string): SupabaseClient {
  const url = process.env.SUPABASE_URL;
  const anonKey = process.env.SUPABASE_ANON_KEY;  // Public, safe to expose
  
  if (!accessToken) {
    throw new Error('[supabase] accessToken required');
  }

  // ← KEY POINT: JWT goes in Authorization header
  return createClient(url, anonKey, {
    auth: { persistSession: false, autoRefreshToken: false },
    global: {
      headers: {
        Authorization: `Bearer ${accessToken}`,  // Supabase validates JWT
      },
    },
  });
}
```

---

### 2.6 Internal SDK Integration (`src-api/src/extensions/agent/codeany/index.ts`)

When Claude SDK calls the `/mcp-memory` endpoint internally:

```typescript
// Lines 910-924
if (accessToken) {
  params.set('access_token', accessToken);  // Query param for Supabase
}
const url = `http://127.0.0.1:${port}/mcp-memory?${params.toString()}`;
const headers: Record<string, string> = {};
if (process.env.SAGE_API_TOKEN) {
  // Only needed if running on Railway
  headers.Authorization = `Bearer ${process.env.SAGE_API_TOKEN}`;
}

return {
  memory: {
    type: 'http',
    url,
    ...(Object.keys(headers).length > 0 ? { headers } : {}),
  },
};
```

---

## 3. Current Auth Flow by Platform

### 3.1 Tauri Desktop (Localhost Sidecar)

```
┌──────────────────────┐
│ Frontend (React)     │
│ + Supabase OAuth     │ ──► User logs in ──► JWT in localStorage
└──────┬───────────────┘
       │
       │ fetch("http://127.0.0.1:2026/agent", {
       │   body: { accessToken: <jwt> }
       │ })
       │
       ▼
┌──────────────────────────────────────────┐
│ localOnlyMiddleware                      │
│ if SAGE_API_TOKEN:                       │
│   ✗ Not set (desktop mode)              │
│ else:                                    │
│   Check remote IP == 127.0.0.1 ✓        │
└──────┬───────────────────────────────────┘
       │
       ▼
┌──────────────────────────────────────────┐
│ Backend (Hono)                           │
│ - Extracts accessToken from body        │
│ - agent.run(..., { accessToken, ... })  │
└──────┬───────────────────────────────────┘
       │
       ▼
┌──────────────────────────────────────────┐
│ createUserScopedSupabase(accessToken)    │
│ - Uses anon key + JWT                    │
│ - RLS enforced: auth.uid() = user_id    │
└──────────────────────────────────────────┘
```

**Result**: ✓ Works. Auth is implicit (IP-based) + JWT for RLS.

---

### 3.2 iOS on Railway (Capacitor + Cloud)

```
┌──────────────────────┐
│ Frontend (React)     │
│ + Supabase OAuth     │ ──► User logs in ──► JWT in localStorage
└──────┬───────────────┘
       │
       │ fetch("https://sage-production-28e1.up.railway.app/agent", {
       │   body: { accessToken: <jwt> }
       │   (NO Authorization header)
       │ })
       │
       ▼
┌──────────────────────────────────────────┐
│ localOnlyMiddleware (Railway)            │
│ if SAGE_API_TOKEN:                       │
│   ✓ Is set (cloud mode)                 │
│   authHeader = c.req.header('auth...')  │
│   if (!header):                          │
│     ✗ return 401 Unauthorized           │
└──────────────────────────────────────────┘
```

**Result**: ✗ Fails. Frontend doesn't send Authorization header.

---

## 4. Environment Files

### 4.1 iOS Build (`.env.ios`)

```env
VITE_API_URL=https://sage-production-28e1.up.railway.app
```

- Sets backend URL for iOS build
- No auth token present (can't expose in app)

### 4.2 Desktop Dev (`configs/env/.env.development`)

```env
VITE_SUPABASE_URL=https://wymqgwtagpsjuonsclye.supabase.co
VITE_SUPABASE_ANON_KEY=eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9...

# (VITE_API_URL not set, so uses localhost:2026)
```

### 4.3 Backend (Railway Console)

```env
SAGE_API_TOKEN=<hardcoded-secret-exposed-in-ios-app>
SUPABASE_URL=https://wymqgwtagpsjuonsclye.supabase.co
SUPABASE_ANON_KEY=<anon-key>
SUPABASE_SERVICE_ROLE_KEY=<service-role-key>  # Optional, for RPC
```

### 4.4 Desktop Sidecar (`~/.sage/.env`)

```env
SUPABASE_URL=https://wymqgwtagpsjuonsclye.supabase.co
SUPABASE_ANON_KEY=<anon-key>
# No SAGE_API_TOKEN (local mode)
# No SERVICE_ROLE_KEY (user-scoped mode)
```

---

## 5. File Reference Table

### Frontend

| Path | Purpose | Key Export/Function |
|------|---------|---------------------|
| `src/config/index.ts` | API base URL selection | `API_BASE_URL`, `API_PORT` |
| `src/shared/lib/supabase.ts` | Supabase client + JWT | `getCurrentAccessToken()`, `supabase` client |
| `src/shared/hooks/useAgent.ts` | Agent execution hook | Lines 1422, 1545, 1809, 2087: passes `accessToken` |

### Backend

| Path | Purpose | Key Function/Export |
|------|---------|---------------------|
| `src-api/src/index.ts` | Hono app setup | Middleware registration (lines 45-51) |
| `src-api/src/app/middleware/local-only.ts` | Auth middleware | `localOnlyMiddleware()`, `isLoopback()` |
| `src-api/src/app/api/agent.ts` | Agent routes | `agent.post('/')` handler |
| `src-api/src/shared/services/agent.ts` | Agent execution | `runAgent()`, `runPlanningPhase()`, `runExecutionPhase()` |
| `src-api/src/shared/supabase/client.ts` | Supabase clients | `getServiceSupabase()`, `createUserScopedSupabase()` |
| `src-api/src/extensions/agent/codeany/index.ts` | Claude SDK integration | Lines 910-924: internal auth setup |

---

## 6. Problem Analysis

### Why iOS Cannot Authenticate

1. **Missing Authorization Header**
   - Frontend sends `accessToken` in request body
   - Backend middleware expects `Authorization: Bearer <token>` header
   - Header is never sent, so middleware rejects with 401

2. **Token Cannot Be Hardcoded**
   - `SAGE_API_TOKEN` would need to be in `.env.ios`
   - This exposes the secret in the compiled iOS app binary
   - Security risk: Anyone can reverse-engineer and extract the token

3. **Design Mismatch**
   - Frontend has JWT (from Supabase)
   - Backend has no way to validate it
   - Frontend has no way to send backend's `SAGE_API_TOKEN`

---

## 7. Recommended Solution

### Proposed: JWT-Based Auth

**Idea**: Use Supabase JWT as the authentication mechanism for all platforms.

**Changes**:

**Backend** (`local-only.ts` middleware):
```typescript
export async function localOnlyMiddleware(c: Context, next: Next) {
  // Cloud mode: Accept JWT in Authorization header
  const authHeader = c.req.header('authorization');
  const token = authHeader?.startsWith('Bearer ') 
    ? authHeader.slice(7) 
    : undefined;

  if (token) {
    // Validate JWT and extract user ID
    try {
      const decoded = validateSupabaseJWT(token); // ← New function
      c.set('userId', decoded.sub);
      c.set('accessToken', token);
      await next();
      return;
    } catch {
      return c.json({ error: 'Invalid token' }, 401);
    }
  }

  // Local mode: IP check (desktop sidecar)
  const remoteAddr = getRemoteAddress(c);
  if (!isLoopback(remoteAddr)) {
    return c.json({ error: 'Forbidden' }, 403);
  }

  // Extract accessToken from body for desktop
  const body = await c.req.json();
  c.set('accessToken', body.accessToken);
  await next();
}

// Validate Supabase JWT
function validateSupabaseJWT(token: string) {
  const supabaseUrl = process.env.SUPABASE_URL;
  // Verify JWT signature matches Supabase instance
  // Extract and return decoded payload
}
```

**Frontend** (`useAgent.ts`):
```typescript
// Add Authorization header with JWT
const accessToken = await getCurrentAccessToken();
const response = await fetchWithRetry(`${AGENT_SERVER_URL}/agent`, {
  method: 'POST',
  headers: {
    'Content-Type': 'application/json',
    ...(accessToken && { 'Authorization': `Bearer ${accessToken}` }),
  },
  body: JSON.stringify({
    prompt,
    // ... other fields ...
    // Still pass accessToken in body for backward compat
    accessToken,
  }),
});
```

**Environment** (Railway):
```env
# Remove:
# SAGE_API_TOKEN=...

# Keep:
SUPABASE_URL=https://wymqgwtagpsjuonsclye.supabase.co
SUPABASE_ANON_KEY=...
SUPABASE_SERVICE_ROLE_KEY=...
```

---

## 8. Implementation Checklist

- [ ] **Backend JWT Validation**
  - [ ] Add JWT verification function using `jsonwebtoken` npm package
  - [ ] Validate JWT issuer == SUPABASE_URL
  - [ ] Extract user ID from `sub` claim
  - [ ] Handle JWT expiration & invalid signatures
  
- [ ] **Update Middleware**
  - [ ] Accept JWT in Authorization header
  - [ ] Set `userId` and `accessToken` in context
  - [ ] Fall back to IP check if no header (local mode)
  - [ ] Remove hardcoded `SAGE_API_TOKEN` check
  
- [ ] **Frontend Changes**
  - [ ] Add Authorization header when calling agent endpoints
  - [ ] Keep accessToken in body for backward compat (optional)
  - [ ] Test on iOS, desktop, and web
  
- [ ] **Environment Changes**
  - [ ] Remove `SAGE_API_TOKEN` from `.env.ios`
  - [ ] Remove `SAGE_API_TOKEN` from Railway console
  - [ ] Verify Supabase config is present on Railway
  
- [ ] **Testing**
  - [ ] iOS app can authenticate with Railway
  - [ ] Desktop app still works with IP-based auth
  - [ ] Expired JWT returns 401
  - [ ] Invalid JWT returns 401
  - [ ] User-scoped Supabase queries work
  - [ ] RLS policies are enforced

---

## Conclusion

The current architecture is **nearly complete but has a critical gap**: iOS and Railway don't agree on authentication method.

**Current**: Backend expects hardcoded token (insecure), frontend doesn't send it (incomplete).

**Solution**: Use Supabase JWT (already available in both desktop and iOS) as the universal auth token. Backend validates JWT instead of checking a hardcoded secret. This:
- ✓ Removes security risk of token exposure
- ✓ Ties auth to user identity (Supabase UUID)
- ✓ Works for all platforms (desktop, iOS, web)
- ✓ Enables user-scoped RLS enforcement
- ✓ Follows JWT best practices

