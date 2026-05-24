import SwiftUI

/// 登录页 — 仅支持 Google OAuth（Apple 一键登录 / 面容登录待实现）
struct LoginView: View {
    @EnvironmentObject var authService: AuthService
    @State private var isLoading = false

    var body: some View {
        ZStack {
            Color(.systemBackground).ignoresSafeArea()

            VStack(spacing: 0) {
                Spacer()

                VStack(spacing: 0) {
                    Image("SageLogo")
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 80, height: 80)
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                        .background(
                            RoundedRectangle(cornerRadius: 18)
                                .fill(Color(.systemGray6))
                                .frame(width: 96, height: 96)
                        )
                        .shadow(color: .black.opacity(0.04), radius: 6, y: 2)
                        .padding(.top, 36)
                        .padding(.bottom, 20)

                    Text("Sage")
                        .font(.system(size: 28, weight: .regular, design: .serif))
                        .foregroundColor(.primary)
                    Text("智能金融助手")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .padding(.top, 4)
                        .padding(.bottom, 28)

                    VStack(spacing: 12) {
                        Button {
                            Task {
                                isLoading = true
                                await authService.signInWithGoogle()
                                isLoading = false
                            }
                        } label: {
                            HStack(spacing: 10) {
                                if isLoading {
                                    ProgressView()
                                        .scaleEffect(0.75)
                                } else {
                                    GoogleLogoView()
                                        .frame(width: 18, height: 18)
                                }
                                Text("使用 Google 登录")
                                    .font(.system(size: 15, weight: .medium))
                                    .foregroundColor(.primary)
                            }
                            .frame(maxWidth: .infinity)
                            .frame(height: 44)
                            .overlay(
                                RoundedRectangle(cornerRadius: 12)
                                    .stroke(Color(.systemGray3), lineWidth: 1)
                            )
                        }
                        .disabled(isLoading)

                        if let error = authService.errorMessage {
                            HStack {
                                Image(systemName: "exclamationmark.circle.fill")
                                    .foregroundColor(.red)
                                Text(error)
                                    .font(.caption)
                                    .foregroundColor(.red)
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 8)
                            .background(Color.red.opacity(0.1))
                            .cornerRadius(8)
                        }
                    }
                    .padding(.horizontal, 28)
                    .padding(.bottom, 36)
                }
                .background(Color(.systemBackground))
                .cornerRadius(20)
                .overlay(
                    RoundedRectangle(cornerRadius: 20)
                        .stroke(Color(.systemGray4).opacity(0.5), lineWidth: 1)
                )
                .shadow(color: .black.opacity(0.05), radius: 12, y: 4)
                .padding(.horizontal, 36)

                Spacer()

                Text("Sage · AI Financial Assistant")
                    .font(.system(size: 11, weight: .regular, design: .monospaced))
                    .foregroundColor(Color(.systemGray2))
                    .padding(.bottom, 28)
            }
        }
    }
}

// MARK: - Google Logo (colored G)

struct GoogleLogoView: View {
    var body: some View {
        Canvas { context, size in
            let w = size.width
            let h = size.height
            let center = CGPoint(x: w/2, y: h/2)
            let radius = min(w, h) * 0.45

            var path1 = Path()
            path1.addArc(center: center, radius: radius, startAngle: .degrees(-45), endAngle: .degrees(10), clockwise: false)
            path1.addLine(to: center)
            context.fill(path1, with: .color(Color(red: 0.263, green: 0.522, blue: 0.957)))

            var path2 = Path()
            path2.addArc(center: center, radius: radius, startAngle: .degrees(10), endAngle: .degrees(100), clockwise: false)
            path2.addLine(to: center)
            context.fill(path2, with: .color(Color(red: 0.204, green: 0.659, blue: 0.325)))

            var path3 = Path()
            path3.addArc(center: center, radius: radius, startAngle: .degrees(100), endAngle: .degrees(200), clockwise: false)
            path3.addLine(to: center)
            context.fill(path3, with: .color(Color(red: 0.984, green: 0.737, blue: 0.020)))

            var path4 = Path()
            path4.addArc(center: center, radius: radius, startAngle: .degrees(200), endAngle: .degrees(315), clockwise: false)
            path4.addLine(to: center)
            context.fill(path4, with: .color(Color(red: 0.918, green: 0.263, blue: 0.208)))

            var centerCircle = Path()
            centerCircle.addArc(center: center, radius: radius * 0.55, startAngle: .degrees(0), endAngle: .degrees(360), clockwise: false)
            context.fill(centerCircle, with: .color(.white))

            let notchRect = CGRect(x: w * 0.48, y: h * 0.38, width: w * 0.52, height: h * 0.26)
            context.fill(Path(notchRect), with: .color(Color(red: 0.263, green: 0.522, blue: 0.957)))
        }
    }
}

#Preview {
    LoginView()
        .environmentObject(AuthService.shared)
}
