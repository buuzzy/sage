# Sage Desktop App - UI Specifications for SwiftUI iOS Replica

## 1. TOOL EXECUTION DISPLAY (`ToolExecutionItem.tsx`)

### Visual Hierarchy
**Line 1 (Tool Call)**:
- Bullet indicator (2×2px, rounded) - color-coded:
  - **Amber with pulse animation** (`animate-pulse bg-amber-500`) - Running state
  - **Red** (`bg-red-500`) - Error
  - **Amber** (`bg-amber-500`) - Warning (expected non-fatal)
  - **Emerald** (`bg-emerald-500`) - Success/Completed
  - **Muted foreground** - Default
- Tool name: **Semibold** text in `foreground` color
- Parameters: Wrapped in parentheses, `muted-foreground` color, truncated to 60 chars max
- Format: `BashName(truncated_param...)`

**Line 2 (Result Summary)**:
- Tree branch symbol "└" in `muted-foreground/40` opacity
- Result summary text:
  - **Red** - Error output
  - **Amber** - Warning/Info
  - **Muted foreground** - Normal

### Result Summaries by Tool Type
```
Read → "Read N lines"
Write → "File created successfully"
Edit → "File modified successfully"
Bash → "N lines of output" OR "Single line preview" OR "(No output)"
Grep → "Found matches in N files" OR "No matches found"
Glob → "Found N files" OR "No files found"
WebFetch → "Fetched N characters"
WebSearch → "Search completed"
TodoWrite → "Todo list updated"
Task → "Subtask completed"
```

### Interactive Features
- Hover state: `hover:bg-accent/50 cursor-pointer` (unless running)
- Click opens modal with full I/O details
- Modal styling:
  - Header: Tool name (monospace) + badge (`px-1.5 py-0.5 text-xs rounded`)
  - Input/Output sections with monospace text, 10000 char truncation
  - Dark backgrounds: `bg-muted/50` normal, `bg-red-500/10` for errors
  - Close button (X icon) in top right

### Spacing
- Container: `-mx-1 rounded-md px-1 py-1.5`
- Line 1: `flex items-start gap-2`
- Line 2: `mt-0.5 ml-1 flex items-start gap-2`
- Font: `font-mono text-[13px]`

---

## 2. MESSAGE ACTION BAR (`AgentActionBar.tsx`)

### Four Action Buttons (left to right)

**Button 1: Copy Answer**
- Icon: `Copy` (3×3px)
- Label: "复制回答" → "已复制" (2s toggle)
- Style: `text-muted-foreground hover:text-foreground hover:bg-muted`
- Font: `text-xs`

**Button 2: Copy Full Process**
- Icon: `Copy` (3×3px)
- Label: "复制完整过程" → "已复制" (2s toggle)
- Includes tool calls + markdown
- Same style as Button 1

**Button 3: Export as Image**
- Icon: `ImageIcon` (3×3px)
- Label: "导出图片" → "导出中…" (disabled state)
- Downloads to system Downloads dir as `sage-YYYY-MM-DDTHH-mm-ss.png`
- Renders with 2× pixel ratio, white background
- Hides action bar from screenshot via CSS class
- Same disabled opacity: `disabled:opacity-40`

**Button 4: Bug Report** (Popover)
- Icon: `AlertTriangle` (3×3px)
- Label: "反馈问题"
- Opens popover above button (`bottom-full left-0 mb-2`)
- Popover width: `w-72`

**Bug Report Popover Content**:
- Title: "反馈问题类型" (12px, semibold)
- Radio buttons for 5 categories:
  1. 回答错误
  2. 工具调用异常
  3. 界面问题
  4. 性能问题
  5. 其他
- Textarea: "补充说明（可选）", `rows={2}`, `resize-none`, `text-xs`
- Checkbox: "附上完整对话帮助排查" (includes full transcript + AI config)
- Buttons: "取消" (border), "提交" (primary, blue)
- Success state: Green checkmark + "感谢反馈!"

### Styling
- Container: `mt-2 flex items-center gap-1`
- Hidden by default: `opacity-0 transition-opacity group-hover/msgitem:opacity-100`
- Each button: `flex items-center gap-1.5 rounded px-2 py-1`
- Appears on hover of message item

