# Sage Backend API Contract for iOS Swift Client

**Base URL:** `https://sage-production-28e1.up.railway.app`  
**Last Updated:** 2026-05-20

## Authentication

### Header Requirements
All requests to `/agent` endpoints require:

```
Authorization: Bearer <TOKEN>
```

### Token Types (Cloud Mode - Railway)

1. **Server-to-Server (Priority 1)**
   - Use: `SAGE_API_TOKEN` environment variable value
   - Header: `Authorization: Bearer <SAGE_API_TOKEN>`
   - Use case: Internal server calls

2. **User Authentication (Priority 2 - for iOS clients)**
   - Use: Supabase JWT token from user login
   - Header: `Authorization: Bearer <SUPABASE_USER_JWT>`
   - Use case: iOS/Web client requests
   - The middleware validates the JWT with Supabase and allows the request if valid

### Middleware Details
- File: `src-api/src/app/middleware/local-only.ts`
- Applied to: `/agent`, `/sandbox`, `/preview`, `/files`, `/mcp`, `/skills`
- NOT applied to: `/v1`, `/channels/*` (external webhook routes)

---

## API Endpoints

### 1. POST /agent/chat
**Lightweight chat endpoint** — bypasses Agent SDK for simple queries with conversation history.

#### Request
```typescript
{
  prompt: string;                           // Required: User message
  conversation?: Array<{
    role: 'user' | 'assistant';
    content: string;
  }>;                                       // Optional: Conversation history
  language?: string;                        // Optional: Preferred response language (e.g., 'en-US', 'zh-CN')
  modelConfig?: {
    apiKey?: string;                        // Custom API key (overrides env)
    baseUrl?: string;                       // Custom API endpoint URL
    model?: string;                         // Model name (e.g., 'claude-3-5-sonnet')
    apiType?: 'anthropic-messages' | 'openai-completions';  // API format
  };
}
```

#### Response
- **Content-Type:** `text/event-stream` (Server-Sent Events)
- **Headers:**
  ```
  Content-Type: text/event-stream
  Cache-Control: no-cache, no-transform
  Connection: keep-alive
  X-Accel-Buffering: no
  ```

#### SSE Event Types (streamed as `data: {...}\n\n`)
```typescript
// Text response
{ type: 'text', content: string }

// Artifact block (auto-rendered components like charts, tables)
{ type: 'text', content: '```artifact:TYPE\n{...data...}\n```' }

// Final summary
{ type: 'done' }

// Error
{ type: 'error', message: string }
```

#### Example Flow
```
Client Request:
POST /agent/chat
Authorization: Bearer <SUPABASE_JWT>
Content-Type: application/json

{
  "prompt": "What is the weather today?",
  "conversation": [
    { "role": "user", "content": "Hi" },
    { "role": "assistant", "content": "Hello! How can I help?" }
  ],
  "language": "en-US"
}

Server SSE Stream:
data: {"type":"text","content":"I'm not connected to real-time weather data..."}

data: {"type":"done"}
```

---

### 2. POST /agent/plan
**Planning Phase** — Creates an execution plan without executing it.

#### Request
```typescript
{
  prompt: string;                           // Required: Task description
  language?: string;                        // Optional: Response language
  modelConfig?: {
    apiKey?: string;
    baseUrl?: string;
    model?: string;
    apiType?: 'anthropic-messages' | 'openai-completions';
  };
  userId?: string;                          // Optional: Supabase user UUID (for memory/persona)
  accessToken?: string;                     // Optional: Supabase JWT (for RLS queries)
}
```

#### Response
- **Content-Type:** `text/event-stream`

#### SSE Event Types
```typescript
// Session created
{ type: 'session', sessionId: string }

// Streamed text/analysis
{ type: 'text', content: string }

// Tool invocation (if memory lookup happens)
{ type: 'tool_use', id: string, name: string, input: unknown }

// Tool result (if memory lookup happens)
{ type: 'tool_result', toolUseId: string, output: string, isError: boolean }

// Plan generated (emit only once if structured plan detected)
{
  type: 'plan',
  plan: {
    id: string;                    // Unique plan ID (nanoid)
    goal: string;                  // Overall objective
    steps: Array<{
      id: string;
      description: string;
      status: 'pending' | 'in_progress' | 'completed' | 'failed';
    }>;
    notes?: string;
    createdAt: Date;
  }
}

// If no structured plan found, may emit direct_answer instead
{ type: 'direct_answer', content: string }

// Completion
{ type: 'done' }

// Error
{ type: 'error', message: string }
```

