import SwiftUI

@main
struct SageApp: App {
    @StateObject private var authService = AuthService.shared
    @StateObject private var settingsService = SettingsService.shared
    @AppStorage("sage_theme") private var theme: String = "system"

    var body: some Scene {
        WindowGroup {
            Group {
                if authService.isLoading {
                    ZStack {
                        Color(.systemBackground).ignoresSafeArea()
                        Image("SageLogo")
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: 64, height: 64)
                            .clipShape(RoundedRectangle(cornerRadius: 14))
                    }
                } else if authService.isAuthenticated {
                    MainView()
                        .environmentObject(authService)
                        .environmentObject(settingsService)
                } else {
                    LoginView()
                        .environmentObject(authService)
                }
            }
            // 平滑切换主题 — 不用 .id(theme)，SwiftUI 自动动画过渡
            .preferredColorScheme(colorSchemeForTheme)
            .animation(.easeInOut(duration: 0.3), value: theme)
        }
    }

    private var colorSchemeForTheme: ColorScheme? {
        switch theme {
        case "light": return .light
        case "dark": return .dark
        default: return nil
        }
    }
}
