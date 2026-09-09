import Foundation
import SwiftData

enum SettingsDataCoordinator {
    static func exportBackup(planItems: [PlanItem], notes: [Note], settings: UserSettings?) throws -> URL {
        try JSONBackupService.exportBackup(planItems: planItems, notes: notes, settings: settings)
    }

    static func importBackup(
        from url: URL,
        existingPlanItems: [PlanItem],
        existingNotes: [Note],
        existingSettings: UserSettings?,
        in context: ModelContext
    ) throws {
        try JSONBackupService.restoreBackup(
            from: url,
            existingPlanItems: existingPlanItems,
            existingNotes: existingNotes,
            existingSettings: existingSettings,
            in: context
        )
    }

    static func clearAllData(planItems: [PlanItem], notes: [Note], in context: ModelContext) throws {
        planItems.forEach { NotificationService.cancelTaskReminder(for: $0) }
        planItems.forEach { context.delete($0) }
        notes.forEach { context.delete($0) }
        try context.save()
    }
}

enum JSONBackupService {
    static func exportBackup(
        planItems: [PlanItem],
        notes: [Note],
        settings: UserSettings?
    ) throws -> URL {
        let envelope = BackupEnvelope(
            exportedAt: Date(),
            planItems: planItems.map(PlanItemBackup.init),
            notes: notes.map(NoteBackup.init),
            settings: settings.map(UserSettingsBackup.init)
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601

        let data = try encoder.encode(envelope)
        let filename = "1Day-Backup-\(filenameDateFormatter.string(from: Date())).json"
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(filename)
        try data.write(to: url, options: [.atomic])
        return url
    }

    static func restoreBackup(
        from url: URL,
        existingPlanItems: [PlanItem],
        existingNotes: [Note],
        existingSettings: UserSettings?,
        in context: ModelContext
    ) throws {
        let didStartAccessing = url.startAccessingSecurityScopedResource()
        defer {
            if didStartAccessing {
                url.stopAccessingSecurityScopedResource()
            }
        }

        let data = try Data(contentsOf: url)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let envelope = try decoder.decode(BackupEnvelope.self, from: data)

        for item in existingPlanItems {
            NotificationService.cancelTaskReminder(for: item)
            context.delete(item)
        }
        for note in existingNotes {
            context.delete(note)
        }

        for backup in envelope.planItems {
            let item = backup.makePlanItem()
            context.insert(item)
            NotificationService.scheduleTaskReminder(for: item)
        }

        for backup in envelope.notes {
            context.insert(backup.makeNote())
        }

        if let settingsBackup = envelope.settings {
            let targetSettings = existingSettings ?? UserSettings()
            settingsBackup.apply(to: targetSettings)
            if existingSettings == nil {
                context.insert(targetSettings)
            }
        }

        try context.save()
    }

    static func clearUserData(
        planItems: [PlanItem],
        notes: [Note],
        in context: ModelContext
    ) throws {
        for item in planItems {
            NotificationService.cancelTaskReminder(for: item)
            context.delete(item)
        }
        for note in notes {
            context.delete(note)
        }
        try context.save()
    }

    private static let filenameDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return formatter
    }()
}

private struct BackupEnvelope: Codable {
    var schemaVersion = 1
    var exportedAt: Date
    var planItems: [PlanItemBackup]
    var notes: [NoteBackup]
    var settings: UserSettingsBackup?
}

private struct PlanItemBackup: Codable {
    var id: UUID
    var title: String
    var notes: String
    var dueDate: Date?
    var statusRawValue: String
    var priorityRawValue: String
    var reminderTime: Date?
    var createdAt: Date
    var updatedAt: Date
    var completedAt: Date?

    init(_ item: PlanItem) {
        id = item.id
        title = item.title
        notes = item.notes
        dueDate = item.dueDate
        statusRawValue = item.statusRawValue
        priorityRawValue = item.priorityRawValue
        reminderTime = item.reminderTime
        createdAt = item.createdAt
        updatedAt = item.updatedAt
        completedAt = item.completedAt
    }

    func makePlanItem() -> PlanItem {
        let item = PlanItem(
            title: title,
            notes: notes,
            dueDate: dueDate,
            status: ItemStatus(rawValue: statusRawValue) ?? .pending,
            priority: Priority(rawValue: priorityRawValue) ?? .none,
            reminderTime: reminderTime
        )
        item.id = id
        item.statusRawValue = statusRawValue
        item.priorityRawValue = priorityRawValue
        item.createdAt = createdAt
        item.updatedAt = updatedAt
        item.completedAt = completedAt
        return item
    }
}

private struct NoteBackup: Codable {
    var id: UUID
    var title: String
    var content: String
    var createdAt: Date
    var updatedAt: Date

    init(_ note: Note) {
        id = note.id
        title = note.title
        content = note.content
        createdAt = note.createdAt
        updatedAt = note.updatedAt
    }

    func makeNote() -> Note {
        let note = Note(title: title, content: content)
        note.id = id
        note.createdAt = createdAt
        note.updatedAt = updatedAt
        return note
    }
}

private struct UserSettingsBackup: Codable {
    var id: UUID
    var dataSchemaVersion: Int
    var nickname: String
    var avatarSymbolName: String
    var avatarImageData: Data?
    var languageRawValue: String
    var appearanceRawValue: String
    var defaultReminderHour: Int
    var defaultReminderMinute: Int
    var selectedAIProviderRawValue: String
    var selectedAIModel: String
    var aiProcessingModeRawValue: String
    var isAIConfigured: Bool
    var hasCompletedOnboarding: Bool
    var createdAt: Date
    var updatedAt: Date

    init(_ settings: UserSettings) {
        id = settings.id
        dataSchemaVersion = settings.dataSchemaVersion
        nickname = settings.nickname
        avatarSymbolName = settings.avatarSymbolName
        avatarImageData = settings.avatarImageData
        languageRawValue = settings.languageRawValue
        appearanceRawValue = settings.appearanceRawValue
        defaultReminderHour = settings.defaultReminderHour
        defaultReminderMinute = settings.defaultReminderMinute
        selectedAIProviderRawValue = settings.selectedAIProviderRawValue
        selectedAIModel = settings.selectedAIModel
        aiProcessingModeRawValue = settings.aiProcessingModeRawValue
        isAIConfigured = settings.isAIConfigured
        hasCompletedOnboarding = settings.hasCompletedOnboarding
        createdAt = settings.createdAt
        updatedAt = settings.updatedAt
    }

    func apply(to settings: UserSettings) {
        settings.dataSchemaVersion = dataSchemaVersion
        settings.nickname = nickname
        settings.avatarSymbolName = avatarSymbolName
        settings.avatarImageData = avatarImageData
        settings.languageRawValue = languageRawValue
        settings.appearanceRawValue = appearanceRawValue
        settings.defaultReminderHour = defaultReminderHour
        settings.defaultReminderMinute = defaultReminderMinute
        settings.selectedAIProviderRawValue = selectedAIProviderRawValue
        settings.selectedAIModel = selectedAIModel
        settings.aiProcessingModeRawValue = aiProcessingModeRawValue
        settings.isAIConfigured = isAIConfigured
        settings.hasCompletedOnboarding = hasCompletedOnboarding
        settings.createdAt = createdAt
        settings.updatedAt = updatedAt
    }
}
