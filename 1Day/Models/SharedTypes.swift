import Foundation
import SwiftUI

// MARK: - App Settings Enums

enum AppLanguage: String, CaseIterable, Codable, Identifiable, Hashable {
    case system
    case zhHans
    case english

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .system: return "跟随系统"
        case .zhHans: return "简体中文"
        case .english: return "English"
        }
    }
}

enum AppSettingsLocalization {
    static func text(_ chinese: String, _ english: String, language: AppLanguage) -> String {
        switch language {
        case .english: return english
        case .zhHans: return chinese
        case .system:
            return Locale.current.language.languageCode?.identifier == "en" ? english : chinese
        }
    }
}

enum AppearanceMode: String, CaseIterable, Codable, Identifiable, Hashable {
    case system
    case light
    case dark

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .system: return "跟随系统"
        case .light: return "浅色"
        case .dark: return "深色"
        }
    }
}

// MARK: - PlanItem Enums

enum ItemStatus: String, Codable, CaseIterable, Identifiable, Hashable {
    case pending
    case completed

    var id: String { rawValue }
}

enum Priority: String, Codable, CaseIterable, Identifiable, Hashable {
    case none
    case low
    case medium
    case high

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .none:   return "无"
        case .low:    return "低"
        case .medium: return "中"
        case .high:   return "高"
        }
    }

    var color: Color {
        switch self {
        case .none:   return .secondary
        case .low:    return FamilyUI.accent
        case .medium: return FamilyUI.warning
        case .high:   return FamilyUI.danger
        }
    }

    var sortOrder: Int {
        switch self {
        case .high:   return 0
        case .medium: return 1
        case .low:    return 2
        case .none:   return 3
        }
    }
}

// MARK: - AI

enum AIProcessingMode: String, CaseIterable, Codable, Identifiable, Hashable {
    case ruleFirst
    case aiFirst

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .ruleFirst: return "规则优先"
        case .aiFirst:   return "AI 优先"
        }
    }

    var description: String {
        switch self {
        case .ruleFirst: return "先用本地规则快速识别，规则失败后再交给 AI。"
        case .aiFirst:   return "先交给 AI 识别，AI 失败或结果异常时再用本地规则兜底。"
        }
    }
}

enum AIProvider: String, CaseIterable, Codable, Identifiable, Hashable {
    case claude
    case chatGPT
    case kimi
    case qwen
    case doubao
    case yuanbao
    case mimo
    case deepseek

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .claude:   return "Claude"
        case .chatGPT:  return "ChatGPT"
        case .kimi:     return "Kimi"
        case .qwen:     return "通义千问"
        case .doubao:   return "豆包"
        case .yuanbao:  return "腾讯元宝"
        case .mimo:     return "小米 MiMo"
        case .deepseek: return "DeepSeek"
        }
    }

    var supportsVision: Bool {
        switch self {
        case .claude, .chatGPT, .kimi, .qwen, .doubao, .yuanbao, .mimo:
            return true
        case .deepseek:
            return false
        }
    }

    func supportsVision(model: String) -> Bool {
        let normalized = model.lowercased()
        switch self {
        case .claude:
            return normalized.contains("claude")
                || normalized.contains("sonnet")
                || normalized.contains("opus")
                || normalized.contains("haiku")
        case .chatGPT:
            return normalized.contains("gpt-5")
                || normalized.contains("gpt-4.1")
                || normalized.contains("gpt-4o")
                || normalized.contains("o4")
        case .kimi:
            return normalized.contains("vision")
                || normalized == "kimi-k2.5"
                || normalized == "kimi-k2.6"
        case .qwen:
            return normalized.contains("vl")
                || normalized.contains("qvq")
                || normalized.contains("ocr")
        case .doubao:
            return normalized.contains("vision")
                || normalized.contains("visual")
                || normalized.contains("multimodal")
                || normalized.contains("doubao-1.6")
                || normalized.contains("seed-2-0-vision")
        case .yuanbao:
            return normalized.contains("vision")
                || normalized.contains("t1-vision")
                || normalized.contains("turbos-vision")
        case .mimo:
            return normalized == "mimo-v2.5"
                || normalized == "mimo-v2.5-pro"
        case .deepseek:
            return false
        }
    }
}
