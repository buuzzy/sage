import SwiftUI

enum SageTheme {
    enum Spacing {
        static let xxs: CGFloat = 4
        static let xs: CGFloat = 8
        static let sm: CGFloat = 12
        static let md: CGFloat = 16
        static let lg: CGFloat = 20
        static let xl: CGFloat = 24
        static let xxl: CGFloat = 32
    }

    enum Typography {
        static let title = Font.system(.title3, design: .default, weight: .semibold)
        static let section = Font.system(.footnote, design: .default, weight: .semibold)
        static let rowTitle = Font.system(.body, design: .default, weight: .regular)
        static let rowTitleEmphasized = Font.system(.body, design: .default, weight: .medium)
        static let rowSubtitle = Font.system(.footnote, design: .default, weight: .regular)
        static let caption = Font.system(.caption, design: .default, weight: .regular)
        static let button = Font.system(.subheadline, design: .default, weight: .semibold)
        static let mono = Font.system(.footnote, design: .monospaced, weight: .regular)
    }

    enum Radius {
        static let sm: CGFloat = 10
        static let md: CGFloat = 16
        static let lg: CGFloat = 22
        static let pill: CGFloat = 30
    }

    enum ColorToken {
        private static func adaptive(light: UIColor, dark: UIColor) -> Color {
            Color(UIColor { traits in
                traits.userInterfaceStyle == .dark ? dark : light
            })
        }

        private static func uiColor(_ red: CGFloat, _ green: CGFloat, _ blue: CGFloat, _ alpha: CGFloat = 1) -> UIColor {
            UIColor(red: red / 255, green: green / 255, blue: blue / 255, alpha: alpha)
        }

        static let brand = Color(red: 0.18, green: 0.43, blue: 0.96)
        static let brandSoft = adaptive(light: uiColor(224, 237, 255), dark: uiColor(30, 30, 32))
        static let cyan = Color(red: 0.13, green: 0.63, blue: 0.73)
        static let surface = adaptive(light: .systemBackground, dark: uiColor(0, 0, 0))
        static let surfaceSecondary = adaptive(light: .secondarySystemBackground, dark: uiColor(23, 23, 23))
        static let surfaceElevated = adaptive(light: .tertiarySystemBackground, dark: uiColor(32, 32, 34))
        static let glass = adaptive(light: uiColor(255, 255, 255, 0.46), dark: uiColor(23, 23, 23, 0.96))
        static let controlGlass = adaptive(light: uiColor(255, 255, 255, 0.66), dark: uiColor(23, 23, 23))
        static let controlStroke = adaptive(light: uiColor(255, 255, 255, 0.78), dark: uiColor(44, 44, 46))
        static let hairline = adaptive(light: uiColor(0, 0, 0, 0.08), dark: uiColor(255, 255, 255, 0.10))
        static let separator = adaptive(light: uiColor(0, 0, 0, 0.075), dark: uiColor(255, 255, 255, 0.11))
        static let mutedText = adaptive(light: .secondaryLabel, dark: uiColor(166, 166, 166))
        static let iconNeutral = adaptive(light: uiColor(0, 0, 0, 0.72), dark: uiColor(238, 238, 238))
        static let iconNeutralBackground = adaptive(light: uiColor(0, 0, 0, 0.055), dark: uiColor(36, 36, 38))
    }

    static func accentColor(for key: String) -> Color {
        switch key {
        case "green": return .green
        case "orange": return .orange
        case "purple": return .purple
        case "red": return .red
        case "pink": return .pink
        default: return ColorToken.brand
        }
    }
}

enum SageIconTone {
    case brand
    case neutral
    case success
    case warning
    case danger
    case purple
    case teal

    var foreground: Color {
        switch self {
        case .brand: return SageTheme.ColorToken.brand
        case .neutral: return SageTheme.ColorToken.iconNeutral
        case .success: return .green
        case .warning: return .orange
        case .danger: return .red
        case .purple: return .purple
        case .teal: return .teal
        }
    }

    var background: Color {
        switch self {
        case .brand: return SageTheme.ColorToken.brand.opacity(0.11)
        case .neutral: return SageTheme.ColorToken.iconNeutralBackground
        case .success: return Color.green.opacity(0.12)
        case .warning: return Color.orange.opacity(0.12)
        case .danger: return Color.red.opacity(0.12)
        case .purple: return Color.purple.opacity(0.12)
        case .teal: return Color.teal.opacity(0.12)
        }
    }
}

struct SageSoftCard: ViewModifier {
    var cornerRadius: CGFloat = SageTheme.Radius.md

    func body(content: Content) -> some View {
        content
            .background(.ultraThinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(SageTheme.ColorToken.hairline, lineWidth: 1)
            )
            .shadow(color: Color.black.opacity(0.05), radius: 14, x: 0, y: 8)
    }
}

