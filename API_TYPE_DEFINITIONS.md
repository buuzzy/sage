# Sage Backend API - TypeScript Type Definitions

These are the exact TypeScript interfaces used by the backend API. Use these as your contract for request/response serialization.

## Core Types

### AgentMessage (SSE Events)
**Source:** `src/core/agent/types.ts`

```typescript
export type AgentMessageType =
  | 'session'
  | 'text'
  | 'tool_use'
  | 'tool_result'
  | 'result'
  | 'error'
  | 'done'
  | 'plan'
  | 'direct_answer';

export interface AgentMessage {
  type: AgentMessageType;
  sessionId?: string;
  content?: string;
  name?: string;
  id?: string;
  input?: unknown;
  cost?: number;
  duration?: number;
  // Tool result fields
  toolUseId?: string;
  output?: string;
  isError?: boolean;
  // Plan fields
  plan?: TaskPlan;
  // Error fields
  message?: string;
}
```

### Request Types

#### AgentRequest (Common for all `/agent` endpoints)
**Source:** `src/shared/types/agent.ts`

```typescript
export interface AgentRequest {
  prompt: string;
  sessionId?: string;
  conversation?: Array<{
    role: 'user' | 'assistant';
    content: string;
  }>;
  /** Preferred response language (e.g., en-US, zh-CN) */
  language?: string;
  // Two-phase execution control
  phase?: 'plan' | 'execute';
  planId?: string; // Reference to approved plan
  // Workspace settings
  workDir?: string; // Working directory for session outputs
  taskId?: string; // Task ID for session folder
  // Skills configuration
  skillsConfig?: SkillsConfigRequest;
  // MCP configuration
  mcpConfig?: McpConfigRequest;
  // Provider selection (optional, defaults to env config)
  provider?: 'codeany';
  // Custom model configuration
  modelConfig?: ModelConfig;
  // Sandbox configuration for isolated execution
  sandboxConfig?: SandboxConfig;
  // Image attachments for vision capabilities
  images?: ImageAttachment[];
  /**
   * Supabase auth.users.id of the current end-user (UUID).
   * Forwarded to the built-in memory MCP so search_memory can scope
   * results to this user. If absent, memory tool is not available.
   */
  userId?: string;
  /**
   * Supabase access token (JWT) of the current end-user.
   *
   * Required for desktop sidecar mode: sage-api forwards this to the
   * built-in memory MCP, which uses it together with the public anon key
   * to talk to Supabase under user-scoped RLS — so the desktop binary
   * never needs to ship a service-role key.
   *
   * Optional in service-role contexts (Railway etc.): when omitted,
   * the memory provider falls back to the server's service-role client
   * and filters by `userId` at the application layer.
   */
  accessToken?: string;
}
```

#### ModelConfig
**Source:** `src/shared/types/agent.ts`

```typescript
export interface ModelConfig {
  apiKey?: string; // API key
  baseUrl?: string; // Custom API base URL
  model?: string; // Model name to use
  apiType?: 'anthropic-messages' | 'openai-completions'; // API format type
}
```

#### SandboxConfig
**Source:** `src/shared/types/agent.ts`

```typescript
export interface SandboxConfig {
  enabled: boolean; // Whether sandbox mode is enabled
  provider?: string; // Sandbox provider to use (e.g., 'codex', 'native', 'docker')
  image?: string; // Container image to use (e.g., node:18-alpine)
  apiEndpoint?: string; // API endpoint for sandbox service
  providerConfig?: Record<string, unknown>; // Provider-specific configuration
}
```

#### ImageAttachment
**Source:** `src/shared/types/agent.ts`

```typescript
export interface ImageAttachment {
  data: string; // Base64 encoded image data
  mimeType: string; // e.g., 'image/png', 'image/jpeg'
}
```

#### SkillsConfigRequest
**Source:** `src/shared/types/agent.ts`

```typescript
export interface SkillsConfigRequest {
  enabled: boolean;
  userDirEnabled: boolean;
  appDirEnabled: boolean;
  skillsPath?: string;
}
```

#### McpConfigRequest
**Source:** `src/shared/types/agent.ts`

