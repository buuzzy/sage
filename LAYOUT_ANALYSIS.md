# Sage Frontend Layout Analysis - iOS Mobile Adaptation Planning

## Executive Summary

Sage is a web-based AI assistant with a **3-panel responsive layout** using Tailwind CSS. The layout is currently designed for desktop/tablet but has minimal mobile considerations. A successful iOS adaptation will require:

1. **Collapsible/stackable panels** (left sidebar → collapsed icon bar)
2. **Full-width single-panel mode** for phones
3. **Safe area padding** for notches & home indicators
4. **Touch-friendly spacing & interactions**
5. **Viewport & orientation handling**

---

## 1. LEFT SIDEBAR LAYOUT (src/components/layout/left-sidebar.tsx)

### Current Structure

```jsx
<aside
  className={cn(
    'border-sidebar-border bg-sidebar flex h-full shrink-0 flex-col border-none transition-all duration-300',
    leftOpen ? 'w-72' : 'w-14'  // ← EXPANDABLE/COLLAPSIBLE
  )}
>
```

### Key Properties

| Property | Desktop | Mobile |
|----------|---------|--------|
| **Expanded Width** | `w-72` (288px) | Hidden/Offscreen |
| **Collapsed Width** | `w-14` (56px) | Hamburger icon bar (44px for touch) |
| **Height** | `h-full` (100vh) | `h-screen` |
| **Transition** | `duration-300` smooth | Same (OK) |
| **Border** | `border-none` | OK |
| **Flex Direction** | `flex-col` | OK |
| **Overflow** | None visible | Tasks need scroll |

### Expanded State Content
```
1. Logo + Toggle button (56px header)
   - Sage logo (9×9)
   - Logo text "Sage" 
   - PanelLeft toggle button

2. Navigation (varies)
   - "New Task" button (SquarePen icon)

3. Tasks Section (flex-1, scrollable)
   - "ALL TASKS" header (shrink-0)
   - Task list (flex-1 overflow-y-auto)
     - max 10 tasks shown
     - "More" link to /library

4. Bottom Section (shrink-0)
   - User avatar + dropdown
   - Settings link
   - Logout button
   - Update indicator (red dot)
```

### State Management
- **Context**: `sidebar-context.tsx`
- **Hook**: `useSidebar()`
- **State**:
  - `leftOpen: boolean` (default: `true`)
  - `toggleLeft()` function
  - `setLeftOpen(open: boolean)` function

### Responsive Behavior Existing

**Only ONE responsive class found:**
```jsx
<button
  className="text-muted-foreground hover:bg-accent hover:text-foreground flex cursor-pointer items-center justify-center rounded-lg p-2 transition-colors duration-200 md:hidden"
>
```
- **md:hidden** = Sidebar toggle button HIDDEN on medium screens and up
- This suggests mobile intent but not fully implemented

### CSS Classes to Know

**Sidebar Colors** (CSS variables in theme.css):
```css
--sidebar: oklch(0.967 0.0029 264.5419);              /* light gray */
--sidebar-foreground: oklch(0.2101 0.0318 264.6645);  /* dark gray */
--sidebar-accent: oklch(1 0 0);                        /* white */
--sidebar-accent-foreground: oklch(0.2101 0.0318 264.6645); /* dark */
--sidebar-border: oklch(0.9276 0.0058 264.5313);      /* light border */
```

**Dark Mode Sidebar:**
```css
.dark {
  --sidebar: oklch(0.1822 0 0);              /* dark */
  --sidebar-foreground: oklch(0.8109 0 0);   /* light text */
  --sidebar-accent: oklch(0.3211 0 0);       /* dark gray accent */
}
```

---

## 2. TASK DETAIL PAGE LAYOUT (src/app/pages/TaskDetail.tsx)

### Overall Structure

