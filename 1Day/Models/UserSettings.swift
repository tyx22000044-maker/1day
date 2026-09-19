import Foundation
import SwiftData

@Model
final class UserSettings {
    static let currentDataSchemaVersion = 1

    /// 全库只应该有一条设置记录，用固定 id 表达这个约束。
    ///
    /// `@Attribute(.unique)` 只挡得住相同 id 的重复插入，挡不住「两条不同 id 的设置」；
    /// 而各视图统一用 `settings.first` 当当前设置，一旦多出来就会各取一条。
    /// 所以新记录一律用这个 id，多余的历史记录在启动时清理。
    static let singletonID = UUID(uuidString: "1da01da0-0000-4000-8000-000000000001")!

    @Attribute(.unique) var id: UUID
    var dataSchemaVersion: Int = UserSettings.currentDataSchemaVersion

    var nickname: String
    var avatarSymbolName: String
    var avatarImageData: Data?

    var languageRawValue: String
    var appearanceRawValue: String

    var defaultReminderHour: Int
    var defaultReminderMinute: Int

    var selectedAIProviderRawValue: String
    var selectedAIModel: String
    var aiProcessingModeRawValue: String = AIProcessingMode.ruleFirst.rawValue
    var isAIConfigured: Bool

    var isHapticsEnabled: Bool = true
    var isSoundEffectsEnabled: Bool = true

    var hasCompletedOnboarding: Bool

    var createdAt: Date
    var updatedAt: Date

    init(id: UUID = UserSettings.singletonID,
         nickname: String = "",
         avatarSymbolName: String = "person.crop.circle",
         avatarImageData: Data? = nil,
         language: AppLanguage = .system,
         appearance: AppearanceMode = .system,
         defaultReminderHour: Int = 9,
         defaultReminderMinute: Int = 0,
         selectedAIProvider: AIProvider = .claude,
         selectedAIModel: String = "claude-sonnet",
         aiProcessingMode: AIProcessingMode = .ruleFirst,
         isAIConfigured: Bool = false,
         isHapticsEnabled: Bool = true,
         isSoundEffectsEnabled: Bool = true,
         hasCompletedOnboarding: Bool = false) {
        self.id = id
        self.nickname = nickname
        self.avatarSymbolName = avatarSymbolName
        self.avatarImageData = avatarImageData
        self.languageRawValue = language.rawValue
        self.appearanceRawValue = appearance.rawValue
        self.defaultReminderHour = defaultReminderHour
        self.defaultReminderMinute = defaultReminderMinute
        self.selectedAIProviderRawValue = selectedAIProvider.rawValue
        self.selectedAIModel = selectedAIModel
        self.aiProcessingModeRawValue = aiProcessingMode.rawValue
        self.isAIConfigured = isAIConfigured
        self.isHapticsEnabled = isHapticsEnabled
        self.isSoundEffectsEnabled = isSoundEffectsEnabled
        self.hasCompletedOnboarding = hasCompletedOnboarding
        self.createdAt = Date()
        self.updatedAt = Date()
    }

    // MARK: - Computed Properties

    var language: AppLanguage {
        get { AppLanguage(rawValue: languageRawValue) ?? .system }
        set { languageRawValue = newValue.rawValue }
    }

    var appearance: AppearanceMode {
        get { AppearanceMode(rawValue: appearanceRawValue) ?? .system }
        set { appearanceRawValue = newValue.rawValue }
    }

    var selectedAIProvider: AIProvider {
        get { AIProvider(rawValue: selectedAIProviderRawValue) ?? .claude }
        set { selectedAIProviderRawValue = newValue.rawValue }
    }

    var aiProcessingMode: AIProcessingMode {
        get { AIProcessingMode(rawValue: aiProcessingModeRawValue) ?? .ruleFirst }
        set { aiProcessingModeRawValue = newValue.rawValue }
    }

    var defaultReminderTime: DateComponents {
        DateComponents(hour: defaultReminderHour, minute: defaultReminderMinute)
    }

    /// 表单预填用：把用户设定的默认提醒点落到 day 当天。
    /// 「没有提醒」和「提醒正好是默认时间」仍由 reminderTime 是否为 nil 区分。
    func reminderDate(on day: Date, calendar: Calendar = .current) -> Date {
        defaultReminderTime.reminderDate(on: day, calendar: calendar)
    }
}

extension DateComponents {
    /// 把自身携带的时分落到 day 当天，得到表单预填用的提醒时刻。
    func reminderDate(on day: Date, calendar: Calendar = .current) -> Date {
        calendar.date(
            bySettingHour: hour ?? 9,
            minute: minute ?? 0,
            second: 0,
            of: day
        ) ?? day
    }

    /// 拿不到 UserSettings 记录时的兜底，与模型初始化默认值一致。
    static let fallbackReminder = DateComponents(hour: 9, minute: 0)
}

/// 首启动时创建唯一的 UserSettings 记录，并把历史遗留的多余记录收敛成一条。
///
/// 必须显式 save：之前只 insert 就交给 SwiftData autosave，用户在真正落盘前
/// 杀掉进程，下次启动会再次掉进 onboarding，看起来像设置没被保存。
enum SettingsBootstrap {
    @discardableResult
    static func ensureSettings(in context: ModelContext) throws -> UserSettings {
        let existing = try context.fetch(FetchDescriptor<UserSettings>())

        let keep: UserSettings
        if existing.isEmpty {
            let created = UserSettings()
            context.insert(created)
            keep = created
            AppLogger.data("Initialized UserSettings: \(created.id)")
        } else {
            // 多条时保留最早创建的那条：它最可能是用户真实数据所在。
            keep = existing.min { lhs, rhs in
                if lhs.createdAt != rhs.createdAt { return lhs.createdAt < rhs.createdAt }
                return lhs.id.uuidString < rhs.id.uuidString
            } ?? existing[0]
        }

        for extra in existing where extra.id != keep.id {
            context.delete(extra)
            AppLogger.data("Removed duplicate UserSettings: \(extra.id)")
        }

        try context.save()
        return keep
    }
}