```typescript
export interface McpConfigRequest {
  enabled: boolean;
  userDirEnabled: boolean;
  appDirEnabled: boolean;
  mcpConfigPath?: string;
}
```

### Plan Types

#### TaskPlan
**Source:** `src/core/agent/types.ts`

```typescript
export interface TaskPlan {
  id: string;
  goal: string;
  steps: PlanStep[];
  notes?: string;
  createdAt: Date;
}
```

#### PlanStep
**Source:** `src/core/agent/types.ts`

```typescript
export interface PlanStep {
  id: string;
  description: string;
  status: 'pending' | 'in_progress' | 'completed' | 'failed';
}
```

### Conversation Message
**Source:** `src/core/agent/types.ts`

```typescript
export interface ConversationMessage {
  role: 'user' | 'assistant';
  content: string;
  /** Image file paths attached to this message (saved to workspace) */
  imagePaths?: string[];
}
```

## Endpoint-Specific Request Bodies

### POST /agent/chat
Extends `AgentRequest` with:
- Required: `prompt`
- Optional: `conversation`, `language`, `modelConfig`

### POST /agent/plan
Extends `AgentRequest` with:
- Required: `prompt`
- Optional: `language`, `modelConfig`, `userId`, `accessToken`

### POST /agent/execute
Custom body structure:
```typescript
{
  planId: string;                           // Required
  prompt: string;                           // Required
  workDir?: string;
  taskId?: string;
  modelConfig?: { apiKey?, baseUrl?, model?, apiType? };
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
  language?: string;
  userId?: string;
  accessToken?: string;
}
```

### POST /agent (Direct execution)
Extends `AgentRequest` with:
- Required: `prompt` (or `images`)
- Optional: All fields including `images`, `conversation`, `workDir`, `taskId`

### POST /agent/title
```typescript
{
  prompt: string;                           // Required
  modelConfig?: {
    apiKey?: string;
    baseUrl?: string;
    model?: string;
  };
  language?: string;
}
```

## Response Types

### Success JSON Responses

#### /agent/title
```typescript
{
  title: string;
}
```

#### /agent/stop/:sessionId
```typescript
{
  status: 'stopped';
}
```

#### /agent/session/:sessionId
```typescript
{
  id: string;
  createdAt: Date;
  phase: 'planning' | 'executing' | 'idle';
  isAborted: boolean;
}
```

#### /agent/plan/:planId
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

### Error JSON Responses

```typescript
{
  error: string;
}
```

### SSE Event Response (Streaming)

All streaming endpoints return events in this format:
```
data: {JSON_OBJECT}\n\n
```

Where `JSON_OBJECT` matches one of the `AgentMessage` types:

```typescript
// Session start
{ type: 'session', sessionId: string }

// Text streaming
{ type: 'text', content: string }

// Tool invocation
{ type: 'tool_use', id: string, name: string, input: unknown }

// Tool result
{
  type: 'tool_result',
  toolUseId: string,
  name?: string,
  output: string,
  isError?: boolean
}

// Execution result with metadata
{
  type: 'result',
  content?: string,
  cost?: number,
  duration?: number
}

// Plan generated (from /agent/plan only)
{ type: 'plan', plan: TaskPlan }

// Direct answer without plan (from /agent/plan only)
{ type: 'direct_answer', content: string }

// Session action event (from /agent with slash commands)
{ type: 'session_action', action: 'new' | 'reset' }

// Error
{ type: 'error', message: string }

// Stream end (always last)
{ type: 'done' }
```

## HTTP Headers

### Request Headers (all requests)
```
Authorization: Bearer <SUPABASE_JWT>
Content-Type: application/json
```

### Response Headers (streaming)
```
Content-Type: text/event-stream
Cache-Control: no-cache, no-transform
Connection: keep-alive
X-Accel-Buffering: no
```

## Field Validation Rules

### prompt
- Type: `string`
- Required for: `/agent`, `/agent/chat`, `/agent/plan`, `/agent/title`
- Min length: 1
- Max length: ~100,000 characters (but very large prompts may be rejected)

### apiKey (in modelConfig)
- Type: `string`
- Format: Provider-specific (e.g., `sk-ant-...` for Anthropic)
- Optional: Falls back to `process.env.ANTHROPIC_API_KEY`

