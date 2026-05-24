import SwiftUI

/// 侧边栏 — Gemini 风格轻抽屉
/// 顶部：品牌 + 设置入口
/// 中间：按日期分组的历史对话列表（今天/昨天/更早）
/// 底部：新对话 FAB
/// 支持：右滑删除、长按重命名
struct SidebarView: View {
    let sessions: [SessionItem]
    let onSelectSession: (String) -> Void
    let onNewChat: () -> Void
    let onDeleteSession: (String) -> Void
    let onRenameSession: (String, String) -> Void
    let onOpenSettings: () -> Void
    var runningSessionId: String? = nil // 正在运行的对话 ID

    @EnvironmentObject var settingsService: SettingsService
    @AppStorage("sage_theme") private var theme: String = "system"
    @State private var renamingSession: SessionItem? = nil
    @State private var renameText = ""

    /// SF Symbol that mirrors the active appearance mode.
    private var themeIconName: String {
        switch theme {
        case "light": return "sun.max.fill"
        case "dark": return "moon.fill"
        default: return "circle.lefthalf.filled"
        }
    }

    private var themeAccessibilityValue: String {
        switch theme {
        case "light": return "浅色"
        case "dark": return "深色"
        default: return "跟随系统"
        }
    }

    /// Cycle light → dark → system → light.
    /// Persist into SettingsService too so the AppSettings JSON stays in sync.
    private func cycleTheme() {
        let next: String
        switch theme {
        case "light": next = "dark"
        case "dark": next = "system"
        default: next = "light"
        }
        theme = next
        settingsService.currentSettings.theme = next
        settingsService.save()
    }

    // MARK: - Date Groups

    private var todaySessions: [SessionItem] {
        sessions.filter { Calendar.current.isDateInToday($0.createdAt) }
    }

    private var yesterdaySessions: [SessionItem] {
        sessions.filter { Calendar.current.isDateInYesterday($0.createdAt) }
    }

    private var olderSessions: [SessionItem] {
        sessions.filter {
            !Calendar.current.isDateInToday($0.createdAt) && !Calendar.current.isDateInYesterday($0.createdAt)
        }
    }

