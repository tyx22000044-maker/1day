import Foundation
import Observation

/// App-wide error/success toast, shown as an `AppErrorBanner` overlay from ContentView.
/// Call `GlobalBannerCenter.shared.show(...)` from any Service or ViewModel instead of
/// building one-off alerts for background failures (AI errors, backup failures, etc).
@MainActor
@Observable
final class GlobalBannerCenter {
    static let shared = GlobalBannerCenter()

    var currentBanner: AppBannerPayload?

    func show(title: String, message: String? = nil, tone: AppBannerTone = .error) {
        currentBanner = AppBannerPayload(title: title, message: message, tone: tone)
    }

    func show(error: AppError) {
        show(title: error.errorDescription ?? "未知错误", message: error.recoverySuggestion, tone: .error)
    }

    /// 只关闭指定那一条。
    ///
    /// 旧实现只有一个无条件的 `dismiss()`：前一条 banner 的延迟关闭回调会在
    /// 新一条刚出现时把它一起关掉，用户根本没见过新错误。
    func dismiss(id: UUID) {
        guard currentBanner?.id == id else { return }
        currentBanner = nil
    }

    /// 用户主动点 × 或需要立即收起时使用。
    func dismiss() {
        currentBanner = nil
    }
}

struct AppBannerPayload: Identifiable, Equatable {
    let id = UUID()
    let title: String
    let message: String?
    let tone: AppBannerTone
}
