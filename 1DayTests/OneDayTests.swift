import Foundation
import SwiftData
import Testing
@testable import OneDay

@Test func planItemCreation() async throws {
    let item = PlanItem(title: "Test Task", dueDate: Date())
    #expect(item.title == "Test Task")
    #expect(item.status == .pending)
    #expect(item.priority == .none)
    #expect(!item.isCompleted)
}

@Test func planItemCompletion() async throws {
    let item = PlanItem(title: "Test Task")
    item.status = .completed
    #expect(item.isCompleted)
    #expect(item.completedAt != nil)

    item.status = .pending
    #expect(!item.isCompleted)
    #expect(item.completedAt == nil)
}

@Test func noteDisplayTitle() async throws {
    let emptyNote = Note()
    #expect(emptyNote.displayTitle == "空笔记")

    let titledNote = Note(title: "My Note")
    #expect(titledNote.displayTitle == "My Note")

    let contentOnlyNote = Note(content: "Some content here")
    #expect(contentOnlyNote.displayTitle == "Some content here")
}

@Test func planDraftValidationRejectsBlankTitle() async throws {
    let draft = PlanItemDraft(title: "   ", dueDate: nil)
    #expect(PlanItemValidator.error(for: draft) != nil)
}

@Test func planDateHelpersUseReferenceDate() async throws {
    let reference = Calendar.current.startOfDay(for: .now)
    let item = PlanItem(title: "回看任务", dueDate: reference)
    #expect(item.isDue(on: reference))
    #expect(!item.isOverdue(asOf: reference))
}

// MARK: - F-02 首启动设置必须立即落盘

private func makeInMemoryContainer() throws -> ModelContainer {
    let configuration = ModelConfiguration(
        schema: OneDayModelContainer.schema,
        isStoredInMemoryOnly: true
    )
    return OneDayModelContainer.make(configuration: configuration).container
}

@Test func settingsBootstrapPersistsImmediately() throws {
    let container = try makeInMemoryContainer()
    let context = ModelContext(container)

    let created = try SettingsBootstrap.ensureSettings(in: context)

    // 另一个 context 看不见未保存的改动，能取到就证明确实 save 了。
    let probe = ModelContext(container)
    let fetched = try probe.fetch(FetchDescriptor<UserSettings>())
    #expect(fetched.count == 1)
    #expect(fetched.first?.id == created.id)
}

@Test func settingsBootstrapIsIdempotentAcrossRepeatedLaunches() throws {
    let container = try makeInMemoryContainer()
    let context = ModelContext(container)

    let first = try SettingsBootstrap.ensureSettings(in: context)
    // onAppear 可能被多次触发，模拟重复启动。
    let second = try SettingsBootstrap.ensureSettings(in: context)
    let third = try SettingsBootstrap.ensureSettings(in: ModelContext(container))

    #expect(first.id == second.id)
    #expect(second.id == third.id)
    #expect(try context.fetch(FetchDescriptor<UserSettings>()).count == 1)
}

// MARK: - F-06 引导页跳过不能丢掉已输入的 key

@Test func onboardingSkipCommitsTypedAPIKey() throws {
    let service = LocalAIConfigurationService(keychain: InMemoryKeychainService())
    let settings = UserSettings()
    settings.selectedAIProvider = .qwen

    let configured = AIConfigurationCoordinator.commitOnboardingAPIKey(
        "  qwen-sk-abcdefghij  ",
        on: settings,
        using: service
    )

    #expect(configured)
    #expect(settings.isAIConfigured)
    #expect(try service.readAPIKey(provider: .qwen) == "qwen-sk-abcdefghij")
}

@Test func onboardingSkipWithEmptyInputKeepsExistingKey() throws {
    let service = LocalAIConfigurationService(keychain: InMemoryKeychainService())
    let settings = UserSettings()
    settings.selectedAIProvider = .claude
    try service.saveAPIKey("claude-key-1234567890", provider: .claude)

    // 留空 = 不动已有 key，而不是把它当成「用户想删除」。
    #expect(AIConfigurationCoordinator.commitOnboardingAPIKey("", on: settings, using: service))
    #expect(try service.readAPIKey(provider: .claude) == "claude-key-1234567890")
}

