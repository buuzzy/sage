import Foundation
import Supabase

/// Supabase 认证服务
/// 管理登录状态、JWT token、用户信息
@MainActor
class AuthService: ObservableObject {
    static let shared = AuthService()

    // Supabase client
    private let client: SupabaseClient

    // Published state
    @Published var isAuthenticated = false
    @Published var isLoading = true
    @Published var currentUser: User?
    @Published var errorMessage: String?

    // Supabase 配置统一从 SupabaseConfig 读取（Secrets.xcconfig 注入，不在源码 hardcode）

    private init() {
        client = SupabaseClient(
            supabaseURL: SupabaseConfig.url,
            supabaseKey: SupabaseConfig.anonKey,
            options: SupabaseClientOptions(
                auth: .init(emitLocalSessionAsInitialSession: true)
            )
        )

        // Listen for auth state changes
        Task {
            await checkSession()
            listenForAuthChanges()
        }
    }

    // MARK: - Public API

    /// Google OAuth 登录
    /// queryParams 传 prompt=select_account 强制弹出账号选择器，支持多账号切换
    func signInWithGoogle() async {
        errorMessage = nil
        do {
            try await client.auth.signInWithOAuth(
                provider: .google,
                redirectTo: URL(string: "ai.sage.app://auth/callback"),
                queryParams: [(name: "prompt", value: "select_account")]
            )
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// 登出
    func signOut() async {
        do {
            try await client.auth.signOut()
            isAuthenticated = false
            currentUser = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// 获取当前 access token（用于 API 调用）
    func getAccessToken() async -> String? {
        try? await client.auth.session.accessToken
    }

    /// 获取当前用户 ID
    var userId: String? {
        currentUser?.id.uuidString
    }

    // MARK: - Private

    private func checkSession() async {
        do {
            let session = try await client.auth.session
            currentUser = session.user
            isAuthenticated = true
        } catch {
            isAuthenticated = false
        }
        isLoading = false
    }

    private func listenForAuthChanges() {
        Task {
            for await (event, session) in client.auth.authStateChanges {
                switch event {
                case .initialSession:
                    applySession(session)
                case .signedIn:
                    applySession(session)
                case .signedOut:
                    currentUser = nil
                    isAuthenticated = false
                default:
                    break
                }
            }
        }
    }

    private func applySession(_ session: Session?) {
        guard let session, !session.isExpired else {
            currentUser = nil
            isAuthenticated = false
            return
        }

        currentUser = session.user
        isAuthenticated = true
    }
}