### baseUrl (in modelConfig)
- Type: `string`
- Format: HTTP/HTTPS URL
- Optional: Falls back to provider defaults
- Examples:
  - `https://api.anthropic.com/v1` (Anthropic)
  - `https://api.minimax.chat/v1` (MiniMax)
  - `http://localhost:8000` (Local)

### model
- Type: `string`
- Examples:
  - `claude-3-5-sonnet-20241022`
  - `gpt-4-turbo`
  - `claude-3-5-haiku-20241022`
- Optional: Falls back to provider defaults

### apiType
- Type: `'anthropic-messages' | 'openai-completions'`
- Optional: Auto-detects from baseUrl if not provided
- Required when using custom baseUrl with non-standard format

### userId
- Type: `string` (UUID format)
- Source: `Supabase auth.users.id`
- Optional: Only needed if using memory/persona features
- When provided: Enables `search_memory` tool for user

### accessToken
- Type: `string` (JWT format)
- Source: Supabase user JWT
- Optional in cloud mode (Railway)
- Required for desktop sidecar mode with RLS queries

### workDir
- Type: `string` (filesystem path)
- Optional: Defaults to `~/.sage`
- Used for: File outputs, session workspace
- Expansion: `~` expands to user home directory

### taskId
- Type: `string` (any unique identifier)
- Optional: Falls back to `nanoid()` if not provided
- Used for: Persistent context across turns, logging
- Recommended: Use same `taskId` for multi-turn conversations

### language
- Type: `string`
- Format: BCP 47 language tag (e.g., `en-US`, `zh-CN`, `fr-FR`)
- Optional: Falls back to model defaults
- Effect: Instructs model to respond in specified language

### conversation
- Type: `Array<{ role: 'user' | 'assistant', content: string }>`
- Optional: Empty or omitted for new conversation
- Order: Must be chronological (oldest first)
- Max items: Recommended ~20-30 for optimal performance

### images
- Type: `Array<{ data: string, mimeType: string }>`
- data: Base64 encoded (with or without `data:image/...;base64,` prefix)
- mimeType: `image/png`, `image/jpeg`, `image/gif`, `image/webp`
- Optional: Omit for non-vision requests
- Saved to: `workDir` as image files

## Encoding/Decoding Notes

### Base64 Image Data
```swift
// Encoding (iOS)
let imageData = try Data(contentsOf: imageURL)
let base64String = imageData.base64EncodedString()
let attachment = ["data": base64String, "mimeType": "image/png"]

// Decoding (optional, server side)
let decodedData = Data(base64Encoded: base64String)
let image = UIImage(data: decodedData)
```

### Date Encoding
- Format: ISO 8601 (e.g., `2026-05-20T13:24:00.000Z`)
- Swift Decoder: Uses default ISO8601DateFormatter

### Artifact Data Structure
```typescript
// When artifact block is found in response:
const artifactText = '```artifact:TYPE\n{...json...}\n```';

// Extract using regex:
const match = artifactText.match(/```artifact:(\w+)\n([\s\S]*?)\n```/);
const artifactType = match?.[1]; // e.g., 'data-table'
const dataJson = match?.[2];     // e.g., '{"title":"...","columns":[...]}'
const artifactData = JSON.parse(dataJson);
```

## Error Response Examples

### 400 Bad Request
```json
{
  "error": "prompt is required"
}
```

### 401 Unauthorized
```json
{
  "error": "Unauthorized"
}
```

### 404 Not Found
```json
{
  "error": "Session not found"
}
```

## Size Limits

| Field | Max Size |
|-------|----------|
| `prompt` | ~100KB |
| `conversation` total | ~500KB |
| `images` total | ~100MB |
| Request body | ~100MB |
| Single image | ~50MB |

## Timeout Behavior

- Streaming endpoints: No server-side timeout (client controls)
- JSON endpoints: ~30 second timeout (Railway default)
- SSE reconnect: Client should implement exponential backoff

## Rate Limiting

- Currently **not enforced** by Sage API
- May be limited by Railway deployment
- Recommended: 100 requests/minute per user

