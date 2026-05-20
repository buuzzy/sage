# Sage iOS App — Implementation Guide

## Current Status: Phase 1 (In Progress)

### Phase 1: SwiftUI 项目骨架 + Supabase 认证
- ✅ **Completed**:
  - Xcode project setup with `project.yml` (XcodeGen)
  - Swift Package Manager dependencies (Supabase, MarkdownUI)
  - AuthService with email/password + Google OAuth support
  - LoginView with email/password + OAuth mode switching
  - MainView with sidebar + chat layout
  - ChatViewModel with SSE streaming
  - MessageRow rendering (user bubbles, AI responses, action bar)
  - InputBarView with model configuration check
  - SettingsService with provider list (8 default providers)
  - APIClient with Bearer token authentication

- ⚠️ **To Complete**:
  - [ ] Test email/password login with Supabase
  - [ ] Verify JWT token handling in API calls
  - [ ] Test SSE streaming integration
  - [ ] Implement SidebarView session list
  - [ ] Implement MarkdownContentView
  - [ ] Add error state handling throughout app
  - [ ] Test on iOS 16+ simulator

---

## Architecture Overview

### Directory Structure
```
sage-ios/
├── Sage/
│   ├── SageApp.swift              # Entry point + root layout
│   ├── Models/
│   │   └── Message.swift          # SSE events, Agent request/response
│   ├── Services/
│   │   ├── AuthService.swift      # Supabase auth + JWT
│   │   ├── APIClient.swift        # HTTP + SSE streaming
│   │   └── SettingsService.swift  # UserDefaults provider list
│   ├── ViewModels/
│   │   ├── ChatViewModel.swift    # Message state + streaming
│   │   └── SessionListViewModel.swift
│   └── Views/
│       ├── Auth/
│       │   └── LoginView.swift
│       ├── Chat/
│       │   ├── InputBarView.swift
│       │   ├── MessageRow.swift
│       │   └── MarkdownContentView.swift
│       ├── Sessions/
│       │   └── SidebarView.swift
│       ├── Settings/
│       │   └── SettingsView.swift
│       └── MainView.swift
```

### Key Design Decisions