---

## 3. SETTINGS MODAL (`SettingsModal.tsx`)

### Modal Structure
- Size: `h-[600px] max-w-4xl`
- Two-column layout with no gap between

**Left Sidebar (280px wide)**
- Background: `bg-muted/30`
- Border right: `border-border`
- Logo header (56px tall): Sage logo + "Sage" text
- Navigation list: Category buttons
  - Padding: `p-2`
  - Hover: `hover:bg-accent/50 hover:text-foreground`
  - Active: `bg-accent text-accent-foreground font-medium`
  - Each: `flex items-center gap-2.5 rounded-lg px-3 py-2`

**Right Content (flex-1)**
- Header: Category title (48px tall), centered
- Content area: `p-6 min-h-0 flex-1 overflow-y-auto`

### Settings Categories (10 tabs)

| ID | Label | Icon | Content |
|----|-------|------|---------|
| `account` | Account | `User` | User profile, login/logout |
| `general` | General | `Settings` | Language, theme, accent color, background style |
| `model` | Model | `Cpu` | AI provider selection, API key, model choice |
| `mcp` | MCP | `Server` | MCP server configuration |
| `skills` | Skills | `Sparkles` | Installed skills, enable/disable |
| `connector` | Connector | `Plug` | WeChat/Feishu connectors |
| `cron` | Cron | `Clock` | Scheduled tasks |
| `persona` | Persona | `Brain` | User persona memory settings |
| `data` | Data | `Database` | Export/import, cleanup |
| `about` | About | `Info` | Version, updates, changelog |

**Update Indicator**: Red dot (1.5×1.5px, `bg-red-500`) on "About" tab when update available

### General Settings Tab Details

**Language Dropdown**:
- Options: "English", "简体中文"
- Style: `h-10 max-w-xs`

**Theme Color Selection** (7 color circles):
1. **Orange** - `oklch(0.6716 0.1368 48.513)` / dark: `oklch(0.7214 0.1337 49.9802)`
2. **Blue** - `oklch(0.5469 0.1914 262.881)` / dark: `oklch(0.6232 0.1914 262.881)`
3. **Green** - `oklch(0.5966 0.1397 149.214)` / dark: `oklch(0.6489 0.1397 149.214)`
4. **Purple** - `oklch(0.5412 0.1879 293.541)` / dark: `oklch(0.6135 0.1879 293.541)`
5. **Pink** - `oklch(0.6171 0.1762 349.761)` / dark: `oklch(0.6894 0.1762 349.761)`
6. **Red** - `oklch(0.5772 0.2077 27.325)` / dark: `oklch(0.6495 0.2077 27.325)`
7. **Sage** - `oklch(0.4531 0.0891 152.535)` / dark: `oklch(0.5654 0.1091 152.535)`

- Active state: Ring around circle (2px), same color
- Hover: Scale up `hover:scale-110`
- Size: `size-10 rounded-full`

**Background Styles** (3 options):
1. Default - "Clean neutral background"
2. Warm - "Cozy cream and beige tones" (class: `bg-warm`)
3. Cool - "Crisp blue-gray tones" (class: `bg-cool`)

---

## 4. CHAT MESSAGE STYLING

### AI Response (`TextMessageItem.tsx`)

**Container**:
- Flexbox column: `flex min-w-0 flex-col gap-3`
- Group hover class: `group/msgitem`

**Logo/Avatar**:
- Component: `<Logo />`
- Appears above message content

**Markdown Content**:
- Wrapper: `prose prose-sm text-foreground max-w-none min-w-0 flex-1 overflow-hidden`
- `prose-sm` is Tailwind's small typography preset
- Customizations:
  - Inline code: `bg-muted rounded px-1.5 py-0.5 text-sm`
  - Code blocks: `bg-muted max-w-full overflow-x-auto rounded-lg p-4`
  - Links: `text-primary cursor-pointer hover:underline`
  - Tables: border-collapse with `border-border` lines
  - Table headers: `bg-muted`

**Artifacts**:
- Component: `<ArtifactRenderer artifacts={extractedArtifacts} />`
- Inserted between logo and markdown