```jsx
<div className="bg-sidebar flex h-screen overflow-hidden">
  {/* Left Sidebar */}
  <LeftSidebar ... />

  {/* Main Content Area */}
  <div ref={containerRef} className="bg-background my-2 mr-2 flex min-w-0 flex-1 overflow-hidden rounded-2xl shadow-sm">
    {/* Left Panel - Chat */}
    <div className="bg-background flex min-w-0 flex-col overflow-hidden...">
      {/* Header */}
      <header className="border-border/50 bg-background z-10 flex shrink-0 items-center gap-2 border-none px-4 py-3">
      
      {/* Messages Container */}
      <div ref={messagesContainerRef} className="scrollbar-soft relative flex-1 overflow-x-hidden overflow-y-auto">
      
      {/* Chat Input */}
      <div className="border-border/50 bg-background relative shrink-0 border-none">
    </div>

    {/* Divider (Preview) */}
    {isPreviewVisible && <div className="bg-border/50 w-px shrink-0" />}

    {/* Middle Panel - Artifact Preview (conditional) */}
    {isPreviewVisible && (
      <div className="bg-muted/10 flex min-w-0 flex-1 flex-col overflow-hidden">
        <ArtifactPreview ... />
      </div>
    )}

    {/* Divider (Sidebar) */}
    <div className="bg-border/50 shrink-0 transition-all duration-300" style={{width: isRightSidebarVisible ? 'w-px' : 'w-0'}} />

    {/* Right Panel - Progress/Artifacts/Context (fixed width) */}
    <div className={cn(
      'bg-background flex shrink-0 flex-col overflow-hidden rounded-r-2xl transition-all duration-300',
      isRightSidebarVisible ? 'w-[280px]' : 'w-0'
    )}>
      <RightSidebar ... />
    </div>
  </div>
</div>
```

### Layout Flex Strategy

| Panel | Flex Property | Width | Behavior |
|-------|---|---|---|
| **Left Sidebar** | `shrink-0` | `w-72` or `w-14` | Fixed, collapsible |
| **Main Chat Area** | `flex-1` | Auto | Fills available space |
| **Message Container** | `flex-1` | Auto | Scrollable |
| **Chat Input** | `shrink-0` | Auto | Fixed height (grows with content) |
| **Preview Panel** | `flex-1` | `clamp(320px, 40%, 500px)` | Conditional, fluid |
| **Right Sidebar** | `shrink-0` | `w-[280px]` or `w-0` | Fixed width or hidden |
| **Dividers** | `shrink-0` | `w-px` or `w-0` | Toggle visibility |

### Header Structure

```jsx
<header className="border-border/50 bg-background z-10 flex shrink-0 items-center gap-2 border-none px-4 py-3">
  {/* Toggle Left Sidebar Button */}
  <button className="... md:hidden">
    <PanelLeft className="size-5" />
  </button>

  {/* Title Section */}
  <div className="group/title flex min-w-0 flex-1 items-center gap-1">
    <h1 className="text-foreground inline-block max-w-full truncate px-2 py-1 text-sm font-normal">
      {displayTitle.slice(0, 40) || `Task ${taskId}`}
    </h1>
    <button className="... opacity-0 group-hover/title:opacity-100">
      <Pencil className="size-3.5" />
    </button>
  </div>

  {/* Running Indicator */}
  {isRunning && <span className="text-primary flex items-center gap-2 text-sm">...</span>}

  {/* Toggle Right Sidebar Button */}
  <button className="...">
    <PanelLeft className="size-4 rotate-180" />
  </button>
</header>
```

### Messages Area

```jsx
<div ref={messagesContainerRef} className={cn(
  'scrollbar-soft relative flex-1 overflow-x-hidden overflow-y-auto',
  !isPreviewVisible && !isRightSidebarVisible && 'flex justify-center'
)}>
  <div className={cn(
    'w-full px-6 pt-4 pb-24',
    !isPreviewVisible && !isRightSidebarVisible && 'max-w-[800px]'
  )}>
    {/* Messages content */}
  </div>
</div>
```

**Key Features:**
- **Centering**: When sidebars hidden, messages are centered (flex justify-center)
- **Max Width**: `max-w-[800px]` when sidebars hidden (readability on wide screens)
- **Padding**: `px-6 pt-4 pb-24` (bottom padding for input)
- **Scroll**: `overflow-y-auto` with `.scrollbar-soft` class
- **Scrollbar Style**: Thin, transparent track, subtle thumb

### Chat Input Area

```jsx
<div className={cn(
  'border-border/50 bg-background relative shrink-0 border-none',
  !isPreviewVisible && !isRightSidebarVisible && 'flex justify-center'
)}>
  <div className={cn(
    'w-full px-4 py-3',
    !isPreviewVisible && !isRightSidebarVisible && 'max-w-[800px]'
  )}>
    <ChatInput
      variant="reply"
      placeholder={t.home.reply}
      isRunning={isRunning}
      onSubmit={handleReply}
      onStop={stopAgent}
      defaultMode={initialMode}
      currentTokens={calculateCurrentTokens()}
      contextLimit={getContextLimit()}
      showContextRing
    />
  </div>
</div>
```

