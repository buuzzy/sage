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

    enum Radius {
        static let sm: CGFloat = 10
        static let md: CGFloat = 16
        static let lg: CGFloat = 22
        static let pill: CGFloat = 30
    }

    enum ColorToken {
        static let brand = Color(red: 0.18, green: 0.43, blue: 0.96)
        static let brandSoft = Color(red: 0.88, green: 0.93, blue: 1.0)
        static let cyan = Color(red: 0.13, green: 0.63, blue: 0.73)
        static let surface = Color(.systemBackground)
        static let surfaceSecondary = Color(.secondarySystemBackground)
        static let surfaceElevated = Color(.tertiarySystemBackground)
        static let hairline = Color.primary.opacity(0.08)
        static let mutedText = Color.secondary
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
        background(.ultraThinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: SageTheme.Radius.pill, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: SageTheme.Radius.pill, style: .continuous)
                    .stroke(SageTheme.ColorToken.hairline, lineWidth: 1)
            )
            .shadow(color: Color.black.opacity(0.08), radius: 18, x: 0, y: 8)
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
