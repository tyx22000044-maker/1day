import SwiftUI

enum AppBannerTone: Equatable {
    case error
    case warning
    case success

    var foreground: Color {
        .white
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

/// 全局横幅组件 — 从顶部滑入的 toast，由 `GlobalBannerCenter` 驱动
struct AppErrorBanner: View {
    let title: String
    var message: String?
    var tone: AppBannerTone = .error
    let onDismiss: () -> Void

    @State private var isVisible = false

    var body: some View {
        VStack {
            if isVisible {
                HStack(alignment: .top, spacing: 12) {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.white.opacity(0.16))
                        .frame(width: FamilyUI.iconBoxSize, height: FamilyUI.iconBoxSize)
                        .overlay(
                            Image(systemName: tone.icon)
                                .font(.system(size: 15, weight: .bold, design: .rounded))
                                .foregroundStyle(tone.foreground)
                        )

                    VStack(alignment: .leading, spacing: 3) {
                        Text(title)
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(tone.foreground)
                        if let message, !message.isEmpty {
                            Text(message)
                                .font(.caption)
                                .foregroundStyle(tone.foreground.opacity(0.84))
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }

                    Spacer(minLength: 0)

                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.caption.weight(.black))
                            .foregroundStyle(tone.foreground.opacity(0.78))
                            .frame(width: 28, height: 28)
                    }
                    .buttonStyle(.plain)
                }
                .padding(12)
                .background(tone.background)
                .overlay(
                    RoundedRectangle(cornerRadius: FamilyUI.controlCornerRadius)
                        .stroke(Color.black.opacity(0.18), lineWidth: 1)
                )
                .clipShape(RoundedRectangle(cornerRadius: FamilyUI.controlCornerRadius))
                .padding(.horizontal, AppSpacing.pageHorizontal)
                .padding(.top, 8)
                .transition(.move(edge: .top).combined(with: .opacity))
            }

            Spacer()
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.74), value: isVisible)
        .onAppear {
            isVisible = true
            autoDismissAfter(4)
        }
    }

    private func dismiss() {
        withAnimation(.easeOut(duration: 0.18)) {
            isVisible = false
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) {
            onDismiss()
        }
    }

    private func autoDismissAfter(_ seconds: Double) {
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds) {
            guard isVisible else { return }
            dismiss()
        }
    }
}