1. **State Management**: No Redux/Zustand. Using SwiftUI's `@Published` + `@StateObject` per component hierarchy.
2. **Networking**: Actor-based APIClient for thread-safe SSE streaming.
3. **Auth**: Supabase-native (no custom JWT validation). Bearer token in Authorization header.
4. **Markdown**: MarkdownUI framework (https://github.com/gonzalezreal/swift-markdown-ui).
5. **API Server**: Railway backend (https://sage-production-28e1.up.railway.app) with Bearer token auth.

---

## Authentication Flow

### Email/Password Login
```
LoginView (switch to email mode)
  ↓
User enters email + password
  ↓
AuthService.signInWithEmail()
  ↓
Supabase client: client.auth.signIn(email:, password:)
  ↓
Success: currentUser set, isAuthenticated = true
  ↓
JWT token stored in Supabase session
  ↓
SageApp detects isAuthenticated → shows MainView
```

### Token Usage in API Calls
```
AuthService.getAccessToken() → returns JWT
  ↓
APIClient.streamAgent(request:)
  ↓
Headers: Authorization: "Bearer <token>"
  ↓
Railway backend validates token with Supabase
```

---

## Chat Streaming Flow

### Message Sending
```
User types prompt → InputBarView.send()
  ↓
ChatViewModel.sendMessage(prompt)
  ↓
1. Append ChatMessage(role: .user, content: prompt)
2. Append ChatMessage(role: .assistant, content: "", isStreaming: true)
3. Build AgentRequest with modelConfig + JWT token
4. Call APIClient.streamAgent(request:)
  ↓
SSE stream begins
```

### SSE Event Processing
```
for try await event in stream:
  case .text / .directAnswer:
    Append to messages[index].content
  case .toolUse:
    Show "🔧 调用 ToolName..."
  case .plan:
    Set phase = "awaiting_approval"
    Show plan data in messages[index].plan
  case .error:
    Append error message
  case .done / .result:
    messages[index].isStreaming = false
```

---

## API Integration

### Base URL & Auth
- **iOS URL**: https://sage-production-28e1.up.railway.app
- **Desktop URL**: http://127.0.0.1:2026 (sidecar)
- **Auth**: Bearer token from Supabase JWT

### Endpoints
| Endpoint | Method | Body | Response |
|----------|--------|------|----------|
| `/agent` | POST | AgentRequest | SSE stream (SSEEvent) |
| `/agent/plan` | POST | AgentRequest | SSE stream (plan event) |
| `/agent/execute` | POST | AgentRequest | SSE stream (execution) |
| `/agent/title` | POST | { prompt, modelConfig, language } | { title: String } |
| `/agent/stop/:sessionId` | POST | - | - |

### AgentRequest Structure
```swift
struct AgentRequest: Codable {
    let prompt: String
    var workDir: String?
    var taskId: String?
    var modelConfig: ModelConfig?
    var sandboxConfig: SandboxConfig?
    var skillsConfig: SkillsConfig?
    var mcpConfig: MCPConfig?
    var language: String?           // "zh-CN" for Chinese
    var userId: String?             // from AuthService.userId
    var accessToken: String?        // JWT from AuthService.getAccessToken()
    var conversation: [ConversationMessage]?
    var images: [ImageAttachment]?
}
```

---

## Component Details

### LoginView
- **Modes**: OAuth (Google) OR Email/Password
- **States**: 
  - `isEmailMode`: Toggle between modes
  - `email`, `password`: Input fields
  - `isLoading`: Show spinner during auth
  - `localError`: Display form validation errors
- **Note**: OAuth may need WebView wrapper for iOS native flow

### MessageRow
- **User Messages**: Right-aligned gray bubble, `systemGray5` background
- **AI Messages**: Left-aligned plain text with markdown rendering
- **Action Bar**: Copy, Thumbs Up/Down, Retry buttons (only when not streaming)
- **Error Messages**: Orange warning badge with icon

### InputBarView
- **Placeholder**: Changes based on state
  - "请先配置模型..." → model not configured
  - "等待回复..." → agent running
  - "询问 Sage..." → ready to send
- **Disabled when**: `isRunning` or `text.isEmpty`
- **Send/Stop toggle**: Shows arrow icon when ready, stop icon when running

### SettingsView (TODO)
- **Tabs**: Account, Model, Provider, Appearance
- **Model Config**: Provider selector + API key input + Model dropdown
- **Appearance**: Theme (light/dark/system) + Accent color picker
- **Save**: Persists to UserDefaults as JSON

---

## Supabase Integration

### Config
- **URL**: https://wymqgwtagpsjuonsclye.supabase.co
- **Anon Key**: (in AuthService.swift)
- **Tables**: 
  - `auth.users` → Created by Supabase Auth
  - `profiles` → User profile data (sync from Railway)
  - `sessions` → Chat session metadata
  - `messages` → Full conversation messages (RLS: user_id)

### Auth Session
```swift
// Check session
let session = try await client.auth.session
let user = session.user

// Get JWT token
let token = try await client.auth.session.accessToken

// Listen for changes
for await (event, session) in client.auth.authStateChanges {
    // .signedIn / .signedOut / .tokenRefreshed
}
```

---

## Phase 2 Preview: UI Polish + Advanced Features

### Mobile Adaptations Needed
- [ ] Bottom tab bar instead of left sidebar (Portrait mode)
- [ ] Sidebar drawer (Landscape mode)
- [ ] Safe area insets (notch/home indicator)
- [ ] Keyboard avoidance in input bar
- [ ] Haptic feedback on send/error
- [ ] Pull-to-refresh for session list
- [ ] Long-press menu for session actions (rename/delete)

### Real Chat Features
- [ ] Load previous sessions from backend
- [ ] Persist messages to local SQLite + sync to Supabase
- [ ] Message editing / retry
- [ ] Artifact rendering (charts, code, etc.)
- [ ] Image attachments
- [ ] Plan approval flow (visual blocks + approve/reject buttons)
- [ ] Tool execution display (same as desktop ToolExecutionItem)
- [ ] Copy/export actions per desktop app

### Settings Screens
- [ ] Model Provider Configuration
- [ ] API Key Input (secure storage via Keychain)
- [ ] Theme Selector (light/dark/system)
- [ ] Accent Color Picker (7 colors like desktop)
- [ ] Language Toggle (English / 中文)
- [ ] About / Version Info
- [ ] Log Out Button

---

## Testing Checklist for Phase 1

### Authentication
- [ ] Email/password login with valid credentials
- [ ] Email/password login with invalid credentials (error display)
- [ ] Google OAuth login (if WebView adapted)
- [ ] Session persistence (restart app, still logged in)
- [ ] Log out clears session
- [ ] JWT token refresh before expiry

### Chat
- [ ] Send message, receive SSE stream
- [ ] Message appears in UI as streaming
- [ ] Multiple messages show correctly
- [ ] Agent error handled gracefully
- [ ] Stop button cancels streaming
- [ ] Title auto-generated for first message
- [ ] Scrolls to latest message automatically

### Settings
- [ ] Select different provider
- [ ] Enter API key
- [ ] Select model from provider list
- [ ] Settings persist across app restart
- [ ] Model configuration check enables send button

### Error Handling
- [ ] Network timeout shows error message
- [ ] Invalid token shows login screen
- [ ] API errors display user-friendly messages
- [ ] Retry mechanism available

---

## Important Notes

1. **API Token**: Currently hardcoded in APIClient.swift. Should move to secure environment variable or Keychain.
2. **Supabase Keys**: Currently hardcoded in AuthService.swift. Public anon key is OK (client-side), but should not commit API keys to git.
3. **SSE Parsing**: Using UTF-8 safe `.lines` iterator to handle multi-byte characters correctly.
4. **Stream Cancellation**: Properly cancels URLSession task on view dealloc or user-initiated stop.
5. **Actor Thread Safety**: APIClient is an actor to prevent race conditions on shared state.

---

## Build & Run

### Prerequisites
- Xcode 16+
- iOS 16.0+ deployment target
- Swift 5.9+
- pnpm 10.33.0 (for desktop API binary builds)

### Local Development
```bash
cd sage-ios
xcodegen generate  # Generate .xcodeproj from project.yml
open Sage.xcodeproj
# Select iPhone simulator
# Press ▶️ to build and run
```

### Environment Configuration
For production testing, ensure:
```
.env (in sage-ios/):
VITE_API_URL=https://sage-production-28e1.up.railway.app
SAGE_API_TOKEN=<your-token>
```

---

## Next Steps

1. **Test Phase 1**: Verify authentication and basic chat flow on simulator
2. **Fix Issues**: Handle any compilation errors or runtime crashes
3. **Start Phase 2**: Mobile UI adaptations (bottom tab bar, Safe Area handling)
4. **Session Management**: Implement session persistence and list view
5. **Advanced Features**: Plan approval, tool execution, artifact rendering

See `docs/ios/IOS_PLAN.md` for full project roadmap.