---

## 3. CHAT INPUT COMPONENT (src/components/shared/ChatInput.tsx)

### Structure - Home Variant

```jsx
<div ref={containerRef} className={cn(
  'relative w-full transition-colors',
  isHome
    ? 'border-border/50 bg-background rounded-2xl border p-4 shadow-lg'
    : 'border-border/60 bg-background rounded-xl border p-3 shadow-sm',
  isDragging && 'border-primary/50 bg-primary/5 border-2'
)}>
  {/* File Input (hidden) */}
  <input type="file" multiple accept="..." />

  {/* Attachment Preview */}
  {attachments.length > 0 && (
    <div className="mb-3 flex flex-wrap gap-2">
      {/* Each attachment shows as thumbnail or file icon */}
    </div>
  )}

  {/* Textarea */}
  <textarea
    ref={textareaRef}
    value={value}
    className={cn(
      'text-foreground placeholder:text-muted-foreground w-full resize-none border-0 bg-transparent focus:outline-none',
      isHome ? 'text-base' : 'px-1 text-sm'
    )}
    style={{
      minHeight: isHome ? '56px' : '20px',
      maxHeight: isHome ? '200px' : '120px',
      overflowY: 'hidden'
    }}
  />

  {/* Bottom Actions */}
  <div className={cn('flex items-center justify-between', isHome ? 'mt-3' : 'mt-2')}>
    {/* Left: Add Button + Mode Selector */}
    <div className="flex items-center gap-2">
      {/* Add Files Button (+ button) */}
      <DropdownMenu modal={false}>
        <DropdownMenuTrigger className={cn(
          'flex shrink-0 items-center justify-center transition-colors',
          isHome ? 'border-border bg-background text-muted-foreground hover:bg-accent hover:text-foreground size-8 rounded-full border'
                 : 'text-muted-foreground hover:bg-accent hover:text-foreground size-7 rounded-md'
        )}>
          <Plus className={isHome ? 'size-4' : 'size-4'} />
        </DropdownMenuTrigger>
        <DropdownMenuContent align="start" sideOffset={8}>
          <DropdownMenuItem onSelect={openFilePicker}>
            <Paperclip className="size-4" />
            <span>{t.home.addFilesOrPhotos}</span>
          </DropdownMenuItem>
        </DropdownMenuContent>
      </DropdownMenu>

      {/* Mode Selector (Auto/Chat/Task) */}
      <DropdownMenu modal={false}>
        <DropdownMenuTrigger className={cn(
          'flex shrink-0 items-center gap-1 rounded-full border transition-colors',
          'border-border bg-background text-muted-foreground hover:bg-accent hover:text-foreground',
          isHome ? 'h-8 px-2.5 text-xs' : 'h-7 px-2 text-xs'
        )}>
          {/* Icon based on mode */}
          <span>{/* Mode text */}</span>
        </DropdownMenuTrigger>
        <DropdownMenuContent align="start" sideOffset={8}>
          {/* Radio options */}
        </DropdownMenuContent>
      </DropdownMenu>

      {/* Category Tag (if present) */}
      {categoryTag && <span className="...">...</span>}
    </div>

    {/* Right: Context Ring + Submit/Stop Button */}
    <div className="flex items-center gap-1">
      {showContextRing && !isHome && (
        <ContextUsageRing ... />
      )}
      {isRunning ? (
        <button className="..."><Square /></button>
      ) : (
        <button className="..." disabled={!canSubmit}>
          {isHome ? <ArrowUp /> : <Send />}
        </button>
      )}
    </div>
  </div>
</div>
```

### Home Variant Sizing

| Element | Size |
|---------|------|
| **Outer Container** | `rounded-2xl border p-4 shadow-lg` |
| **Textarea Min Height** | `56px` |
| **Textarea Max Height** | `200px` |
| **+ Button** | `size-8` (32px) `rounded-full` |
| **Mode Button** | `h-8 px-2.5 text-xs` |
| **Text Size** | `text-base` |
| **Bottom Margin** | `mt-3` |

### Reply Variant Sizing