@Test func onboardingSkipWithTooShortKeyIsNotMarkedConfigured() throws {
    let service = LocalAIConfigurationService(keychain: InMemoryKeychainService())
    let settings = UserSettings()
    settings.selectedAIProvider = .kimi

    let configured = AIConfigurationCoordinator.commitOnboardingAPIKey("abc", on: settings, using: service)
    #expect(configured == false)
    #expect(settings.isAIConfigured == false)
}

// MARK: - F-05 服务商切换后 AI 状态必须按 Keychain 重算

private final class InMemoryKeychainService: KeychainService, @unchecked Sendable {
    private(set) var store: [String: String] = [:]

    func save(_ value: String, account: String) throws { store[account] = value }
    func read(account: String) throws -> String? { store[account] }
    func delete(account: String) throws { store[account] = nil }
}

@Test func providerSwitchRecomputesConfiguredFlagFromKeychain() throws {
    let service = LocalAIConfigurationService(keychain: InMemoryKeychainService())
    let settings = UserSettings()

    try service.saveAPIKey("claude-key-1234567890", provider: .claude)
    settings.selectedAIProvider = .claude
    settings.isAIConfigured = true

    // 切到本机没有 key 的服务商：状态必须立刻回到「未配置」。
    let switched = AIConfigurationCoordinator.switchProvider(to: .deepseek, on: settings, using: service)
    #expect(switched == false)
    #expect(settings.isAIConfigured == false)
    #expect(settings.selectedAIModel == "deepseek-chat")

    // 切回 Claude：本机已有的 key 要重新被认出来，不能停在 false。
    let back = AIConfigurationCoordinator.switchProvider(to: .claude, on: settings, using: service)
    #expect(back)
    #expect(settings.isAIConfigured)
    #expect(settings.selectedAIModel == "claude-sonnet-4-6")
}

@Test func deletingKeyAndRelaunchingDoesNotLeaveStaleConfiguredFlag() throws {
    let service = LocalAIConfigurationService(keychain: InMemoryKeychainService())
    let settings = UserSettings()
    try service.saveAPIKey("kimi-key-1234567890", provider: .kimi)
    settings.selectedAIProvider = .kimi
    settings.isAIConfigured = AIConfigurationCoordinator.revalidate(settings: settings, using: service)
    #expect(settings.isAIConfigured)

    try service.deleteAPIKey(provider: .kimi)
    // 模拟重启：启动校准要把上一次运行留下的 true 纠正过来。
    let revalidated = AIConfigurationCoordinator.revalidate(settings: settings, using: service)
    #expect(revalidated == false)
    #expect(settings.isAIConfigured == false)
}

// MARK: - F-04 备份必须完整覆盖反馈偏好

@Test func feedbackPreferencesSurviveBackupRoundTrip() throws {
    let sourceContext = ModelContext(try makeInMemoryContainer())
    let sourceSettings = try SettingsBootstrap.ensureSettings(in: sourceContext)
    sourceSettings.isHapticsEnabled = false
    sourceSettings.isSoundEffectsEnabled = false
    try sourceContext.save()

    let url = try JSONBackupService.exportBackup(planItems: [], notes: [], settings: sourceSettings)

    // 恢复侧当作另一台设备：出厂默认两个开关都开着。
    let targetContext = ModelContext(try makeInMemoryContainer())
    let targetSettings = try SettingsBootstrap.ensureSettings(in: targetContext)
    #expect(targetSettings.isHapticsEnabled)
    #expect(targetSettings.isSoundEffectsEnabled)

    try restore(url, into: targetContext)

    #expect(targetSettings.isHapticsEnabled == false)
    #expect(targetSettings.isSoundEffectsEnabled == false)
}