**Action Bar**:
- Appears below content on hover
- Only if `cleanText.trim() || extractedArtifacts.length > 0`

### User Message (`UserMessage.tsx`)

**Container**:
- Flexbox row: `flex min-w-0 gap-3`
- Left spacer: `min-w-0 flex-1` (pushes bubble right)

**Bubble**:
- Background: `bg-accent/50`
- Padding: `px-4 py-3`
- Max width: `max-w-[85%]`
- Border: `rounded-xl`
- Text: `text-foreground text-sm`
- Wrapping: `whitespace-pre-wrap break-word`

**Attachments** (images/files):
- Container: `mb-2 flex flex-wrap gap-2`
- Images: `max-h-48 max-w-full`
- Files: `bg-muted flex items-center gap-2 rounded-lg px-3 py-2`
  - Icon: `FileText text-muted-foreground size-4`
  - Name: `text-foreground text-sm`

---

## 5. RUNNING INDICATOR (`RunningIndicator.tsx`)

### Display Format
- Spinner SVG (4×4px animated rotation, amber `#d97706`)
- Activity text (left of spinner)
- Font: `text-muted-foreground text-sm`

### Activity Messages by Phase/Tool
```
phase: 'planning' → "Planning execution..."
phase: 'executing', no tool → "Executing..."
phase: 'thinking', no tool → "Thinking..."
Bash → "Running command..."
Read → "Reading filename.ext..."
Write → "Writing filename.ext..."
Edit → "Editing filename.ext..."
Grep → "Searching..."
Glob → "Finding files..."
WebSearch → "Searching web..."
WebFetch → "Fetching page..."
Task → "Running subtask..."
```

### Styling
- Container: `flex items-center gap-2 py-2`
- SVG: `size-4 animate-spin` (cubic rotation)
- Circle opacity: `opacity-20`
- Path opacity: `opacity-80`

---

## 6. THEME SYSTEM (`theme-provider.tsx`)

### Available Themes
1. **"light"** - Light mode (manual)
2. **"dark"** - Dark mode (manual)
3. **"system"** - Follow OS preference (watches `prefers-color-scheme`)

### CSS Variable Application
When theme resolves:
```css
--primary: <color>
--ring: <color>
--sidebar-primary: <color>
--sidebar-ring: <color>
```

### Theme Application
- `document.documentElement.classList.add('dark')` for dark mode
- `document.documentElement.classList.remove('dark')` for light mode
- Background styles add classes: `bg-warm` or `bg-cool` (none for default)

### Theme Context API
```typescript
{
  theme: 'light' | 'dark' | 'system'
  resolvedTheme: 'light' | 'dark' (actual computed value)
  accentColor: AccentColor (orange|blue|green|purple|pink|red|sage)
  backgroundStyle: BackgroundStyle (default|warm|cool)
  setTheme(theme)
  setAccentColor(color)
  setBackgroundStyle(style)
}
```

### Persistence
- Saved in settings DB + localStorage
- Synced with Tauri window theme
- System preference changes trigger re-apply

---

## 7. LEFT SIDEBAR (`left-sidebar.tsx`)

### Two States: Expanded (288px) / Collapsed (56px)

#### EXPANDED STATE

**Header Section (56px)**:
- Flexbox: `flex items-center justify-between gap-3 p-4`
- Logo: 36×36px image
- Text: "Sage" monospace, `text-lg font-medium tracking-wide`
- Toggle button: `PanelLeft` icon, 32×32px

**Navigation Section (64px total)**:
- Single "New Task" item
- Icon: `SquarePen`
- Label: `t.nav.newTask`
- Style: full-width button, `rounded-lg px-3 py-2.5`

**Tasks Section** (flex-1, scrollable):
- Header: "ALL TASKS" (12px, `text-xs font-medium tracking-wider`, muted)
- Item count: Show first 10, "More" button if count > 10
- Each task item (56px tall):
  - Icon: Dynamic based on prompt content (Globe/Smartphone/Sparkles/FileText/Calendar)
  - Selected state: `bg-sidebar-accent text-sidebar-accent-foreground shadow-sm`
  - Hover state: `hover:bg-sidebar-accent/50 hover:text-sidebar-foreground`
  - Text: Truncated prompt, `text-sm`
  - Running indicator (collapsed): Green pulsing dot (top-right corner)
  - Dropdown menu: Star icon (if favorited, `fill-amber-400`) or 3-dot menu (hover)
    - Options: Favorite/Unfavorite, Rename, Delete (red)