#### Notes
- Plan is stored in global plan store (in-memory, shared across requests)
- Plan storage duration: Until API restarts or expires
- After receiving `plan` event, client should save the `plan.id` for `/agent/execute`

---

### 3. POST /agent/execute
**Execution Phase** — Executes an approved plan from `/agent/plan`.

#### Request
```typescript
{
  planId: string;                           // Required: Plan ID from POST /agent/plan response
  prompt: string;                           // Required: Original prompt (for context)
  workDir?: string;                         // Optional: Working directory for file outputs
  taskId?: string;                          // Optional: Task identifier for logging/context
  modelConfig?: {
    apiKey?: string;
    baseUrl?: string;
    model?: string;
    apiType?: 'anthropic-messages' | 'openai-completions';
  };
  sandboxConfig?: {
    enabled: boolean;                       // Whether sandbox isolation is enabled
    provider?: string;                      // e.g., 'codex', 'native', 'docker'
    image?: string;                         // Container image if using docker (e.g., 'node:18-alpine')
    apiEndpoint?: string;                   // API endpoint for sandbox service
    providerConfig?: Record<string, unknown>;  // Provider-specific config
  };
  skillsConfig?: {
    enabled: boolean;
    userDirEnabled: boolean;                // Load from ~/.claude/skills
    appDirEnabled: boolean;                 // Load from workspace/skills
    skillsPath?: string;                    // Custom path (legacy)
  };
  mcpConfig?: {
    enabled: boolean;
    userDirEnabled: boolean;                // Load from claude's MCP config
    appDirEnabled: boolean;                 // Load from sage's MCP config
    mcpConfigPath?: string;                 // Custom path (legacy)
  };
  language?: string;                        // Optional: Response language
  userId?: string;                          // Optional: Supabase user UUID
  accessToken?: string;                     // Optional: Supabase JWT
}
```

#### Response
- **Content-Type:** `text/event-stream`

#### SSE Event Types
```typescript
// Session created
{ type: 'session', sessionId: string }

// Streamed text response
{ type: 'text', content: string }

// Artifact blocks (auto-rendered)
{ type: 'text', content: '```artifact:TYPE\n{...data...}\n```' }

// Tool invocation
{ type: 'tool_use', id: string, name: string, input: unknown }

// Tool result (can be error)
{ type: 'tool_result', toolUseId: string, output: string, isError?: boolean }

// Execution result
{ type: 'result', content: string, cost?: number, duration?: number }

// Completion
{ type: 'done' }

// Error
{ type: 'error', message: string }
```

#### Error Responses
```typescript
// If planId not found
c.json({ error: 'Plan not found or expired' }, 404)

// If planId is missing
c.json({ error: 'planId is required' }, 400)
```

---

### 4. POST /agent (Direct Execution)
**Legacy Combined Endpoint** — Plans + executes in a single request (no approval step).

#### Request
```typescript
{
  prompt: string;                           // Required: Task or query
  conversation?: Array<{
    role: 'user' | 'assistant';
    content: string;
  }>;
  language?: string;
  workDir?: string;
  taskId?: string;
  modelConfig?: {
    apiKey?: string;
    baseUrl?: string;
    model?: string;
    apiType?: 'anthropic-messages' | 'openai-completions';
  };
  sandboxConfig?: {
    enabled: boolean;
    provider?: string;
    image?: string;
    apiEndpoint?: string;
    providerConfig?: Record<string, unknown>;
  };
  skillsConfig?: {
    enabled: boolean;
    userDirEnabled: boolean;
    appDirEnabled: boolean;
    skillsPath?: string;
  };
  mcpConfig?: {
    enabled: boolean;
    userDirEnabled: boolean;
    appDirEnabled: boolean;
    mcpConfigPath?: string;
  };
  images?: Array<{
    data: string;                           // Base64 encoded image data
    mimeType: string;                       // e.g., 'image/png', 'image/jpeg'
  }>;
  userId?: string;
  accessToken?: string;
}
```

#### Response
- **Content-Type:** `text/event-stream`