| Element | Size |
|---------|------|
| **Outer Container** | `rounded-xl border p-3 shadow-sm` |
| **Textarea Min Height** | `20px` |
| **Textarea Max Height** | `120px` |
| **+ Button** | `size-7` (28px) `rounded-md` |
| **Mode Button** | `h-7 px-2 text-xs` |
| **Text Size** | `text-sm` |
| **Bottom Margin** | `mt-2` |

### Attachment Preview

```jsx
<div className="mb-3 flex flex-wrap gap-2">
  {attachments.map(attachment => (
    <div key={attachment.id} className="group border-border/50 bg-muted/50 relative flex items-center gap-2 rounded-lg border px-3 py-2">
      {attachment.type === 'image' && attachment.preview ? (
        <img src={attachment.preview} alt={...} className="h-10 w-10 rounded object-cover" />
      ) : (
        <div className="bg-muted flex h-10 w-10 items-center justify-center rounded">
          <FileText className="text-muted-foreground h-5 w-5" />
        </div>
      )}
      <span className="text-foreground max-w-[120px] truncate text-sm">
        {attachment.file.name}
      </span>
      <button className="... absolute -top-2 -right-2 flex h-5 w-5 items-center justify-center rounded-full opacity-0 group-hover:opacity-100">
        <X className="h-3 w-3" />
      </button>
    </div>
  ))}
</div>
```

**Attachment Sizing:**
- Thumbnail: `h-10 w-10` (40×40px)
- File icon: `h-5 w-5` (20×20px)
- Close button: `h-5 w-5` positioned absolutely `top-2 right-2`

---

## 4. HOME PAGE LAYOUT (src/app/pages/Home.tsx)

### Structure

```jsx
<div className="bg-sidebar flex h-screen overflow-hidden">
  {/* Left Sidebar */}
  <LeftSidebar tasks={tasks} ... />

  {/* Main Content */}
  <div className="bg-background my-2 mr-2 flex min-w-0 flex-1 flex-col overflow-hidden rounded-2xl shadow-sm">
    {/* Content Area - Vertically Centered */}
    <div className="flex flex-1 flex-col items-center justify-center overflow-auto px-4">
      <div className="flex w-full max-w-2xl flex-col items-center gap-6">
        {/* Title */}
        <h1 className="text-foreground text-center font-serif text-4xl font-normal tracking-tight md:text-5xl">
          {t.home.welcomeTitle}
        </h1>

        {/* Input Box */}
        <ChatInput
          variant="home"
          placeholder={activeCategoryData?.placeholder ?? t.home.inputPlaceholder}
          onSubmit={handleSubmit}
          className="w-full"
          autoFocus
          externalValue={pendingPrompt}
          categoryTag={...}
        />

        {/* Category Buttons / Prompt List */}
        {activeCategory && activeCategoryData ? (
          <div className="w-full">
            <div className="border-border divide-border divide-y rounded-xl border">
              {activeCategoryData.prompts.map(prompt => (
                <button
                  key={index}
                  className="text-foreground hover:bg-accent group flex w-full items-center justify-between gap-3 px-4 py-3.5 text-left text-sm transition-colors first:rounded-t-xl last:rounded-b-xl"
                >
                  <span className="truncate">{prompt}</span>
                  <ArrowUpRight className="text-muted-foreground group-hover:text-foreground size-4 shrink-0 transition-colors" />
                </button>
              ))}
            </div>
          </div>
        ) : (
          <div className="flex flex-wrap items-center justify-center gap-3">
            {categoryKeys.map(key => (
              <button
                key={key}
                className="border-border bg-background text-muted-foreground flex items-center gap-2 rounded-full border px-4 py-2 text-sm transition-colors hover:bg-accent hover:text-foreground"
              >
                {categoryIcons[key]}
                <span>{categories[key].label}</span>
              </button>
            ))}
          </div>
        )}
      </div>
    </div>
  </div>
</div>
```

### Home Page Sizing

| Element | Size |
|---------|------|
| **Main Title** | `text-4xl md:text-5xl` |
| **Content Max Width** | `max-w-2xl` (896px) |
| **Content Padding** | `px-4` |
| **Content Gap** | `gap-6` |
| **ChatInput** | `w-full` |
| **Category Buttons** | `gap-3` spacing |
| **Prompt List Item** | `px-4 py-3.5 text-sm` |

### Responsive Classes on Home

```jsx
<h1 className="... text-4xl md:text-5xl">
```
- **md:text-5xl** = Larger title on medium screens and up

---

