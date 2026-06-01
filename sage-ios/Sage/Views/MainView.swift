import SwiftUI

/// iOS 主壳：投资对讲机（资产 / 行动 / 分身）。
/// 设置入口收敛到分身 Tab；App 层注入的环境对象沿环境传递到各 Tab。
struct MainView: View {
    var body: some View {
        InvestmentWalkieView()
    }
}
