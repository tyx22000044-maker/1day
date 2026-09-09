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