#### SSE Event Types
```typescript
// Session created
{ type: 'session', sessionId: string }

// Streamed text response
{ type: 'text', content: string }

// Tool invocations and results
{ type: 'tool_use', id: string, name: string, input: unknown }
{ type: 'tool_result', toolUseId: string, output: string, isError?: boolean }

// Artifact blocks
{ type: 'text', content: '```artifact:TYPE\n{...data...}\n```' }

// Execution completion
{ type: 'result', content: string, cost?: number, duration?: number }

// Final done
{ type: 'done' }

// Error
{ type: 'error', message: string }
```

#### Slash Command Handling
If prompt starts with `/`:

- **`/compact`** — Compress conversation history
  ```
  Response:
  { type: 'text', content: '✅ 上下文已压缩...' }
  { type: 'done' }
  ```

- **`/new`** — Clear session and start fresh
  ```
  Response:
  { type: 'text', content: '✅ 已开启新对话...' }
  { type: 'session_action', action: 'new' }
  { type: 'done' }
  ```

- **`/reset`** — Reset session (same as `/new`)
  ```
  Response:
  { type: 'session_action', action: 'reset' }
  { type: 'done' }
  ```

---

### 5. POST /agent/title
**Generate Title** — Creates a short title from a prompt (useful for conversation names).

#### Request
```typescript
{
  prompt: string;                           // Required: Text to generate title from
  modelConfig?: {
    apiKey?: string;
    baseUrl?: string;
    model?: string;
  };
  language?: string;                        // Optional: Response language
}
```

#### Response
```typescript
// JSON Response (NOT Server-Sent Events)
{
  title: string;                            // Generated short title
}
```

#### HTTP Status
- `200 OK` — Title generated successfully
- `400 Bad Request` — prompt is missing

#### Example
```
Request:
POST /agent/title
Authorization: Bearer <JWT>
Content-Type: application/json

{ "prompt": "How do I write a React component?" }

Response:
HTTP/1.1 200 OK
Content-Type: application/json

{ "title": "React Component Writing Guide" }
```

---

### 6. POST /agent/stop/:sessionId
**Stop Execution** — Cancels a running agent session.

#### Request
```
POST /agent/stop/abc123def456
Authorization: Bearer <JWT>
```

#### Response
```typescript
// JSON Response
{
  status: 'stopped'
}
```

#### HTTP Status
- `200 OK` — Session stopped
- `404 Not Found` — Session not found

#### Implementation Details
- Calls `deleteSession(sessionId)` which:
  - Aborts the `AbortController`
  - Removes session from active sessions map
  - Stops streaming any ongoing requests

---

### 7. GET /agent/session/:sessionId
**Get Session Status** — Retrieves current session state (read-only).

#### Request
```
GET /agent/session/abc123def456
Authorization: Bearer <JWT>
```

#### Response
```typescript
{
  id: string;
  createdAt: Date;
  phase: 'planning' | 'executing' | 'idle';
  isAborted: boolean;
}
```

#### HTTP Status
- `200 OK` — Session found
- `404 Not Found` — Session not found

---

### 8. GET /agent/plan/:planId
**Get Plan Details** — Retrieves a stored plan by ID (read-only).

#### Request
```
GET /agent/plan/plan_abc123
Authorization: Bearer <JWT>
```

#### Response
```typescript
{
  id: string;
  goal: string;
  steps: Array<{
    id: string;
    description: string;
    status: 'pending' | 'in_progress' | 'completed' | 'failed';
  }>;
  notes?: string;
  createdAt: Date;
}
```

#### HTTP Status
- `200 OK` — Plan found
- `404 Not Found` — Plan not found or expired

---

## SSE Event Types (Complete Reference)

All streaming endpoints use Server-Sent Events. Each event is sent as:

```
data: <JSON>\n\n
```

### Supported Event Types

| Type | Fields | Purpose |
|------|--------|---------|
| `session` | `sessionId: string` | Session created, use this ID for `/stop/:sessionId` |
| `text` | `content: string` | Streamed text response from model |
| `tool_use` | `id, name, input` | Model invoked a tool |
| `tool_result` | `toolUseId, name?, output, isError?` | Tool returned result |
| `result` | `content?, cost?, duration?` | Execution completed with metadata |
| `plan` | `plan: TaskPlan` | Structured plan generated (from `/plan` only) |
| `direct_answer` | `content: string` | Direct answer without structured plan |
| `session_action` | `action: 'new' \| 'reset'` | Session state changed (slash commands) |
| `error` | `message: string` | Error occurred |
| `done` | (no fields) | Stream finished (always last event) |

