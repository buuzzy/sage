import SwiftUI

@main
struct SageApp: App {
    @StateObject private var authService = AuthService.shared
    @StateObject private var settingsService = SettingsService.shared

    var body: some Scene {
        WindowGroup {
            if authService.isLoading {
                // Splash
                ZStack {
                    Color(.systemBackground).ignoresSafeArea()
                    Image(systemName: "leaf.fill")
                        .font(.system(size: 48))
                        .foregroundColor(.green)
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
    }
}