**Bottom Section** (72px):
- Avatar with status badge (36×36px)
- User name: `text-sm font-medium` truncated
- Chevrons icon: `ChevronsUpDown`
- Update dot: Red (2×2px) at `top-1.5 left-[38px]` if update available
- Dropdown menu on click:
  - User info header (name + avatar)
  - Settings option (with optional update dot)
  - Separator
  - Log out (red text)

#### COLLAPSED STATE (56px)

**Logo Button**:
- 36×36px image, centered
- Hover expand behavior (shows "Sage" text on hover preview)

**Navigation Icons** (vertical stack, 40×40px each):
- New Task (`SquarePen`)
- Tasks list (hover popup)
- Tooltips: Show label on right

**Tasks Hover Popup**:
- Width: 320px
- Appears to right of icon with hover bridge
- Header: "ALL TASKS" with border
- Same task list as expanded (max 70vh height)
- Top margin: `ml-2`
- Border: `border-border/60`

**Avatar** (bottom):
- 32×32px
- Dropdown menu same as expanded

### Task Item Icons (Dynamic)
```
Contains "网站"|"website" → Globe
Contains "应用"|"app" → Smartphone
Contains "设计"|"design" → Sparkles
Contains "文档"|"doc" → FileText
Default → Calendar
```

### Task Item Dropdown Menu
- Favorite: Toggle star icon
- Rename: Edit icon + dialog
- Delete: Trash icon (red), shows confirmation dialog

### Rename Dialog
- Title: `t.common.rename`
- Input: Text field (autofocus)
- Buttons: Cancel (border), Confirm (primary, disabled if empty)
- Submit on Enter key

### Delete Confirmation Dialog
- Title: `t.common.deleteTaskConfirm`
- Description: `t.common.deleteTaskDescription`
- Buttons: Cancel (border), Delete (red)
- If deleting current task, navigate to home

### Mobile Adaptations
- Fixed overlay: `fixed inset-y-0 left-0 z-50 w-[85vw] max-w-[320px]`
- Closed: `-translate-x-full`
- Opened: `translate-x-0`
- Safe area padding: `pt-[var(--safe-area-top)]`
- Backdrop: Semi-transparent on open

### CSS Classes & Spacing
- Sidebar border: `border-sidebar-border`
- Background: `bg-sidebar`
- Text: `text-sidebar-foreground`
- Accent: `bg-sidebar-accent text-sidebar-accent-foreground`
- Spacing: `gap-0.5` between items, `p-2` to `p-4` sections

---

## 8. AVATAR STATUS BADGE (`avatar-status-badge`)

- Ring around avatar: `ring-sidebar`
- Green dot for online status
- Tooltip on hover (right side for collapsed sidebar)
- Component: `AvatarImage` with fallback icon

---

## 9. COLOR SYSTEM (TailwindCSS)

### Semantic Colors
```
foreground / text-foreground
background / bg-background
muted (secondary text) / text-muted-foreground
accent (highlights, active states) / bg-accent text-accent-foreground
primary (action buttons, links) / bg-primary text-primary-foreground
destructive (delete, errors) / text-destructive
border / border-border (subtle dividers)
input / border-input
ring / focus:ring-ring
```

### Sidebar-Specific Colors
```
bg-sidebar
text-sidebar-foreground
bg-sidebar-accent
text-sidebar-accent-foreground
border-sidebar-border
```

### Status Colors
```
Running: amber-500 (with pulse)
Success: emerald-500
Error: red-500
Warning: amber-500
Info: amber-500
```

---

## 10. TYPOGRAPHY & SPACING CONSTANTS

### Font Sizes
- `text-xs` - 12px (labels, captions)
- `text-sm` - 14px (body text)
- `text-base` - 16px (default)
- `text-lg` - 18px (headings)

### Font Weights
- Normal: 400
- Medium: 500
- Semibold: 600
- Bold: 700

