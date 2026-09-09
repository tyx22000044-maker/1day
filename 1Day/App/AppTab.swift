import Foundation

enum AppTab: Int, CaseIterable, Hashable, Identifiable {
    case today
    case plan
    case ai
    case notes
    case settings

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .today: return "今天"
        case .plan: return "计划"
        case .ai: return "AI"
        case .notes: return "笔记"
        case .settings: return "设置"
        }
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