## 5. SIDEBAR CONTEXT STATE MANAGEMENT (src/components/layout/sidebar-context.tsx)

### Context Interface

```tsx
interface SidebarContextType {
  leftOpen: boolean;
  rightOpen: boolean;
  toggleLeft: () => void;
  toggleRight: () => void;
  setLeftOpen: (open: boolean) => void;
  setRightOpen: (open: boolean) => void;
}
```

### Default State

```tsx
const [leftOpen, setLeftOpen] = useState(true);  // ← Starts OPEN
const [rightOpen, setRightOpen] = useState(true); // ← Starts OPEN
```

### Usage Pattern

```tsx
const { toggleLeft, setLeftOpen } = useSidebar();

// Auto-collapse left sidebar when preview opens
useEffect(() => {
  if (isPreviewVisible) {
    setLeftOpen(false);
  }
}, [isPreviewVisible, setLeftOpen]);
```

---

## 6. GLOBAL CSS & TAILWIND CONFIGURATION

### Global Styles (src/config/style/global.css)

```css
@import 'tailwindcss';
@import './theme.css';

@custom-variant dark (&:is(.dark *));
@plugin 'tailwindcss-animate';
@plugin '@tailwindcss/typography';

@layer base {
  * {
    @apply border-border outline-ring/50;
    scrollbar-width: thin;
    scrollbar-color: rgba(0, 0, 0, 0.15) transparent;
  }
  .dark * {
    scrollbar-color: rgba(255, 255, 255, 0.15) transparent;
  }
  body {
    @apply bg-background text-foreground;
  }
}

/* Scrollbar styling for webkit browsers */
::-webkit-scrollbar {
  width: 6px;
  height: 6px;
}
::-webkit-scrollbar-track {
  background: transparent;
}
::-webkit-scrollbar-thumb {
  background-color: rgba(0, 0, 0, 0.15);
  border-radius: 999px;
}

/* Utility classes */
.scrollbar-hide { display: none; }
.scrollbar-soft { scrollbar-color: rgba(0, 0, 0, 0.25) transparent; }
.container { @apply mx-auto max-w-7xl px-4 md:px-8; }
```

### Theme Colors (src/config/style/theme.css)

```css
:root {
  --background: oklch(1 0 0);              /* white */
  --foreground: oklch(0.2101 0.0318 264.6645); /* dark blue-gray */
  --primary: oklch(0.6716 0.1368 48.513);  /* orange/amber */
  --muted: oklch(0.967 0.0029 264.5419);   /* very light gray */
  --border: oklch(0.9276 0.0058 264.5313); /* light gray border */
  --accent: oklch(0.9491 0 0);             /* off-white */
  /* ... more colors ... */
}

.dark {
  --background: oklch(0.1797 0.0043 308.1928); /* very dark gray/blue */
  --foreground: oklch(0.8109 0 0);             /* light text */
  --primary: oklch(0.7214 0.1337 49.9802);     /* bright orange */
  --accent: oklch(0.3211 0 0);                 /* dark gray accent */
  /* ... more dark mode colors ... */
}
```

### Tailwind Breakpoints (Default)

```
sm: 640px   (phones)
md: 768px   (tablets)
lg: 1024px  (desktops)
xl: 1280px  (large screens)
2xl: 1536px (very large)
```

### No Safe Area Implementation

**Current:** NO safe-area padding for notches, home indicators, or dynamic island
- **Missing**: `padding-safe`, `safe-area-inset-*`, or `env()` CSS variables
- **Missing**: `viewport-fit=cover` meta tag handling

---

## 7. RESPONSIVE UTILITIES & MEDIA QUERIES FOUND

### Existing `@media` Queries in Layout Files

**VERY LIMITED - Only 1 responsive class in layout files:**

```jsx
// TaskDetail.tsx - Header toggle button
<button className="... md:hidden">
  <PanelLeft className="size-5" />
</button>
```

**This means:**
- Button is HIDDEN on `md` (768px) and larger screens
- Button is VISIBLE on phones (`sm` and below 768px)
- This is the ONLY responsive breakpoint in core layout files

### Tailwind Responsive Modifiers Used Elsewhere

```jsx
// Home.tsx - Title sizing
<h1 className="... text-4xl md:text-5xl">

// ChatInput.tsx - Sidebar max-width constraint
className={cn(
  'w-full px-6 pt-4 pb-24',
  !isPreviewVisible && !isRightSidebarVisible && 'max-w-[800px]'
)}
```

