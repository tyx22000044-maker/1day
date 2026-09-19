import Foundation
import SwiftData

@Model
final class UserSettings {
    static let currentDataSchemaVersion = 1

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

    init(nickname: String = "",
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
        self.id = UUID()
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
}

/// 首启动时创建唯一的 UserSettings 记录。
///
/// 必须显式 save：之前只 insert 就交给 SwiftData autosave，用户在真正落盘前
/// 杀掉进程，下次启动会再次掉进 onboarding，看起来像设置没被保存。
enum SettingsBootstrap {
    @discardableResult
    static func ensureSettings(in context: ModelContext) throws -> UserSettings {
        if let existing = try context.fetch(FetchDescriptor<UserSettings>()).first {
            return existing
        }
        let settings = UserSettings()
        context.insert(settings)
        try context.save()
        AppLogger.data("Initialized UserSettings: \(settings.id)")
        return settings
    }
}
