import Foundation

enum AppTab: Int, CaseIterable, Hashable, Identifiable {
    case today
    case plan
    case ai
    case notes
    case settings

    var id: Int { rawValue }

    /// Tab 名跟着界面语言走；之前写死中文，切英文后整条 tab bar 都不换。
    func title(for language: AppLanguage) -> String {
        let key: AppText.Key
        switch self {
        case .today: key = .tabToday
        case .plan: key = .tabPlan
        case .ai: key = .tabAI
        case .notes: key = .tabNotes
        case .settings: key = .tabSettings
        }
        return AppText.string(key, language: language)
    }

    var systemImage: String {
        switch self {
        case .today: return "sun.max.fill"
        case .plan: return "list.bullet"
        case .ai: return "sparkles"
        case .notes: return "note.text"
        case .settings: return "gearshape.fill"
        }
    }
}