### CSS Scrollbar Classes

```css
.scrollbar-hide   /* Hide scrollbar completely */
.scrollbar-blend  /* Blend into background */
.scrollbar-soft   /* Light, subtle scrollbar */
```

---

## 8. KEY METRICS FOR iOS ADAPTATION

### Current Desktop Layout Widths

| Component | Width |
|-----------|-------|
| Left Sidebar (Expanded) | 288px (w-72) |
| Left Sidebar (Collapsed) | 56px (w-14) |
| Right Sidebar | 280px (w-[280px]) |
| Main Chat Area Min | 320px |
| Preview Panel | 320px–500px (40% of width) |
| Chat Input Min Height | 20px (reply) / 56px (home) |
| Chat Input Max Height | 120px (reply) / 200px (home) |

### Tailwind Sizes in Use

```
size-2 = 8px   (ping indicators)
size-3 = 12px  (small icons)
size-3.5 = 14px (small pencil icon)
size-4 = 16px   (common icon)
size-5 = 20px   (medium icon)
size-6 = 24px   (buttons)
size-7 = 28px   (+ button reply)
size-8 = 32px   (+ button home)
size-9 = 36px   (avatar)
size-10 = 40px  (attachment thumbnail)
```

### Spacing Used

```
gap-1 = 4px
gap-2 = 8px
gap-3 = 12px
gap-6 = 24px
px-2 = 8px left-right
px-3 = 12px left-right
px-4 = 16px left-right
px-6 = 24px left-right
py-2 = 8px top-bottom
py-3 = 12px top-bottom
py-3.5 = 14px top-bottom
```

---

## 9. CRITICAL LAYOUT FEATURES FOR iOS

### Auto-Layout Dependencies

1. **Left sidebar auto-closes when preview opens** (TaskDetail.tsx line 212-216)
```jsx
useEffect(() => {
  if (isPreviewVisible) {
    setLeftOpen(false);
  }
}, [isPreviewVisible, setLeftOpen]);
```

2. **Right sidebar auto-expands when artifacts available** (TaskDetail.tsx line 264-300)
```jsx
useEffect(() => {
  if (isLoading) return;
  if (!task || task.id !== taskId) return;
  if (hasAutoExpandedRef.current) return;
  
  const hasContent = hasArtifacts || (hasWorkspace && hasFileOps) || hasMcpTools || hasSkills;
  if (hasContent) {
    setIsRightSidebarVisible(true);
    hasAutoExpandedRef.current = true;
  }
}, [artifacts.length, messages, workingDir, isLoading, task, taskId]);
```

3. **Messages center when no sidebars** (TaskDetail.tsx line 1015)
```jsx
{!isPreviewVisible && !isRightSidebarVisible && 'flex justify-center'}
```

### Dynamic Panel Sizing

**Chat panel flex logic:**
```jsx
style={{
  flex: isPreviewVisible ? '0 0 auto' : '1 1 0%',
  width: isPreviewVisible ? 'clamp(320px, 40%, 500px)' : undefined,
  minWidth: '320px',
  maxWidth: isPreviewVisible ? '500px' : undefined,
}}
```

---

## 10. VIEWPORT META TAG

**Current (index.html):**
```html
<meta name="viewport" content="width=device-width, initial-scale=1.0" />
```

**Needed for iOS notch support:**
```html
<meta name="viewport" content="width=device-width, initial-scale=1.0, viewport-fit=cover" />
```

---

## Summary: What Needs to Change for iOS

| Aspect | Current | iOS Needed |
|--------|---------|-----------|
| **Sidebar Layout** | Left sidebar always visible (w-14 collapsed) | Overlay drawer or full hidden on phone |
| **Safe Areas** | None | Add env() safe-area-inset for notch |
| **Touch Targets** | 24px–32px buttons | Minimum 44×44px for iOS |
| **Responsive** | Only `md:hidden` | Full sm/md/lg breakpoint strategy |
| **Viewport** | Standard | Add `viewport-fit=cover` |
| **Gestures** | Hover/click only | Swipe, long-press support |
| **Modal/Drawer** | Popover UI | Native modal with safe insets |
| **Input Keyboard** | No spacing | Keyboard height handling |
| **Panel Widths** | Fixed 280-500px | Fluid 100vw–clamp() based |
| **Scroll Behavior** | momentum scroll | Momentum + safe edges |

