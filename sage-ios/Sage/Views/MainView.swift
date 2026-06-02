import SwiftUI

/// iOS 主壳：投资对讲机（资产 / 行动横向分页）。
/// 设置从左上角入口进入；分身归档为设置功能，App 层注入的环境对象沿环境传递。
struct MainView: View {
    var body: some View {
        InvestmentWalkieView()
    }
}