extension View {
    func sageSoftCard(cornerRadius: CGFloat = SageTheme.Radius.md) -> some View {
        modifier(SageSoftCard(cornerRadius: cornerRadius))
    }

    func sagePillBackground() -> some View {
        background(SageTheme.ColorToken.glass)
            .clipShape(RoundedRectangle(cornerRadius: SageTheme.Radius.pill, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: SageTheme.Radius.pill, style: .continuous)
                    .stroke(SageTheme.ColorToken.controlStroke, lineWidth: 1)
            )
            .shadow(color: Color.black.opacity(0.16), radius: 22, x: 0, y: 10)
    }

    func sageGlassControl(cornerRadius: CGFloat = SageTheme.Radius.md) -> some View {
        background(SageTheme.ColorToken.controlGlass)
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(SageTheme.ColorToken.controlStroke, lineWidth: 1)
            )
            .shadow(color: SageTheme.ColorToken.brand.opacity(0.06), radius: 12, x: 0, y: 6)
    }

    func sageSettingsPage() -> some View {
        scrollContentBackground(.hidden)
            .background(SageBackground())
    }

    func sageListSection() -> some View {
        listRowBackground(sageListRowBackground)
            .listRowSeparatorTint(SageTheme.ColorToken.separator)
    }
}

let sageListRowBackground = SageTheme.ColorToken.controlGlass

struct SageSymbolIcon: View {
    let systemName: String
    var tone: SageIconTone = .neutral
    var size: CGFloat = 17
    var containerSize: CGFloat = 32

    var body: some View {
        Image(systemName: systemName)
            .font(.system(size: size, weight: .medium))
            .symbolRenderingMode(.monochrome)
            .foregroundColor(tone.foreground)
            .frame(width: containerSize, height: containerSize)
            .background(tone.background)
            .clipShape(RoundedRectangle(cornerRadius: SageTheme.Radius.sm, style: .continuous))
    }
}

struct SageSettingsRow<Accessory: View>: View {
    let icon: String
    let title: String
    var subtitle: String?
    var tone: SageIconTone = .neutral
    var showsChevron = true
    private let accessory: Accessory

    init(
        icon: String,
        title: String,
        subtitle: String? = nil,
        tone: SageIconTone = .neutral,
        showsChevron: Bool = true
    ) where Accessory == EmptyView {
        self.icon = icon
        self.title = title
        self.subtitle = subtitle
        self.tone = tone
        self.showsChevron = showsChevron
        self.accessory = EmptyView()
    }

    init(
        icon: String,
        title: String,
        subtitle: String? = nil,
        tone: SageIconTone = .neutral,
        showsChevron: Bool = true,
        @ViewBuilder accessory: () -> Accessory
    ) {
        self.icon = icon
        self.title = title
        self.subtitle = subtitle
        self.tone = tone
        self.showsChevron = showsChevron
        self.accessory = accessory()
    }

    var body: some View {
        HStack(spacing: 12) {
            SageSymbolIcon(systemName: icon, tone: tone)

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(SageTheme.Typography.rowTitle)
                    .foregroundColor(.primary)
                    .lineLimit(1)
                if let subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .font(SageTheme.Typography.rowSubtitle)
                        .foregroundColor(SageTheme.ColorToken.mutedText)
                        .lineLimit(2)
                }
            }

            Spacer(minLength: SageTheme.Spacing.sm)
            accessory
            if showsChevron {
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(SageTheme.ColorToken.mutedText.opacity(0.42))
            }
        }
        .frame(minHeight: subtitle == nil ? 52 : 60)
        .contentShape(Rectangle())
    }
}

struct SageKeyValueRow: View {
    let title: String
    let value: String
    var valueColor: Color = SageTheme.ColorToken.mutedText
    var monospacedValue = false

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: SageTheme.Spacing.md) {
            Text(title)
                .font(SageTheme.Typography.rowTitle)
                .foregroundColor(.primary)
            Spacer()
            Text(value)
                .font(monospacedValue ? SageTheme.Typography.mono : SageTheme.Typography.rowSubtitle)
                .foregroundColor(valueColor)
                .multilineTextAlignment(.trailing)
                .lineLimit(2)
        }
        .frame(minHeight: 46)
    }
}

struct SageStatusPill: View {
    let title: String
    var tone: SageIconTone = .neutral

    var body: some View {
        Text(title)
            .font(.system(size: 11, weight: .medium))
            .foregroundColor(tone.foreground)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(tone.background)
            .clipShape(Capsule())
    }
}

struct SageLoadingRow: View {
    var body: some View {
        HStack {
            Spacer()
            ProgressView()
                .controlSize(.regular)
                .padding(.vertical, SageTheme.Spacing.lg)
            Spacer()
        }
        .listRowBackground(Color.clear)
    }
}