### Event Parsing Strategy
```typescript
// Client-side Swift pseudocode
while let line = readLine() {
  if line.starts(with: "data: ") {
    let jsonStr = String(line.dropFirst(6))
    if let data = jsonStr.data(using: .utf8),
       let event = try JSONDecoder().decode(AgentMessage.self, from: data) {
      handleEvent(event)
    }
  }
}
```

---

## ModelConfig Details

### Field Descriptions

| Field | Type | Default | Notes |
|-------|------|---------|-------|
| `apiKey` | `string?` | `process.env.ANTHROPIC_API_KEY` | Custom API key for external providers |
| `baseUrl` | `string?` | `https://api.anthropic.com/v1` (Anthropic) | Custom API endpoint (e.g., MiniMax, Ollama) |
| `model` | `string?` | `claude-3-5-sonnet-20241022` | Model identifier |
| `apiType` | `'anthropic-messages' \| 'openai-completions'?` | Auto-detect from baseUrl | API protocol version |

### Examples

#### Anthropic (Default)
```json
{
  "modelConfig": {
    "apiKey": "sk-ant-...",
    "model": "claude-3-5-sonnet-20241022"
  }
}
```

#### OpenAI-Compatible (MiniMax, Ollama, etc.)
```json
{
  "modelConfig": {
    "apiKey": "xxx",
    "baseUrl": "https://api.minimax.chat/v1",
    "model": "gpt-4-turbo",
    "apiType": "openai-completions"
  }
}
```

#### Custom Self-Hosted
```json
{
  "modelConfig": {
    "apiKey": "local-key",
    "baseUrl": "http://localhost:8000",
    "model": "local-model",
    "apiType": "anthropic-messages"
  }
}
```

---

## Authentication Flows

### For iOS Client

#### Step 1: User Login (Not part of Sage API)
```swift
// Your auth system (Firebase, Supabase, etc.)
let supabaseJWT = try await authProvider.login(email, password)
```

#### Step 2: Make Sage API Requests
```swift
let headers = [
  "Authorization": "Bearer \(supabaseJWT)",
  "Content-Type": "application/json"
]

// All requests use these headers
let request = URLRequest(url: sageMcpURL)
request.allHTTPHeaderFields = headers
```

#### Step 3: Handle JWT Expiry
```swift
// If you get 401 Unauthorized:
// 1. Refresh the JWT from your auth provider
// 2. Retry the request with new JWT
```

---

## Error Handling

### Common HTTP Status Codes

| Code | Scenario | Example |
|------|----------|---------|
| `200` | Success | Plan generated, title created |
| `400` | Bad request | Missing required field (`prompt`) |
| `401` | Unauthorized | Invalid JWT token or missing Authorization header |
| `404` | Not found | Session/Plan ID doesn't exist |
| `500` | Server error | API key error, model error |

### Error Response Format

#### JSON Errors
```json
{
  "error": "Description of what went wrong"
}
```

#### SSE Error Events
```json
{
  "type": "error",
  "message": "Error description or code"
}
```

### Special Error Messages
```
"__API_KEY_ERROR__"           → Invalid/missing API key
"__CUSTOM_API_ERROR__|URL|LOG" → Custom API endpoint failed
"__INTERNAL_ERROR__|LOG"       → Internal server error (check logs at path)
```

---

## Artifact Types

When the agent performs certain operations (e.g., fetching stock data), the response includes artifact blocks:

```
data: {"type":"text","content":"```artifact:TYPE\n{data}\n```"}
```

### Common Artifact Types

| Type | Use Case | Data Format |
|------|----------|-------------|
| `quote-card` | Stock quote snapshot | `{ code, name, price, chgVal, chgPct, ... }` |
| `kline-chart` | Stock price history chart | `{ code, name, data: [{ time, open, close, high, low, vol }] }` |
| `data-table` | Tabular data | `{ title, columns: [{key, label}], rows: [{}] }` |
| `news-list` | News/article list | `{ items: [{newId, title, summary, publishTime}] }` |
| `text` | Text document | Raw string content |