    var body: some View {
        ZStack {
            // Solid base — keeps the sidebar fully opaque so it never bleeds the
            // chat content underneath. SageBackground sits on top as a thin tint.
            SageTheme.ColorToken.surface
                .ignoresSafeArea()
            SageBackground()

            VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack {
                HStack(spacing: SageTheme.Spacing.sm) {
                    Image("SageLogo")
                        .resizable()
                        .scaledToFill()
                        .frame(width: 34, height: 34)
                        .clipShape(RoundedRectangle(cornerRadius: SageTheme.Radius.sm, style: .continuous))
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Sage")
                            .font(SageTheme.Typography.title)
                        Text("金融助手")
                            .font(SageTheme.Typography.rowSubtitle)
                            .foregroundColor(SageTheme.ColorToken.mutedText)
                    }
                }
                Spacer()
                Button(action: cycleTheme) {
                    Image(systemName: themeIconName)
                        .font(.system(size: 17, weight: .medium))
                        .foregroundColor(SageTheme.ColorToken.iconNeutral)
                        .frame(width: 40, height: 40)
                        .background(SageTheme.ColorToken.iconNeutralBackground)
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text("外观"))
                .accessibilityValue(Text(themeAccessibilityValue))
            }
            .padding(.horizontal, SageTheme.Spacing.lg)
            .padding(.top, SageTheme.Spacing.lg)
            .padding(.bottom, SageTheme.Spacing.md)

            Button(action: onNewChat) {
                HStack(spacing: SageTheme.Spacing.sm) {
                    Image(systemName: "plus.message.fill")
                        .font(.system(size: 15, weight: .semibold))
                    Text("新对话")
                        .font(SageTheme.Typography.button)
                    Spacer()
                }
                .foregroundColor(.white)
                .padding(.horizontal, SageTheme.Spacing.md)
                .frame(minHeight: 48)
                .background(SageTheme.ColorToken.brand)
                .clipShape(RoundedRectangle(cornerRadius: SageTheme.Radius.md, style: .continuous))
            }
            .buttonStyle(SagePlainRowButtonStyle())
            .padding(.horizontal, SageTheme.Spacing.md)
            .padding(.bottom, SageTheme.Spacing.sm)

            // Session list (grouped by date)
            if sessions.isEmpty {
                VStack(spacing: 12) {
                    Spacer()
                    SageEmptyStateView(
                        systemName: "bubble.left.and.bubble.right",
                        title: "暂无对话",
                        message: "开始一次新的市场研究或复盘。"
                    )
                    Spacer()
                }
                .frame(maxWidth: .infinity)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        // 今天
                        if !todaySessions.isEmpty {
                            sectionHeader("今天")
                            ForEach(todaySessions) { session in
                                sessionRow(session)
                            }
                        }

                        // 昨天
                        if !yesterdaySessions.isEmpty {
                            sectionHeader("昨天")
                            ForEach(yesterdaySessions) { session in
                                sessionRow(session)
                            }
                        }

                        // 更早
                        if !olderSessions.isEmpty {
                            sectionHeader("更早")
                            ForEach(olderSessions) { session in
                                sessionRow(session)
                            }
                        }
                    }
                }
            }

            Spacer()

            Button(action: onOpenSettings) {
                HStack(spacing: SageTheme.Spacing.sm) {
                    SageSymbolIcon(systemName: "gearshape", tone: .neutral, size: 16, containerSize: 32)
                    Text("设置与账号")
                        .font(SageTheme.Typography.rowTitleEmphasized)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(SageTheme.ColorToken.mutedText.opacity(0.42))
                }
                .foregroundColor(.primary)
                .padding(.horizontal, SageTheme.Spacing.sm)
                .frame(minHeight: 56)
                .sageGlassControl(cornerRadius: SageTheme.Radius.md)
            }
            .buttonStyle(SagePlainRowButtonStyle())
            .padding(.horizontal, SageTheme.Spacing.md)
            .padding(.bottom, SageTheme.Spacing.lg)
            }
        }
        .alert("重命名对话", isPresented: .init(
            get: { renamingSession != nil },
            set: { if !$0 { renamingSession = nil } }
        )) {
            TextField("对话标题", text: $renameText)
            Button("取消", role: .cancel) { renamingSession = nil }
            Button("确定") {
                if let session = renamingSession, !renameText.isEmpty {
                    onRenameSession(session.id, renameText)
                }
                renamingSession = nil
            }
        } message: {
            Text("请输入新的对话标题")
        }
    }

    // MARK: - Section Header

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(SageTheme.Typography.section)
            .foregroundColor(SageTheme.ColorToken.mutedText)
            .tracking(0.3)
            .padding(.horizontal, SageTheme.Spacing.lg)
            .padding(.top, 16)
            .padding(.bottom, 6)
    }

    // MARK: - Session Row (swipe to delete + long press menu)

    private func sessionRow(_ session: SessionItem) -> some View {
        Button {
            onSelectSession(session.id)
        } label: {
            HStack(spacing: SageTheme.Spacing.sm) {
                // 运行中绿色脉冲点
                if session.id == runningSessionId {
                    Circle()
                        .fill(SageIconTone.success.foreground)
                        .frame(width: 8, height: 8)
                        .overlay(
                            Circle()
                                .stroke(SageIconTone.success.foreground.opacity(0.4), lineWidth: 2)
                                .scaleEffect(1.5)
                        )
                        .frame(width: 32, height: 32)
                } else {
                    SageSymbolIcon(systemName: "bubble.left", tone: .neutral, size: 14, containerSize: 32)
                }

                Text(session.title)
                    .font(SageTheme.Typography.rowTitle)
                    .foregroundColor(.primary)
                    .lineLimit(1)

                Spacer()
            }
            .padding(.horizontal, SageTheme.Spacing.sm)
            .frame(minHeight: 52)
            .background(
                RoundedRectangle(cornerRadius: SageTheme.Radius.sm, style: .continuous)
                    .fill(session.id == runningSessionId ? SageTheme.ColorToken.brandSoft.opacity(0.75) : Color.clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(SagePlainRowButtonStyle())
        .padding(.horizontal, SageTheme.Spacing.xs)
        .contextMenu {
            Button {
                renamingSession = session
                renameText = session.title
            } label: {
                Label("重命名", systemImage: "pencil")
            }
            Button(role: .destructive) {
                onDeleteSession(session.id)
            } label: {
                Label("删除", systemImage: "trash")
            }
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            Button(role: .destructive) {
                onDeleteSession(session.id)
            } label: {
                Label("删除", systemImage: "trash")
            }
        }
    }
}
