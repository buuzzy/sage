import Foundation

/// Supabase 客户端配置 — single source of truth
///
/// 配置来源：`sage-ios/Sage/Config/Secrets.xcconfig`（.gitignore，本地填值）
/// 注入路径：xcconfig → build settings → Info.plist substitution → 运行时 Bundle 读取
///
/// 任何需要访问 Supabase 的服务（AuthService / CloudSyncService / 未来新增的）
/// 都必须通过此类型间接拿到 URL 和 anon key，**不要在源码里再次 hardcode**。
///
/// 历史教训：CloudSyncService 曾经独立 hardcode 了一份过期的 anon key，
/// Supabase 轮换 JWT secret 后所有 cloud sync 请求静默 401，
/// 直到「清除数据」详细日志才暴露。本类型把这种事故归零的可能性降到最低。
enum SupabaseConfig {
    /// Supabase 项目 URL（来自 Secrets.xcconfig 的 SUPABASE_URL）
    static let url: URL = {
        guard let raw = Bundle.main.object(forInfoDictionaryKey: "SUPABASE_URL") as? String,
              !raw.isEmpty,
              let url = URL(string: raw) else {
            fatalError(
                "[SupabaseConfig] 缺失或无效的 SUPABASE_URL。\n" +
                "请检查 sage-ios/Sage/Config/Secrets.xcconfig 是否存在并填入正确值\n" +
                "（参考 Secrets.xcconfig.example）"
            )
        }
        return url
    }()

    /// Supabase 匿名 key（来自 Secrets.xcconfig 的 SUPABASE_ANON_KEY）
    /// 注：anon key 设计上是 public — 真正的安全由 RLS 在 Supabase 端保证。
    /// 我们仍把它放进 .gitignore 是为了避免 key 轮换时漏改的工程事故。
    static let anonKey: String = {
        guard let key = Bundle.main.object(forInfoDictionaryKey: "SUPABASE_ANON_KEY") as? String,
              !key.isEmpty,
              key != "your-anon-key-here" else {
            fatalError(
                "[SupabaseConfig] 缺失或未填入的 SUPABASE_ANON_KEY。\n" +
                "请检查 sage-ios/Sage/Config/Secrets.xcconfig 是否存在并填入正确值\n" +
                "（参考 Secrets.xcconfig.example）"
            )
        }
        return key
    }()
}
