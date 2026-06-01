import SwiftUI

/// iOS 新主壳：资产 / 行动 / 分身。
///
/// 旧聊天 ViewModel 暂时保留在入参中，便于后台恢复逻辑和后续分阶段拆迁；
/// 新产品形态不再把会话流作为主入口。
struct MainView: View {
    @EnvironmentObject var authService: AuthService
    @EnvironmentObject var settingsService: SettingsService
    @State private var showSettings = false

    var body: some View {
        InvestmentWalkieView()
            .sheet(isPresented: $showSettings) {
                SettingsView()
                    .environmentObject(authService)
                    .environmentObject(settingsService)
                    .sageSheetBackground()
            }
    }
}