struct SageErrorState: View {
    let message: String

    var body: some View {
        HStack(alignment: .top, spacing: SageTheme.Spacing.sm) {
            SageSymbolIcon(systemName: "exclamationmark.triangle", tone: .warning)
            Text(message)
                .font(SageTheme.Typography.rowSubtitle)
                .foregroundColor(.primary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer()
        }
        .padding(.vertical, SageTheme.Spacing.xs)
    }
}

struct SageEmptyPanel: View {
    let icon: String
    let title: String
    let message: String
    var tone: SageIconTone = .neutral

    var body: some View {
        VStack(spacing: SageTheme.Spacing.sm) {
            SageSymbolIcon(systemName: icon, tone: tone, size: 22, containerSize: 44)
            Text(title)
                .font(SageTheme.Typography.rowTitleEmphasized)
                .foregroundColor(.primary)
            Text(message)
                .font(SageTheme.Typography.rowSubtitle)
                .foregroundColor(SageTheme.ColorToken.mutedText)
                .multilineTextAlignment(.center)
                .lineSpacing(2)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, SageTheme.Spacing.xl)
    }
}

struct SagePrimaryButtonStyle: ButtonStyle {
    var tint: Color = SageTheme.ColorToken.brand

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(SageTheme.Typography.button)
            .foregroundColor(.white)
            .frame(minHeight: 46)
            .frame(maxWidth: .infinity)
            .background(tint.opacity(configuration.isPressed ? 0.78 : 1))
            .clipShape(RoundedRectangle(cornerRadius: SageTheme.Radius.md, style: .continuous))
            .scaleEffect(configuration.isPressed ? 0.985 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

struct SagePlainRowButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.62 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

// MARK: - Sheet Background Modifier

extension View {
    /// 给 sheet 设置纯色背景，避免 SwiftUI 默认的半透明 system material 让
    /// 底层 SageBackground 的浅蓝渐变透出来（iOS 16.4 才提供 presentationBackground）。
    /// iOS 16.0-16.3 用户继续看到 system material，影响极小。
    @ViewBuilder
    func sageSheetBackground(_ color: Color = SageTheme.ColorToken.surface) -> some View {
        if #available(iOS 16.4, *) {
            self.presentationBackground(color)
        } else {
            self
        }
    }
}

struct SageBackground: View {
    @Environment(\.colorScheme) private var colorScheme

    @ViewBuilder
    var body: some View {
        if colorScheme == .dark {
            LinearGradient(
                colors: [
                    Color.black,
                    SageTheme.ColorToken.surfaceSecondary.opacity(0.42),
                    Color.black
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()
        } else {
            LinearGradient(
                colors: [
                    SageTheme.ColorToken.brand.opacity(0.18),
                    SageTheme.ColorToken.cyan.opacity(0.08),
                    SageTheme.ColorToken.brandSoft.opacity(0.34),
                    SageTheme.ColorToken.surface.opacity(0.94)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()
        }
    }
}

struct SageIconButton: View {
    let systemName: String
    var color: Color = .primary
    var background: Color = SageTheme.ColorToken.surfaceSecondary
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(color)
                .frame(width: 40, height: 40)
                .background(background)
                .clipShape(Circle())
        }
        .buttonStyle(.plain)
    }
}

struct SagePromptChip: View {
    let icon: String
    let title: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: SageTheme.Spacing.xs) {
                Image(systemName: icon)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(SageTheme.ColorToken.brand)
                Text(title)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.primary)
                    .lineLimit(1)
            }
            .padding(.horizontal, SageTheme.Spacing.md)
            .padding(.vertical, 10)
            .background(SageTheme.ColorToken.brandSoft.opacity(0.8))
            .clipShape(Capsule())
            .overlay(
                Capsule()
                    .stroke(SageTheme.ColorToken.brand.opacity(0.16), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}

struct SageEmptyStateView: View {
    let systemName: String
    let title: String
    let message: String

    var body: some View {
        VStack(spacing: SageTheme.Spacing.sm) {
            Image(systemName: systemName)
                .font(.system(size: 32, weight: .regular))
                .foregroundColor(SageTheme.ColorToken.mutedText.opacity(0.55))
            Text(title)
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(.primary)
            Text(message)
                .font(.system(size: 13))
                .foregroundColor(SageTheme.ColorToken.mutedText)
                .multilineTextAlignment(.center)
                .lineLimit(3)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, SageTheme.Spacing.xl)
    }
}

struct SageSheetHandle: View {
    var body: some View {
        Capsule()
            .fill(Color.secondary.opacity(0.28))
            .frame(width: 38, height: 5)
            .padding(.top, SageTheme.Spacing.sm)
            .padding(.bottom, SageTheme.Spacing.xs)
    }
}
