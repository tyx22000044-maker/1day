import SwiftUI

enum AppBannerTone: Equatable {
    case error
    case warning
    case success

    var foreground: Color {
        FamilyUI.onAccent
    }

    var background: Color {
        switch self {
        case .error:
            return FamilyUI.danger.opacity(0.94)
        case .warning:
            return FamilyUI.warning.opacity(0.96)
        case .success:
            return FamilyUI.success.opacity(0.96)
        }
    }

    var icon: String {
        switch self {
        case .error:
            return "exclamationmark.triangle.fill"
        case .warning:
            return "exclamationmark.circle.fill"
        case .success:
            return "checkmark.circle.fill"
        }
    }
}

/// 全局横幅组件 — 从顶部滑入的 toast，由 `GlobalBannerCenter` 驱动。
///
/// `presentationID` 是这条 banner 的身份：延迟收起的回调只允许关闭自己那一条，
/// 而且 `.task(id:)` 会在身份变化时取消上一次的计时，旧 banner 不会误关新 banner。
struct AppErrorBanner: View {
    let presentationID: UUID
    let title: String
    var message: String?
    var tone: AppBannerTone = .error
    let onDismiss: () -> Void

    @State private var isVisible = false
    @State private var isDismissing = false

    var body: some View {
        VStack {
            if isVisible {
                HStack(alignment: .top, spacing: 12) {
                    RoundedRectangle(cornerRadius: FamilyUI.controlCornerRadius)
                        .fill(FamilyUI.onAccent.opacity(0.16))
                        .frame(width: FamilyUI.iconBoxSize, height: FamilyUI.iconBoxSize)
                        .overlay(
                            Image(systemName: tone.icon)
                                .font(.system(size: 15, weight: .bold))
                                .foregroundStyle(tone.foreground)
                        )

                    VStack(alignment: .leading, spacing: 3) {
                        Text(title)
                        .font(FamilyTypography.text(.subheadline, .bold))
                            .foregroundStyle(tone.foreground)
                        if let message, !message.isEmpty {
                            Text(message)
                                .font(FamilyTypography.text(.caption))
                                .foregroundStyle(tone.foreground.opacity(0.84))
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }

                    Spacer(minLength: 0)

                    Button {
                        Task { await runDismissal() }
                    } label: {
                        Image(systemName: "xmark")
                            .font(FamilyTypography.text(.caption, .black))
                            .foregroundStyle(tone.foreground.opacity(0.78))
                            .frame(width: 28, height: 28)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("关闭提示")
                }
                .padding(12)
                .background(tone.background)
                .overlay(
                    RoundedRectangle(cornerRadius: FamilyUI.controlCornerRadius)
                        .stroke(FamilyUI.ink.opacity(0.18), lineWidth: 1)
                )
                .clipShape(RoundedRectangle(cornerRadius: FamilyUI.controlCornerRadius))
                .padding(.horizontal, AppSpacing.pageHorizontal)
                .padding(.top, 8)
                .transition(.move(edge: .top).combined(with: .opacity))
            }

            Spacer()
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.74), value: isVisible)
        .task(id: presentationID) {
            isVisible = true
            isDismissing = false
            try? await Task.sleep(nanoseconds: 4_000_000_000)
            guard !Task.isCancelled else { return }
            await runDismissal()
        }
    }

    private func runDismissal() async {
        guard isVisible, !isDismissing else { return }
        isDismissing = true
        withAnimation(.easeOut(duration: 0.18)) {
            isVisible = false
        }
        try? await Task.sleep(nanoseconds: 180_000_000)
        guard !Task.isCancelled else { return }
        onDismiss()
    }
}