@Test func legacyBackupWithoutFeedbackFieldsKeepsCurrentPreferences() throws {
    let targetContext = ModelContext(try makeInMemoryContainer())
    let targetSettings = try SettingsBootstrap.ensureSettings(in: targetContext)
    targetSettings.isHapticsEnabled = false
    try targetContext.save()

    // v1 备份：settings 里没有触觉/声音两个键。
    let legacy = """
    {"schemaVersion":1,"exportedAt":"2026-01-01T00:00:00Z","planItems":[],"notes":[],\
    "settings":{"id":"\(UUID().uuidString)","dataSchemaVersion":1,"nickname":"小陈",\
    "avatarSymbolName":"person.crop.circle","languageRawValue":"system","appearanceRawValue":"system",\
    "defaultReminderHour":9,"defaultReminderMinute":0,"selectedAIProviderRawValue":"claude",\
    "selectedAIModel":"claude-sonnet","aiProcessingModeRawValue":"ruleFirst","isAIConfigured":false,\
    "hasCompletedOnboarding":true,"createdAt":"2026-01-01T00:00:00Z","updatedAt":"2026-01-01T00:00:00Z"}}
    """
    try restore(try writeBackupJSON(legacy), into: targetContext)

    // 缺字段不能把用户已经关掉的触觉静默改回去，其余字段仍要照常恢复。
    #expect(targetSettings.isHapticsEnabled == false)
    #expect(targetSettings.nickname == "小陈")
    #expect(targetSettings.hasCompletedOnboarding)
}

// MARK: - F-03 备份恢复必须是可回滚的单一事务

private func writeBackupJSON(_ json: String) throws -> URL {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("1Day-backup-\(UUID().uuidString).json")
    try Data(json.utf8).write(to: url)
    return url
}

private func backupItemJSON(id: String, title: String) -> String {
    """
    {"id":"\(id)","title":"\(title)","notes":"","statusRawValue":"pending",\
    "priorityRawValue":"none","createdAt":"2026-01-01T00:00:00Z","updatedAt":"2026-01-01T00:00:00Z"}
    """
}

private func backupEnvelopeJSON(planItems: [String], notes: [String] = []) -> String {
    """
    {"schemaVersion":1,"exportedAt":"2026-01-01T00:00:00Z",\
    "planItems":[\(planItems.joined(separator: ","))],"notes":[\(notes.joined(separator: ","))]}
    """
}

private func seedRestoreContext() throws -> (container: ModelContainer, context: ModelContext) {
    let container = try makeInMemoryContainer()
    let context = ModelContext(container)
    context.insert(PlanItem(title: "原有任务"))
    context.insert(Note(title: "原有笔记", content: "原内容"))
    try context.save()
    return (container, context)
}

private func restore(_ url: URL, into context: ModelContext) throws {
    let items = try context.fetch(FetchDescriptor<PlanItem>())
    let notes = try context.fetch(FetchDescriptor<Note>())
    let settings = try context.fetch(FetchDescriptor<UserSettings>()).first
    try JSONBackupService.restoreBackup(
        from: url,
        existingPlanItems: items,
        existingNotes: notes,
        existingSettings: settings,
        in: context
    )
}

@Test func malformedBackupLeavesExistingDataUntouched() throws {
    let (_, context) = try seedRestoreContext()
    // 真实 App 里传进来的是 mainContext，autosave 是开着的。
    context.autosaveEnabled = true
    let url = try writeBackupJSON("{ this is not json")

    var didThrow = false
    do {
        try restore(url, into: context)
    } catch {
        didThrow = true
    }

    #expect(didThrow)
    let items = try context.fetch(FetchDescriptor<PlanItem>())
    let notes = try context.fetch(FetchDescriptor<Note>())
    #expect(items.map(\.title) == ["原有任务"])
    #expect(notes.map(\.title) == ["原有笔记"])
    // 失败后不能把 context 永久留在关闭 autosave 的状态。
    #expect(context.autosaveEnabled)
}

