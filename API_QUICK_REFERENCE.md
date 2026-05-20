# Sage Backend API - Quick Reference for iOS Development

## Base Information
- **URL:** `https://sage-production-28e1.up.railway.app`
- **Auth:** `Authorization: Bearer <SUPABASE_JWT>`
- **Response Type:** Server-Sent Events (text/event-stream)

## Endpoints Summary

| Endpoint | Method | Purpose | Returns |
|----------|--------|---------|---------|
| `/agent` | POST | Direct execution (plan + execute) | SSE stream |
| `/agent/chat` | POST | Lightweight chat | SSE stream |
| `/agent/plan` | POST | Create plan (no execute) | SSE stream + `{ type: 'plan', plan: {...} }` |
| `/agent/execute` | POST | Execute approved plan | SSE stream |
| `/agent/title` | POST | Generate title from text | `{ title: string }` (JSON) |
| `/agent/stop/:sessionId` | POST | Stop running session | `{ status: 'stopped' }` |
| `/agent/session/:sessionId` | GET | Check session status | Session info |
| `/agent/plan/:planId` | GET | Retrieve plan details | Plan info |

## SSE Event Types

```typescript
{ type: 'session', sessionId: string }           // Stream start
{ type: 'text', content: string }                // Streamed response
{ type: 'tool_use', id: string, name: string, input: unknown }  // Tool call
{ type: 'tool_result', toolUseId: string, output: string }      // Tool result
{ type: 'result', content: string, cost?: number, duration?: number }  // Summary
{ type: 'plan', plan: TaskPlan }                 // Plan (from /plan only)
{ type: 'direct_answer', content: string }       // No structured plan
{ type: 'session_action', action: 'new'|'reset' }  // Session cleared
{ type: 'error', message: string }               // Error
{ type: 'done' }                                 // Stream end (always last)
```

## Request Body Common Fields

### All Endpoints
```typescript
{
  prompt: string;                          // Required (except /title, /stop/:id, /session/:id, /plan/:id)
  language?: string;                       // e.g., 'en-US', 'zh-CN'
  modelConfig?: {
    apiKey?: string;
    baseUrl?: string;
    model?: string;
    apiType?: 'anthropic-messages' | 'openai-completions';
  };
}
```

### /agent & /agent/execute (Full execution)
```typescript
{
  prompt: string;
  workDir?: string;                        // Working directory
  taskId?: string;                         // Task ID for context
  conversation?: Array<{ role, content }>; // History
  images?: Array<{ data: string, mimeType: string }>;  // Base64 images
  sandboxConfig?: {                        // Isolated execution
    enabled: boolean;
    provider?: string;
    image?: string;
  };
  skillsConfig?: {                         // Tool extensions
    enabled: boolean;
    userDirEnabled: boolean;
    appDirEnabled: boolean;
  };
  mcpConfig?: {                            // Model Context Protocol servers
    enabled: boolean;
    userDirEnabled: boolean;
    appDirEnabled: boolean;
  };
  userId?: string;                         // Supabase user UUID (for memory)
  accessToken?: string;                    // Supabase JWT (for RLS)
}
```

### /agent/plan → /agent/execute (Two-phase)
```typescript
// /agent/plan response includes:
{ type: 'plan', plan: { id, goal, steps, createdAt } }

// Use plan.id in /agent/execute:
{
  planId: string;                          // Required: from plan.id
  prompt: string;
  // ... other fields
}
```

## Key Concepts

### Two-Phase Execution
1. **POST /agent/plan** → Get `plan` event → Save `plan.id`
2. **POST /agent/execute** → Use `planId` → Execute approved plan

### Direct Execution
- **POST /agent** → Combines plan + execute → Full response

### ModelConfig Override
```typescript
// Use custom API instead of default Anthropic
{
  modelConfig: {
    apiKey: "...",
    baseUrl: "https://api.minimax.chat/v1",
    model: "gpt-4-turbo",
    apiType: "openai-completions"
  }
}
```

## Error Codes

