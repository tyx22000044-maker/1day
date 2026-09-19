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

enum BackupRestoreError: LocalizedError, Equatable {
    case duplicateRecordID(String)

    var errorDescription: String? {
        switch self {
        case .duplicateRecordID(let id):
            return "备份文件中有重复的记录（\(id)），已停止导入。"
        }
    }

    var recoverySuggestion: String? {
        "你的现有数据没有被改动。请重新导出一份备份，或删掉重复的那条记录后再试。"
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

    /// 恢复备份，按「先验后改」的事务顺序执行。
    ///
    /// 旧实现先删库再插入，任何一步失败都会留下半截状态：原数据已经没了，
    /// 恢复数据可能只进来一部分，而通知早在保存之前就已经排好，指向并不存在的任务。
    /// 现在：解码 + 校验 + 构造全部成功后才开始改动；保存失败则 rollback 回到改动前，
    /// 通知只在真正落盘之后重建。
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

        // 阶段一：完全不触碰 context，任何失败都还是「原样」。
        let restored = try prepareRestorePayload(from: url)
        // 待删对象的 id 必须提前取，删除并保存之后它们就不能再被访问了。
        let replacedReminderIDs = existingPlanItems.map(\.id)

        // 阶段二：关掉 autosave，让整次替换成为一个可回滚的事务。
        let hadAutosave = context.autosaveEnabled
        context.autosaveEnabled = false
        defer { context.autosaveEnabled = hadAutosave }

        for item in existingPlanItems { context.delete(item) }
        for note in existingNotes { context.delete(note) }

        for item in restored.planItems { context.insert(item) }
        for note in restored.notes { context.insert(note) }

        if let settingsBackup = restored.settings {
            let targetSettings = existingSettings ?? UserSettings()
            settingsBackup.apply(to: targetSettings)
            if existingSettings == nil {
                context.insert(targetSettings)
            }
        }

        do {
            try context.save()
        } catch {
            // 所有改动都还没进库，rollback 后原数据仍然是唯一事实。
            context.rollback()
            AppLogger.dataError("备份恢复保存失败，已回滚，原数据保持不变: \(error.localizedDescription)")
            throw error
        }

        // 阶段三：只有确认落盘，才重建提醒，避免通知指向没保存成功的任务。
        for itemID in replacedReminderIDs { NotificationService.cancelTaskReminder(itemID: itemID) }
        for item in restored.planItems { NotificationService.scheduleTaskReminder(for: item) }
        AppLogger.data("Restored backup: \(restored.planItems.count) tasks, \(restored.notes.count) notes")
    }

    /// 解码 + 校验 + 构造出待写入的对象；不修改 context。
    private static func prepareRestorePayload(from url: URL) throws -> RestorePayload {
        let data = try Data(contentsOf: url)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let envelope = try decoder.decode(BackupEnvelope.self, from: data)

        var seenIDs = Set<UUID>()
        var planItems: [PlanItem] = []
        planItems.reserveCapacity(envelope.planItems.count)
        for backup in envelope.planItems {
            guard seenIDs.insert(backup.id).inserted else {
                throw BackupRestoreError.duplicateRecordID(backup.id.uuidString)
            }
            planItems.append(backup.makePlanItem())
        }

        var noteIDs = Set<UUID>()
        var notes: [Note] = []
        notes.reserveCapacity(envelope.notes.count)
        for backup in envelope.notes {
            guard noteIDs.insert(backup.id).inserted else {
                throw BackupRestoreError.duplicateRecordID(backup.id.uuidString)
            }
            notes.append(backup.makeNote())
        }

        return RestorePayload(
            planItems: planItems,
            notes: notes,
            settings: envelope.settings
        )
    }

    private struct RestorePayload {
        let planItems: [PlanItem]
        let notes: [Note]
        let settings: UserSettingsBackup?
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