### Icon Sizes
- `size-3` - 12×12px (small indicators)
- `size-4` - 16×16px (default)
- `size-5` - 20×20px (buttons)
- `size-8` - 32×32px (avatar)
- `size-9` - 36×36px (logo)
- `size-10` - 40×40px (nav items)

### Spacing (Tailwind)
- Gap: `gap-1.5`, `gap-2`, `gap-2.5`, `gap-3`
- Padding: `px-1.5`, `py-0.5`, `px-2 py-1`, `px-3 py-2`, `p-4`, `p-6`
- Margin: `mt-0.5`, `mt-1`, `mt-2`, `mt-4`
- Borders: `rounded` (4px), `rounded-lg` (8px), `rounded-xl` (12px)

---

## 11. ANIMATION & TRANSITIONS

- Button hover: `transition-colors` (200ms)
- Sidebar toggle: `transition-all duration-300`
- Opacity changes: `transition-opacity`
- Scale on hover: `hover:scale-110`
- Spinner: `animate-spin` (linear, continuous)
- Pulse: `animate-pulse` (2-second cycle)
- Running dot: `animate-ping` (background) + static dot (foreground)

---

## 12. RESPONSIVE BREAKPOINTS (Mobile)

- Mobile detection: `isMobile` from platform utils
- Sidebar becomes fixed drawer on mobile
- Safe area handling: `pt-[var(--safe-area-top)]`
- Max widths constrained: `max-w-[90vw]`, `max-w-[320px]`
- Overflow auto: `overflow-y-auto` on scrollable sections

---

## 13. INTERACTION PATTERNS

### Hover Groups
```
group/msgitem - Entire message item
  .group-hover/msgitem:opacity-100 - Action bar fades in
```

### Keyboard Support
- Enter key submits text input, confirmation dialogs
- Escape closes modals (via Radix UI Dialog)
- Tab navigation for accessibility

### Click Handlers
- `e.stopPropagation()` - Prevents bubbling on menu items
- `onClick` with loading states - Show spinner during async operations

---

## 14. KEY SWIFTUI MAPPING RECOMMENDATIONS

**Tool Execution Item**:
- Use `VStack` with `HStack` for line layout
- `@State` for modal presentation
- `Circle()` for bullet indicator with conditional color
- Implement expand/collapse via `.gesture` or sheet presentation

**Message Action Bar**:
- Use `HStack` with buttons
- `.opacity()` with `.onCursorEnter()` / `.onCursorExit()` for hover
- Popover for bug report form

**Settings Modal**:
- `NavigationStack` or `TabView` for category selection
- Two-column layout using `HStack { List + ScrollView }`
- Dynamic form fields based on category

**Chat Messages**:
- `VStack` for AI response
- `.background()` with accent color for user bubble (right-aligned)
- `MarkdownUI` or custom renderer for prose content

**Left Sidebar**:
- `NavigationStack` for routing
- `.offset()` or `GeometryReader` for collapse animation
- Custom scroll tracking for task list

**Theme System**:
- Use `.preferredColorScheme()` modifier
- Environment variable for theme state
- `@Environment(\.colorScheme)` for system detection

---

## 15. PRECISE CSS UTILITY REFERENCE

### Most Critical Classes for Replication

**Message Styling**:
```
prose prose-sm text-foreground max-w-none min-w-0 flex-1 overflow-hidden
prose-h1:text-xl prose-h1:font-semibold
prose-h2:text-lg prose-h2:font-semibold
```

**Tool Item**:
```
-mx-1 rounded-md px-1 py-1.5 font-mono text-[13px]
hover:bg-accent/50 cursor-pointer
```

**Buttons**:
```
flex items-center gap-1.5 rounded px-2 py-1 text-xs
text-muted-foreground hover:text-foreground hover:bg-muted
transition-colors
```

**Sidebar Navigation**:
```
flex w-full cursor-pointer items-center gap-2.5 rounded-lg px-3 py-2 text-sm
hover:bg-sidebar-accent/50 hover:text-sidebar-foreground
```

**Accent Colors (OKLCH format)**:
- Orange: `oklch(0.6716 0.1368 48.513)`
- Blue: `oklch(0.5469 0.1914 262.881)`