---

## Request/Response Size Limits

- **Max request body:** ~100 MB (for images)
- **Max stream duration:** No enforced limit (depends on task complexity)
- **Session timeout:** No enforced timeout (until API restart)

---

## Rate Limiting

Currently **not enforced** by sage-api. Limits may be applied at:
- Railway deployment level
- Reverse proxy/load balancer
- Client implementation (throttling)

---

## Example: Complete iOS Request Flow

### Scenario: User asks a question via iOS app

```swift
// 1. User logs in (handled by your auth system)
let jwt = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9..."

// 2. Prepare request
var request = URLRequest(url: URL(string: "https://sage-production-28e1.up.railway.app/agent")!)
request.httpMethod = "POST"
request.setValue("Bearer \(jwt)", forHTTPHeaderField: "Authorization")
request.setValue("application/json", forHTTPHeaderField: "Content-Type")

let body = [
  "prompt": "What is the capital of France?",
  "language": "en-US",
  "modelConfig": [
    "apiKey": "sk-ant-...",
    "model": "claude-3-5-sonnet-20241022"
  ]
] as [String: Any]

request.httpBody = try JSONSerialization.data(withJSONObject: body)

// 3. Stream response
let (stream, response) = try await URLSession.shared.bytes(for: request)

for try await line in stream {
  if line.starts(with: "data: ") {
    let jsonStr = String(line.dropFirst(6))
    let event = try JSONDecoder().decode(AgentMessage.self, from: jsonStr.data(using: .utf8)!)
    
    switch event.type {
    case "text":
      uiState.append(contentsOf: event.content ?? "")
    case "done":
      uiState.isLoading = false
      break
    case "error":
      showError(event.message ?? "Unknown error")
    default:
      break
    }
  }
}
```

---

## Testing

### Using cURL

#### Chat Endpoint
```bash
curl -X POST https://sage-production-28e1.up.railway.app/agent/chat \
  -H "Authorization: Bearer <JWT>" \
  -H "Content-Type: application/json" \
  -d '{
    "prompt": "Hello, how are you?",
    "language": "en-US"
  }'
```

#### Generate Title
```bash
curl -X POST https://sage-production-28e1.up.railway.app/agent/title \
  -H "Authorization: Bearer <JWT>" \
  -H "Content-Type: application/json" \
  -d '{"prompt": "How to write Swift?"}'
```

#### Stop Session
```bash
curl -X POST https://sage-production-28e1.up.railway.app/agent/stop/abc123 \
  -H "Authorization: Bearer <JWT>"
```

---

## Configuration

### Environment Variables (Backend)

| Variable | Purpose |
|----------|---------|
| `SAGE_API_TOKEN` | API token for server-to-server auth |
| `ANTHROPIC_API_KEY` | Default Anthropic API key |
| `PORT` | Server port (default: 2026) |
| `SUPABASE_URL` | Supabase project URL (for JWT validation) |
| `SUPABASE_SERVICE_ROLE_KEY` | Supabase service key (for memory RLS) |

### iOS Client Configuration

```swift
struct SageConfig {
  let baseURL = "https://sage-production-28e1.up.railway.app"
  let userJWT: String  // From your auth provider
  
  let modelConfig = ModelConfig(
    apiKey: "sk-ant-...",
    model: "claude-3-5-sonnet-20241022"
  )
}
```

---

## Troubleshooting

### 401 Unauthorized
- Check JWT is valid and not expired
- Verify JWT belongs to Supabase user
- Check `Authorization` header format: `Bearer <JWT>`

### 404 Not Found (plan)
- Plan may have expired
- Try creating a new plan with `/agent/plan`
- Plans are stored in-memory and lost on API restart

### Timeout / No Response
- Check network connectivity
- Verify endpoint URL is correct
- Try `/agent/title` to test connectivity

### Empty or Corrupted SSE Events
- Ensure client handles multiline events properly
- Each event ends with `\n\n`
- Parse only lines starting with `data: `

---

## Version History

| Date | Changes |
|------|---------|
| 2026-05-20 | Initial documentation |

---

## Support

For issues or questions about the API:
1. Check the troubleshooting section
2. Review server logs at `~/.sage/logs/sage.log`
3. Verify modelConfig is correct for your API provider
