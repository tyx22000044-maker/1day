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

extension AppLanguage {
    /// 界面语言和日期格式要一起走，否则切到英文还是「7月1日 星期三」。
    var locale: Locale {
        switch self {
        case .english: return Locale(identifier: "en_US")
        case .zhHans: return Locale(identifier: "zh_CN")
        case .system: return .autoupdatingCurrent
        }
    }
}

/// 用户可见文案的单一来源。中文是主语言，英文按 `docs/APP_COPY.md` 对齐。
///
/// 之前每个页面各自把中英两份字符串散在调用点上（`localized("今天", "Today")`），
/// 漏掉一处就是切英文后中英混排。这里先收口主流程的可见文案；
/// 设置页深层文案、AI 提示词和站内信仍是中文优先，见 MVP_SCOPE 的本地化说明。
enum AppText {
    enum Key: String, CaseIterable {
        case tabToday, tabPlan, tabAI, tabNotes, tabSettings
        case navToday, navPlan, navNotes, navSettings
        case groupUnscheduled, groupOverdue, groupToday, groupTomorrow, groupThisWeek, groupLater
        case sectionCompleted, sectionCompletedToday, sectionCompletedThisWeek
        case trendExpand, trendCollapse
        case quickInputPlaceholder, taskCountSuffix, noteCountSuffix
        case createTask, createNote, save, cancel, delete, undo, priorityLabel
        case emptyTodayTitle, emptyTodaySubtitle
        case emptyPlanTitle, emptyPlanSubtitle
        case emptyNotesTitle, emptyNotesSubtitle, emptySearchTitle, emptySearchSubtitle
        case scheduleLater, addedToToday
        case rowComplete, rowUncomplete, rowMoveToUnscheduled, rowSetDate, deleteTask, deleteNote
        case notifyTodayBody, notifyTomorrowBody, notifyWeekdayBody
        case notifyImportantPrefix, notifyTodayHigh, notifyTomorrowHigh, notifyWeekdayHigh
    }

    private static let table: [Key: (zh: String, en: String)] = [
        .tabToday: ("今天", "Today"),
        .tabPlan: ("计划", "Plan"),
        .tabAI: ("AI", "AI"),
        .tabNotes: ("笔记", "Notes"),
        .tabSettings: ("设置", "Settings"),
        .navToday: ("今天", "Today"),
        .navPlan: ("计划", "Plan"),
        .navNotes: ("笔记", "Notes"),
        .navSettings: ("设置", "Settings"),
        .groupUnscheduled: ("未安排", "Unscheduled"),
        .groupOverdue: ("已过期", "Overdue"),
        .groupToday: ("今天", "Today"),
        .groupTomorrow: ("明天", "Tomorrow"),
        .groupThisWeek: ("本周", "This Week"),
        .groupLater: ("更晚", "Later"),
        .sectionCompleted: ("已完成", "Done"),
        .sectionCompletedToday: ("今日完成", "Completed today"),
        .sectionCompletedThisWeek: ("本周完成", "This week"),
        .trendExpand: ("查看本周趋势", "See weekly trend"),
        .trendCollapse: ("收起本周趋势", "Hide weekly trend"),
        .quickInputPlaceholder: ("记下一件事…", "Jot down one thing…"),
        .taskCountSuffix: ("项", "tasks"),
        .noteCountSuffix: ("条", "notes"),
        .createTask: ("创建任务", "New task"),
        .createNote: ("创建笔记", "New note"),
        .save: ("保存", "Save"),
        .cancel: ("取消", "Cancel"),
        .delete: ("删除", "Delete"),
        .undo: ("撤销", "Undo"),
        .priorityLabel: ("优先级", "Priority"),
        .emptyTodayTitle: ("没有待办事项", "Nothing scheduled"),
        .emptyTodaySubtitle: ("在上方输入框记下一件事，或点击 + 创建", "Type above, or tap + to add a task"),
        .emptyPlanTitle: ("还没有任何任务", "No tasks yet"),
        .emptyPlanSubtitle: ("点击 + 创建你的第一个任务", "Tap + to create your first task"),
        .emptyNotesTitle: ("随手记下你的想法", "Capture what's on your mind"),
        .emptyNotesSubtitle: ("点击 + 创建一条笔记", "Tap + to start a note"),
        .emptySearchTitle: ("没有匹配的笔记", "No matching notes"),
        .emptySearchSubtitle: ("试试搜索标题中的关键词，或正文中的片段", "Try a word from the title or body"),
        .scheduleLater: ("稍后安排", "Schedule later"),
        .addedToToday: ("已加入今天", "Added to today"),
        .rowComplete: ("标记完成", "Mark done"),
        .rowUncomplete: ("标记未完成", "Mark not done"),
        .rowMoveToUnscheduled: ("移到未安排", "Move to unscheduled"),
        .rowSetDate: ("设日期", "Set date"),
        .deleteTask: ("删除任务", "Delete task"),
        .deleteNote: ("删除笔记", "Delete note"),
        .notifyTodayBody: ("今天的待办，别忘了", "Due today — don't forget"),
        .notifyTomorrowBody: ("明天到期，提前提醒你", "Due tomorrow — a heads-up"),
        .notifyWeekdayBody: ("到期，记得处理", "is coming up"),
        .notifyImportantPrefix: ("重要：", "Important: "),
        .notifyTodayHigh: ("今天必须完成，重要任务", "Due today and important"),
        .notifyTomorrowHigh: ("明天的重要任务，提前提醒", "Important task due tomorrow"),
        .notifyWeekdayHigh: ("到期，重要任务", "due soon — high priority")
    ]

    static func string(_ key: Key, language: AppLanguage) -> String {
        guard let entry = table[key] else { return key.rawValue }
        return AppSettingsLocalization.text(entry.zh, entry.en, language: language)
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

    /// 优先级名称也要跟界面语言，否则英文选择器里冒出「高/中/低」。
    func displayName(for language: AppLanguage) -> String {
        switch self {
        case .none:   return AppSettingsLocalization.text("无", "None", language: language)
        case .low:    return AppSettingsLocalization.text("低", "Low", language: language)
        case .medium: return AppSettingsLocalization.text("中", "Medium", language: language)
        case .high:   return AppSettingsLocalization.text("高", "High", language: language)
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
