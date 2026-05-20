import SwiftUI

@main
struct SageApp: App {
    @StateObject private var authService = AuthService.shared
    @StateObject private var settingsService = SettingsService.shared
    @StateObject private var chatVM = ChatViewModel()
    @AppStorage("sage_theme") private var theme: String = "system"
    @AppStorage("sage_accent_color") private var accentColor: String = "blue"
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
                    MainView(chatVM: chatVM)
                        .environmentObject(authService)
                        .environmentObject(settingsService)
                } else {
                    LoginView()
                        .environmentObject(authService)
                }
            }
            .preferredColorScheme(colorSchemeForTheme)
            .tint(accentColorValue)
            .animation(.easeInOut(duration: 0.3), value: theme)
            .onChange(of: scenePhase) { newPhase in
                switch newPhase {
                case .background:
                    chatVM.willEnterBackground()
                case .active:
                    chatVM.resumeFromBackground()
                    NotificationService.shared.clearBadge()
                default:
                    break
                }
            }
            .onAppear {
                NotificationService.shared.requestPermission()
            }
        }
    }

    private var colorSchemeForTheme: ColorScheme? {
        switch theme {
        case "light": return .light
        case "dark": return .dark
        default: return nil
        }
    }

    private var accentColorValue: Color {
        switch accentColor {
        case "green": return .green
        case "orange": return .orange
        case "purple": return .purple
        case "red": return .red
        case "pink": return .pink
        default: return .blue
        }
    }
}