@Test func duplicateRecordIDsAreRejectedBeforeAnyMutation() throws {
    let (_, context) = try seedRestoreContext()
    let url = try writeBackupJSON(
        backupEnvelopeJSON(planItems: [
            backupItemJSON(id: UUID().uuidString, title: "第一条"),
            backupItemJSON(id: UUID().uuidString, title: "第二条"),
        ])
    )
    try restore(url, into: context)
    #expect(try context.fetch(FetchDescriptor<PlanItem>()).map(\.title).sorted() == ["第一条", "第二条"].sorted())

    // 同一个 id 出现两次会撞上 @Attribute(.unique)，旧实现此时已经删完原数据。
    let shared = UUID().uuidString
    let badURL = try writeBackupJSON(
        backupEnvelopeJSON(planItems: [
            backupItemJSON(id: shared, title: "重复甲"),
            backupItemJSON(id: shared, title: "重复乙"),
        ])
    )

    var caught: BackupRestoreError?
    do {
        try restore(badURL, into: context)
    } catch let error as BackupRestoreError {
        caught = error
    }

    #expect(caught == .duplicateRecordID(shared))
    // 原备份数据必须还在，而不是被上一轮导入后再删空。
    let survivors = try context.fetch(FetchDescriptor<PlanItem>()).map(\.title).sorted()
    #expect(survivors == ["第一条", "第二条"].sorted())
}

@Test func validBackupReplacesAndPersistsInOneCommit() throws {
    let (container, context) = try seedRestoreContext()
    context.autosaveEnabled = true
    let url = try writeBackupJSON(backupEnvelopeJSON(
        planItems: [backupItemJSON(id: UUID().uuidString, title: "导入任务")],
        notes: [
            """
            {"id":"\(UUID().uuidString)","title":"导入笔记","content":"新内容",\
            "createdAt":"2026-01-01T00:00:00Z","updatedAt":"2026-01-01T00:00:00Z"}
            """
        ]
    ))

    try restore(url, into: context)

    // 用另一个 context 验证确实已提交，而不是只活在待保存的事务里。
    let probe = ModelContext(container)
    #expect(try probe.fetch(FetchDescriptor<PlanItem>()).map(\.title) == ["导入任务"])
    #expect(try probe.fetch(FetchDescriptor<Note>()).map(\.title) == ["导入笔记"])
    #expect(context.autosaveEnabled)
}

// MARK: - F-01 持久化降级必须可见

private func makeTempDirectory() throws -> URL {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("1Day-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    return directory
}

@Test func persistedHealthIsTheNormalPath() throws {
    let directory = try makeTempDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }

    let configuration = ModelConfiguration(
        schema: OneDayModelContainer.schema,
        url: directory.appendingPathComponent("data.sqlite")
    )
    let outcome = OneDayModelContainer.make(configuration: configuration)

    #expect(outcome.health == .persisted)
    #expect(outcome.health.isPersistingUserData)
}

@Test func unwritableStoreFallsBackToMemoryButReportsIt() throws {
    // 把 store 路径指向一个已存在的目录：SQLite 无法在其中打开数据库文件，
    // 这正是「沙盒不可写」的可复现代身。
    let directory = try makeTempDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }

    let configuration = ModelConfiguration(schema: OneDayModelContainer.schema, url: directory)
    let outcome = OneDayModelContainer.make(configuration: configuration)

    // 若降级被静默吞掉，health 会是 .persisted，下一条断言直接失败。
    #expect(outcome.health.isPersistingUserData == false)
    guard case .inMemoryOnly(let reason) = outcome.health else { return }
    #expect(!reason.isEmpty)

    // 降级容器仍可读写，App 才能继续提供「导出当前数据」的出路。
    let context = ModelContext(outcome.container)
    context.insert(PlanItem(title: "内存模式仍可记录"))
    try context.save()
    let fetched = try context.fetch(FetchDescriptor<PlanItem>())
    #expect(fetched.contains { $0.title == "内存模式仍可记录" })
}