| Code | Meaning |
|------|---------|
| 200 | Success |
| 400 | Bad request (missing required field) |
| 401 | Unauthorized (invalid/missing JWT) |
| 404 | Not found (session/plan doesn't exist) |
| 500 | Server error |

## SSE Parsing (Swift)

```swift
func streamAgentResponse(jwt: String, prompt: String) async throws {
  var request = URLRequest(url: URL(string: "https://sage-production-28e1.up.railway.app/agent")!)
  request.httpMethod = "POST"
  request.setValue("Bearer \(jwt)", forHTTPHeaderField: "Authorization")
  request.httpBody = try JSONEncoder().encode(["prompt": prompt])
  
  let (stream, response) = try await URLSession.shared.bytes(for: request)
  
  for try await line in stream {
    if line.starts(with: "data: ") {
      let jsonStr = String(line.dropFirst(6))
      if let data = jsonStr.data(using: .utf8) {
        let event = try JSONDecoder().decode(AgentEvent.self, from: data)
        handleEvent(event)
      }
    }
  }
}
```

## Swift Model Types

```swift
struct AgentEvent: Codable {
  let type: String
  let content: String?
  let message: String?
  let sessionId: String?
  let id: String?
  let name: String?
  let input: AnyCodable?
  let toolUseId: String?
  let output: String?
  let isError: Bool?
  let plan: TaskPlan?
  let cost: Double?
  let duration: Int?
  let action: String?
}

struct TaskPlan: Codable {
  let id: String
  let goal: String
  let steps: [PlanStep]
  let notes: String?
  let createdAt: Date
}

struct PlanStep: Codable {
  let id: String
  let description: String
  let status: String  // 'pending' | 'in_progress' | 'completed' | 'failed'
}

struct ModelConfig: Codable {
  let apiKey: String?
  let baseUrl: String?
  let model: String?
  let apiType: String?  // 'anthropic-messages' | 'openai-completions'
}

struct AgentRequest: Codable {
  let prompt: String
  let conversation: [ConversationMessage]?
  let language: String?
  let workDir: String?
  let taskId: String?
  let modelConfig: ModelConfig?
  let sandboxConfig: SandboxConfig?
  let skillsConfig: SkillsConfig?
  let mcpConfig: McpConfig?
  let images: [ImageAttachment]?
  let userId: String?
  let accessToken: String?
}

struct ImageAttachment: Codable {
  let data: String  // Base64 encoded
  let mimeType: String
}

struct ConversationMessage: Codable {
  let role: String  // 'user' | 'assistant'
  let content: String
}
```

## Artifact Rendering

When you see:
```
{ type: 'text', content: '```artifact:TYPE\n{...json...}\n```' }
```

Extract and render based on TYPE:
- `quote-card` → Stock price card
- `kline-chart` → Price history chart
- `data-table` → Table view
- `news-list` → News list
- `text` → Plain text

## Authentication Flow

```swift
// 1. Get JWT from Supabase (your auth system)
let jwt = try await supabase.auth.signIn(email: email, password: password)

// 2. Use in all Sage requests
var request = URLRequest(url: URL(string: "https://sage-production-28e1.up.railway.app/agent")!)
request.setValue("Bearer \(jwt)", forHTTPHeaderField: "Authorization")

// 3. If 401 received:
//    - Refresh JWT from Supabase
//    - Retry request with new token
```

## Complete Example: Plan + Execute

```swift
// Step 1: Create plan
let planRequest: [String: Any] = [
  "prompt": "Write a Python script that downloads images from a URL list",
  "language": "en-US"
]

var planReq = URLRequest(url: URL(string: "https://sage-production-28e1.up.railway.app/agent/plan")!)
planReq.httpMethod = "POST"
planReq.setValue("Bearer \(jwt)", forHTTPHeaderField: "Authorization")
planReq.httpBody = try JSONSerialization.data(withJSONObject: planRequest)

// Stream and capture plan.id from { type: 'plan', plan: {...} } event
let planId = "..." // from response

// Step 2: Execute plan
let execRequest: [String: Any] = [
  "planId": planId,
  "prompt": "Write a Python script that downloads images from a URL list",
  "workDir": "/tmp/workspace"
]

var execReq = URLRequest(url: URL(string: "https://sage-production-28e1.up.railway.app/agent/execute")!)
execReq.httpMethod = "POST"
execReq.setValue("Bearer \(jwt)", forHTTPHeaderField: "Authorization")
execReq.httpBody = try JSONSerialization.data(withJSONObject: execRequest)

// Stream full execution response...
```

---

**Full documentation:** See `SAGE_API_CONTRACT.md` for complete details on all endpoints, request/response types, and error handling.
