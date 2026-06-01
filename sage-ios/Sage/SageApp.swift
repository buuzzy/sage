import SwiftUI

@main
struct SageApp: App {
    @StateObject private var authService = AuthService.shared
    @StateObject private var settingsService = SettingsService.shared
    @StateObject private var cloudProviderStore = CloudProviderStore.shared
    @AppStorage("sage_theme") private var theme: String = "system"
    @Environment(\.scenePhase) private var scenePhase

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
                        .environmentObject(cloudProviderStore)
                        .task {
                            // 启动时拉取云端 provider，确保 isModelConfigured 正确
                            await cloudProviderStore.refresh()
                            settingsService.hasCloudProvider = !cloudProviderStore.providers.isEmpty
                        }
                } else {
                    LoginView()
                        .environmentObject(authService)
                }
            }
            .tint(SageTheme.ColorToken.brand)
            .onAppear {
                applyTheme(theme)
                NotificationService.shared.requestPermission()
            }
            .onChange(of: theme) { newValue in
                applyTheme(newValue)
            }
            .onChange(of: scenePhase) { newPhase in
                switch newPhase {
                case .active:
                    NotificationService.shared.clearBadge()
                    // Check for new cron job results from Supabase
                    Task { await CronResultPoller.shared.checkForNewResults() }
                default:
                    break
                }
            }
        }
    }

    /// Drive the theme through UIKit instead of SwiftUI's `.preferredColorScheme`.
    /// `.preferredColorScheme` does not always re-evaluate inside sheets / NavigationLink
    /// push destinations when the underlying @AppStorage value changes, which left the
    /// settings page stuck in the previous mode after switching to "跟随系统". Setting
    /// `overrideUserInterfaceStyle` on every connected UIWindowScene's windows applies
    /// the change at the UIKit layer so every presentation (including modally hosted
    /// sheets) flips immediately.
    private func applyTheme(_ theme: String) {
        let style: UIUserInterfaceStyle
        switch theme {
        case "light": style = .light
        case "dark": style = .dark
        default: style = .unspecified
        }

        for scene in UIApplication.shared.connectedScenes {
            guard let windowScene = scene as? UIWindowScene else { continue }
            for window in windowScene.windows {
                window.overrideUserInterfaceStyle = style
            }
        }
    }
}
