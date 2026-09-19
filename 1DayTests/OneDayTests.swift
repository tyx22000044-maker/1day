import Foundation
import SwiftData
import Testing
import UIKit
import UserNotifications
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

// MARK: - F-20 笔记草稿清理规则

@Test func onlyNeverWrittenDraftsAreDiscardedOnDeparture() {
    // 点 + 建出来、一个字没写就返回 → 清理草稿
    #expect(NoteEditorPolicy.discardEmptyDraftOnDeparture(openedEmpty: true, isNowEmpty: true))
    // 曾经有内容、被用户清空 → 必须留着，删除交给列表里的显式操作
    #expect(!NoteEditorPolicy.discardEmptyDraftOnDeparture(openedEmpty: false, isNowEmpty: true))
    #expect(!NoteEditorPolicy.discardEmptyDraftOnDeparture(openedEmpty: true, isNowEmpty: false))
    #expect(!NoteEditorPolicy.discardEmptyDraftOnDeparture(openedEmpty: false, isNowEmpty: false))
}

@Test func emptiedExistingNoteSurvivesTheDepartureCleanup() throws {
    let container = try makeInMemoryContainer()
    let context = ModelContext(container)
    let note = Note(title: "会议记录", content: "决定周五交付")
    context.insert(note)
    try context.save()

    let openedEmpty = note.isEmpty
    note.content = ""
    note.title = ""
    if NoteEditorPolicy.discardEmptyDraftOnDeparture(openedEmpty: openedEmpty, isNowEmpty: note.isEmpty) {
        context.delete(note)
    }
    try context.save()

    let remaining = try ModelContext(container).fetch(FetchDescriptor<Note>())
    #expect(remaining.count == 1)
    #expect(remaining.first?.displayTitle == "空笔记")
}

@Test func unwrittenDraftIsStillCleanedUp() throws {
    let container = try makeInMemoryContainer()
    let context = ModelContext(container)
    let draft = Note()
    context.insert(draft)
    try context.save()

    if NoteEditorPolicy.discardEmptyDraftOnDeparture(openedEmpty: draft.isEmpty, isNowEmpty: draft.isEmpty) {
        context.delete(draft)
    }
    try context.save()

    #expect(try ModelContext(container).fetch(FetchDescriptor<Note>()).isEmpty)
}

// MARK: - F-19 UserSettings 单例保证

@Test func newUserSettingsAllShareTheSingletonID() {
    #expect(UserSettings().id == UserSettings.singletonID)
    #expect(UserSettings(nickname: "甲").id == UserSettings.singletonID)
}

@Test func bootstrapCollapsesLegacyDuplicateRecordsIntoTheEarliest() throws {
    let container = try makeInMemoryContainer()
    let context = ModelContext(container)

    // 模拟历史脏数据：两条不同 id 的设置。各视图都用 settings.first 取当前设置，
    // 留着就会有人读到「早期昵称」、有人读到「后来多出来的」。
    let earlier = UserSettings(id: UUID(), nickname: "早期昵称")
    earlier.createdAt = Date(timeIntervalSince1970: 1_000)
    let later = UserSettings(id: UUID(), nickname: "后来多出来的")
    later.createdAt = Date(timeIntervalSince1970: 5_000)
    context.insert(earlier)
    context.insert(later)
    try context.save()
    #expect(try context.fetch(FetchDescriptor<UserSettings>()).count == 2)

    let kept = try SettingsBootstrap.ensureSettings(in: context)

    #expect(kept.id == earlier.id)
    #expect(kept.nickname == "早期昵称")
    #expect(try context.fetch(FetchDescriptor<UserSettings>()).count == 1)

    // 再启动一次也不能又变出第二条。
    _ = try SettingsBootstrap.ensureSettings(in: ModelContext(container))
    #expect(try ModelContext(container).fetch(FetchDescriptor<UserSettings>()).count == 1)
}

// MARK: - F-18 schema 版本与迁移计划

@Test func schemaRegistersEveryPersistentModel() {
    let types = AppSchema.modelTypes
    #expect(types.count == 4)
    #expect(types.contains { $0 == PlanItem.self })
    #expect(types.contains { $0 == Note.self })
    #expect(types.contains { $0 == UserSettings.self })
    // AIChatMessage 定义在 Services/AI 下，漏登记就会「聊天看着有、重启就没了」。
    #expect(types.contains { $0 == AIChatMessage.self })
}

@Test func migrationPlanStartsAtV1WithNoStagesYet() {
    #expect(OneDaySchemaV1.versionIdentifier == Schema.Version(1, 0, 0))
    #expect(OneDayMigrationPlan.schemas.count == 1)
    // 现在没有可迁移的旧版本；改字段时必须在这里补 stage，而不是指望自动兼容。
    #expect(OneDayMigrationPlan.stages.isEmpty)
}

@Test func containerReopensTheSameStoreThroughTheMigrationPlanWithoutLosingRows() throws {
    let directory = try makeTempDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let storeURL = directory.appendingPathComponent("data.sqlite")

    let first = OneDayModelContainer.make(configuration: ModelConfiguration(schema: AppSchema.current, url: storeURL))
    #expect(first.health == .persisted)
    let writeContext = ModelContext(first.container)
    writeContext.insert(Note(title: "迁移计划下的笔记", content: "内容"))
    try writeContext.save()

    // 重新打开同一个 store：这才是加字段时真正会走的路径。
    let second = OneDayModelContainer.make(configuration: ModelConfiguration(schema: AppSchema.current, url: storeURL))
    #expect(second.health == .persisted)
    let fetched = try ModelContext(second.container).fetch(FetchDescriptor<Note>())
    #expect(fetched.map(\.title) == ["迁移计划下的笔记"])
}

// MARK: - F-17 备份版本闸门与字段预检

private func rawBackupItemJSON(
    id: String = UUID().uuidString,
    title: String = "任务",
    status: String = "pending",
    priority: String = "none",
    dueDate: String? = nil,
    reminderTime: String? = nil,
    completedAt: String? = nil
) -> String {
    var fields = [
        "\"id\":\"\(id)\"",
        "\"title\":\"\(title)\"",
        "\"notes\":\"\"",
        "\"statusRawValue\":\"\(status)\"",
        "\"priorityRawValue\":\"\(priority)\"",
        "\"createdAt\":\"2026-01-01T00:00:00Z\"",
        "\"updatedAt\":\"2026-01-01T00:00:00Z\""
    ]
    if let dueDate { fields.append("\"dueDate\":\"\(dueDate)\"") }
    if let reminderTime { fields.append("\"reminderTime\":\"\(reminderTime)\"") }
    if let completedAt { fields.append("\"completedAt\":\"\(completedAt)\"") }
    return "{\(fields.joined(separator: ","))}"
}

private func envelopeJSON(planItems: [String], settings: String? = nil, schemaVersion: Int = 2) -> String {
    var document = """
    {"schemaVersion":\(schemaVersion),"exportedAt":"2026-01-01T00:00:00Z",\
    "planItems":[\(planItems.joined(separator: ","))],"notes":[]
    """
    if let settings { document += ",\"settings\":\(settings)" }
    document += "}"
    return document
}

private func restoreError(_ json: String, into context: ModelContext) -> BackupRestoreError? {
    guard let url = try? writeBackupJSON(json) else { return .duplicateRecordID("url-failed") }
    do {
        try restore(url, into: context)
        return nil
    } catch let error as BackupRestoreError {
        return error
    } catch {
        return nil
    }
}

@Test func futureSchemaVersionIsRefusedWithoutTouchingExistingData() throws {
    let (_, context) = try seedRestoreContext()

    let error = restoreError(envelopeJSON(planItems: [], schemaVersion: 99), into: context)

    #expect(error == .unsupportedSchemaVersion(99))
    #expect(try context.fetch(FetchDescriptor<PlanItem>()).map(\.title) == ["原有任务"])
}

@Test func unknownEnumRawValueIsRefusedInsteadOfSilentlyCoerced() throws {
    let (_, context) = try seedRestoreContext()

    // 旧实现把读不懂的 status 变成 pending，用户会看到一条状态被偷偷改写的任务。
    let error = restoreError(
        envelopeJSON(planItems: [rawBackupItemJSON(title: "奇怪的", status: "archived")]),
        into: context
    )

    #expect(error == .invalidField(field: "status", value: "archived"))
    #expect(try context.fetch(FetchDescriptor<PlanItem>()).map(\.title) == ["原有任务"])
}

@Test func outOfRangeReminderHourIsRefused() throws {
    let (_, context) = try seedRestoreContext()
    let settings = """
    {"id":"\(UUID().uuidString)","dataSchemaVersion":1,"nickname":"","avatarSymbolName":"person.crop.circle",\
    "languageRawValue":"system","appearanceRawValue":"system","defaultReminderHour":25,"defaultReminderMinute":0,\
    "selectedAIProviderRawValue":"claude","selectedAIModel":"claude-sonnet","aiProcessingModeRawValue":"ruleFirst",\
    "isAIConfigured":false,"hasCompletedOnboarding":true,"createdAt":"2026-01-01T00:00:00Z","updatedAt":"2026-01-01T00:00:00Z"}
    """

    let error = restoreError(envelopeJSON(planItems: [], settings: settings), into: context)

    #expect(error == .invalidField(field: "defaultReminderHour", value: "25"))
    #expect(try context.fetch(FetchDescriptor<Note>()).count == 1)
}

@Test func completedStatusWithoutTimestampIsRepairedOnRestore() throws {
    let (_, context) = try seedRestoreContext()
    let item = rawBackupItemJSON(
        title: "忘了记完成时间",
        status: "completed",
        dueDate: "2026-01-01T00:00:00Z"
    )

    try restore(try writeBackupJSON(envelopeJSON(planItems: [item])), into: context)

    let restored = try context.fetch(FetchDescriptor<PlanItem>()).first
    #expect(restored?.isCompleted == true)
    // 完成态必须配一个完成时间，否则「今天完成了几件」会漏掉它。
    #expect(restored?.completedAt != nil)
}

@Test func reminderWithoutDueDateIsDroppedOnRestore() throws {
    let (_, context) = try seedRestoreContext()
    let item = rawBackupItemJSON(title: "没有日期却带提醒", reminderTime: "2026-07-01T09:00:00Z")

    try restore(try writeBackupJSON(envelopeJSON(planItems: [item])), into: context)

    let restored = try context.fetch(FetchDescriptor<PlanItem>()).first
    // 没有日期的任务不会有本地通知，留着提醒时间只是骗人。
    #expect(restored?.isUnscheduled == true)
    #expect(restored?.reminderTime == nil)
}

// MARK: - F-16 Claude 多模态请求保留多轮历史

@Test func claudeVisionKeepsHistoryAndAttachesImagesToTheCurrentTurn() throws {
    let messages: [AIClientMessage] = [
        AIClientMessage(role: .system, content: "你是 1Day 助手"),
        AIClientMessage(role: .user, content: "明天下午开会"),
        AIClientMessage(role: .assistant, content: "已记为草稿"),
        AIClientMessage(role: .user, content: "这张海报里的时间对吗"),
    ]
    let images = [
        AIImageAttachment(data: Data([0x01]), mediaType: "image/jpeg"),
        AIImageAttachment(data: Data([0x02]), mediaType: "image/png"),
    ]
    let request = try #require(AIVisionRequest(messages: messages, images: images, model: "claude-sonnet-4-6", apiKey: "k"))

    // 之前只留最后一条 user，前面的条件和 assistant 回复全丢。
    #expect(ClaudeClient.visionBody(for: request)["system"] as? String == "你是 1Day 助手")

    let history = ClaudeClient.visionMessages(for: request)
    #expect(history.count == 3)
    #expect(history[0]["role"] as? String == "user")
    #expect(history[0]["content"] as? String == "明天下午开会")
    #expect(history[1]["role"] as? String == "assistant")
    #expect(history[1]["content"] as? String == "已记为草稿")

    let currentBlocks = try #require(history[2]["content"] as? [[String: Any]])
    #expect(currentBlocks.count == 3)
    #expect(currentBlocks[0]["type"] as? String == "image")
    #expect(currentBlocks[0]["source"] != nil)
    #expect(currentBlocks[1]["type"] as? String == "image")
    #expect(currentBlocks.last?["text"] as? String == "这张海报里的时间对吗")
}

@Test func claudeVisionSystemPromptIsNotDuplicatedIntoMessages() throws {
    let request = try #require(AIVisionRequest(
        messages: [
            AIClientMessage(role: .system, content: "规则"),
            AIClientMessage(role: .user, content: "看这张图"),
        ],
        images: oneImage,
        model: "m",
        apiKey: "k"
    ))

    let history = ClaudeClient.visionMessages(for: request)
    #expect(history.count == 1)
    #expect(history[0]["role"] as? String == "user")
    let blocks = try #require(history[0]["content"] as? [[String: Any]])
    #expect(blocks.last?["text"] as? String == "看这张图")
}

// MARK: - F-15 压缩必须真的满足大小上限

/// 随机噪点图：JPEG 压不动，能逼出「降尺寸 + 再降质量」这条真实路径。
private func noisyJPEG(side: CGFloat) -> Data {
    let size = CGSize(width: side, height: side)
    // scale = 1，否则测试图会按屏幕倍数画成 3 倍像素，测出来的字节数没有意义。
    let format = UIGraphicsImageRendererFormat()
    format.scale = 1
    let renderer = UIGraphicsImageRenderer(size: size, format: format)
    let image = renderer.image { context in
        context.cgContext.setFillColor(UIColor.white.cgColor)
        context.cgContext.fill(CGRect(origin: .zero, size: size))
        for _ in 0..<12_000 {
            let color = UIColor(
                red: .random(in: 0...1),
                green: .random(in: 0...1),
                blue: .random(in: 0...1),
                alpha: 1
            )
            context.cgContext.setFillColor(color.cgColor)
            context.cgContext.fill(CGRect(
                x: CGFloat(Int.random(in: 0..<Int(side))),
                y: CGFloat(Int.random(in: 0..<Int(side))),
                width: 7,
                height: 7
            ))
        }
    }
    return image.jpegData(compressionQuality: 0.98)!
}

@Test func compressedImageRespectsTheByteLimit() throws {
    let original = noisyJPEG(side: 2_000)
    let limit = 200_000
    // 前提：这张图本身确实超限，否则「压下去了」没有意义。
    #expect(original.count > limit)

    let compressed = try ImageService.compressedData(original, maxBytes: limit)

    #expect(compressed.count <= limit)
    #expect(compressed.count < original.count)
}

@Test func impossibleByteLimitFailsInsteadOfReturningOversizedData() throws {
    let original = noisyJPEG(side: 900)

    #expect(throws: (any Error).self) {
        _ = try ImageService.compressedData(original, maxBytes: 200)
    }
    // 旧实现在缩到 1600 之后只压一次就不再检查，超限数据会被当成成功返回。
    #expect(ImageService.compress(original, maxBytes: 200) == nil)
}

@Test func unreadableImageDataIsRejected() {
    #expect(throws: (any Error).self) {
        _ = try ImageService.compressedData(Data([0x00, 0x01, 0x02, 0x03]))
    }
    #expect(ImageService.compress(Data("这不是一张图片".utf8)) == nil)
}

@Test func smallImageStillFitsTheDefaultBudget() throws {
    let tiny = noisyJPEG(side: 48)
    let compressed = try ImageService.compressedData(tiny, maxBytes: ImageService.defaultMaxBytes)
    #expect(compressed.count <= ImageService.defaultMaxBytes)
}

// MARK: - F-14 图片请求的输入契约

private let oneImage = [AIImageAttachment(data: Data([0xFF, 0xD8]), mediaType: "image/jpeg")]

@Test func visionRequestRejectsEmptyImageListInsteadOfTrapping() {
    let messages = [AIClientMessage(role: .user, content: "看看这个")]

    // 旧实现暴露 `images[0]`，空数组一到就是运行时 trap。
    #expect(AIVisionRequest(messages: messages, images: [], model: "m", apiKey: "k") == nil)
    #expect(AIVisionRequest(messages: messages, images: oneImage, model: "m", apiKey: "k")?.images.count == 1)
}

@Test func visionRequestCapsImagesAtTheProviderLimit() {
    let messages = [AIClientMessage(role: .user, content: "看看这些")]
    let many = Array(repeating: oneImage[0], count: 9)

    let request = AIVisionRequest(messages: messages, images: many, model: "m", apiKey: "k")
    #expect(request?.images.count == AIVisionRequest.maximumImageCount)
}

// MARK: - F-13 通知失败必须让用户看见

private struct StubAddFailure: Error, LocalizedError {
    var errorDescription: String? { "系统拒绝了这条提醒" }
}

@Test func permissionStateMapsEverySystemStatus() {
    #expect(ReminderPermissionState(.authorized) == .granted)
    #expect(ReminderPermissionState(.denied) == .denied)
    #expect(ReminderPermissionState(.provisional) == .provisional)
    #expect(ReminderPermissionState(.ephemeral) == .provisional)
    #expect(ReminderPermissionState(.notDetermined) == .notDetermined)

    #expect(ReminderPermissionState.denied.needsUserAction)
    #expect(ReminderPermissionState.notDetermined.needsUserAction)
    #expect(!ReminderPermissionState.granted.needsUserAction)
    #expect(!ReminderPermissionState.provisional.needsUserAction)
}

@Test func everyNotificationFailureMessageIsActionable() {
    for state in [ReminderPermissionState.granted, .provisional, .denied, .notDetermined] {
        #expect(!state.title.isEmpty)
        #expect(!state.guidance.isEmpty)
    }
    #expect(ReminderDeliveryProblem.permissionDenied.message.contains("系统设置"))
    #expect(ReminderDeliveryProblem.schedulingFailed("容量不足").message.contains("容量不足"))
}

@Test func deniedPermissionIsReportedNotJustLogged() async throws {
    let recorder = ProblemRecorder()
    let delivery = RecordingNotificationDelivery(authorizationGranted: false, status: .denied)
    let scheduler = NotificationScheduler(delivery: delivery) { problem in
        await recorder.record(problem)
    }

    await scheduler.schedule(
        ReminderRequest(itemID: UUID(), title: "任务", body: "b", triggerDate: .now.addingTimeInterval(3_600))
    )

    #expect(await recorder.problems() == [.permissionDenied])
}

@Test func undecidedPermissionDoesNotTriggerAFailureBanner() async throws {
    let recorder = ProblemRecorder()
    let delivery = RecordingNotificationDelivery(authorizationGranted: false, status: .notDetermined)
    let scheduler = NotificationScheduler(delivery: delivery) { problem in
        await recorder.record(problem)
    }

    await scheduler.schedule(
        ReminderRequest(itemID: UUID(), title: "任务", body: "b", triggerDate: .now.addingTimeInterval(3_600))
    )

    // 还没做过决定不等于失败，弹「提醒不会送达」是误报。
    #expect(await recorder.problems().isEmpty)
}

@Test func systemRejectingTheRequestIsReportedWithDetail() async throws {
    let recorder = ProblemRecorder()
    let delivery = RecordingNotificationDelivery(addError: StubAddFailure())
    let scheduler = NotificationScheduler(delivery: delivery) { problem in
        await recorder.record(problem)
    }

    await scheduler.schedule(
        ReminderRequest(itemID: UUID(), title: "任务", body: "b", triggerDate: .now.addingTimeInterval(3_600))
    )

    let problems = await recorder.problems()
    #expect(problems.count == 1)
    if case .schedulingFailed(let detail)? = problems.first {
        #expect(detail.contains("系统拒绝了这条提醒"))
    } else {
        #expect(false, "应该报调度失败，而不是静默")
    }
}

// MARK: - F-11 通知调度按任务 id 串行化

/// 线程安全的记录型出口：用 actor 存事件序列，避免并发 append 丢写。
private actor RecordingNotificationDelivery: NotificationDelivering {
    private let authorizationGranted: Bool
    private let status: UNAuthorizationStatus
    private let addError: Error?
    private var eventLog: [String] = []
    private var addedRequests: [ReminderRequest] = []

    init(
        authorizationGranted: Bool = true,
        status: UNAuthorizationStatus = .authorized,
        addError: Error? = nil
    ) {
        self.authorizationGranted = authorizationGranted
        self.status = status
        self.addError = addError
    }

    func waitForAuthorization() async -> Bool {
        // 留出真实的挂起点，让竞态有机会出现。
        try? await Task.sleep(nanoseconds: 20_000_000)
        eventLog.append("auth")
        return authorizationGranted
    }

    func authorizationStatus() async -> UNAuthorizationStatus { status }

    func removePending(identifier: String) async {
        try? await Task.sleep(nanoseconds: 5_000_000)
        eventLog.append("remove:\(identifier)")
    }

    func add(_ request: ReminderRequest) async throws {
        try? await Task.sleep(nanoseconds: 5_000_000)
        if let addError { throw addError }
        eventLog.append("add:\(request.title)")
        addedRequests.append(request)
    }

    func snapshot() -> (events: [String], added: [ReminderRequest], lastEvent: String?) {
        (eventLog, addedRequests, eventLog.last)
    }
}

private actor ProblemRecorder {
    private var recorded: [ReminderDeliveryProblem] = []

    func record(_ problem: ReminderDeliveryProblem) {
        recorded.append(problem)
    }

    func problems() -> [ReminderDeliveryProblem] { recorded }
}

/// 可控门控版：第一次授权等待会被卡在门上，等测试安排好第二次提交后再放行，
/// 这样「哪一次被取代」就是确定的，而不是看调度器心情。
private actor GatedNotificationDelivery: NotificationDelivering {
    private var eventLog: [String] = []
    private var addedRequests: [ReminderRequest] = []
    private var gateOpen = false
    private var authAttempts = 0

    func waitForAuthorization() async -> Bool {
        authAttempts += 1
        eventLog.append("auth:enter")
        while !gateOpen {
            try? await Task.sleep(nanoseconds: 2_000_000)
        }
        eventLog.append("auth:exit")
        return true
    }

    func removePending(identifier: String) async {
        eventLog.append("remove:\(identifier)")
    }

    func authorizationStatus() async -> UNAuthorizationStatus { .authorized }

    func add(_ request: ReminderRequest) async throws {
        eventLog.append("add:\(request.title)")
        addedRequests.append(request)
    }

    func waitUntilPendingWorkStarts() async {
        while authAttempts == 0 {
            try? await Task.sleep(nanoseconds: 2_000_000)
        }
    }

    func openGate() {
        gateOpen = true
    }

    func snapshot() -> (added: [ReminderRequest], lastEvent: String?) {
        (addedRequests, eventLog.last)
    }
}

@Test func supersededScheduleCannotOvertakeTheNewestRequest() async throws {
    let delivery = GatedNotificationDelivery()
    let scheduler = NotificationScheduler(delivery: delivery)
    let id = UUID()
    let older = ReminderRequest(itemID: id, title: "旧日期", body: "b", triggerDate: Date().addingTimeInterval(3_600))
    let newer = ReminderRequest(itemID: id, title: "新日期", body: "b", triggerDate: Date().addingTimeInterval(7_200))

    async let first = scheduler.schedule(older)
    await delivery.waitUntilPendingWorkStarts()
    async let second = scheduler.schedule(newer)
    await delivery.openGate()
    await (first, second)

    let snap = await delivery.snapshot()
    #expect(snap.added.map(\.title) == ["新日期"])
    #expect(snap.lastEvent == "add:新日期")
}

@Test func rapidReschedulesAlwaysEndWithAnAdd() async throws {
    // 不加门控的真实交错：至少最后一步不能是 remove，
    // 否则用户看到的就是「提醒凭空消失」。
    let delivery = RecordingNotificationDelivery()
    let scheduler = NotificationScheduler(delivery: delivery)
    let id = UUID()

    await withTaskGroup(of: Void.self) { group in
        for minute in 1...6 {
            group.addTask {
                await scheduler.schedule(ReminderRequest(
                    itemID: id,
                    title: "第\(minute)次",
                    body: "b",
                    triggerDate: Date().addingTimeInterval(TimeInterval(minute * 600))
                ))
            }
        }
    }

    let snap = await delivery.snapshot()
    #expect(!snap.added.isEmpty)
    #expect(snap.lastEvent?.hasPrefix("add:") == true)
}

@Test func cancelAfterScheduleIsTheLastThingThatTouchesTheCenter() async throws {
    let delivery = RecordingNotificationDelivery()
    let scheduler = NotificationScheduler(delivery: delivery)
    let id = UUID()
    let request = ReminderRequest(itemID: id, title: "即将撤销的任务", body: "b", triggerDate: Date().addingTimeInterval(3_600))

    async let scheduling = scheduler.schedule(request)
    try await Task.sleep(nanoseconds: 5_000_000)
    await scheduler.cancel(itemID: id)
    await scheduling

    // 撤销排在调度之后，就必须是最后一个动作，否则通知中心会留下孤儿提醒。
    let snap = await delivery.snapshot()
    #expect(snap.lastEvent == "remove:\(ReminderRequest.identifier(for: id))")
}

@Test func differentTasksDoNotSupersedeEachOther() async throws {
    let delivery = RecordingNotificationDelivery()
    let scheduler = NotificationScheduler(delivery: delivery)

    async let a = scheduler.schedule(ReminderRequest(itemID: UUID(), title: "甲", body: "b", triggerDate: .now.addingTimeInterval(3_600)))
    async let b = scheduler.schedule(ReminderRequest(itemID: UUID(), title: "乙", body: "b", triggerDate: .now.addingTimeInterval(3_600)))
    await (a, b)

    let snap = await delivery.snapshot()
    #expect(snap.added.count == 2)
    #expect(Set(snap.added.map(\.title)) == ["甲", "乙"])
}

@Test func deniedAuthorizationSkipsScheduling() async throws {
    let delivery = RecordingNotificationDelivery(authorizationGranted: false)
    let scheduler = NotificationScheduler(delivery: delivery)

    await scheduler.schedule(
        ReminderRequest(itemID: UUID(), title: "任务", body: "b", triggerDate: .now.addingTimeInterval(3_600))
    )

    let snap = await delivery.snapshot()
    #expect(snap.added.isEmpty)
    #expect(snap.events == ["auth"])
}

@Test func reminderSnapshotOnlyExistsForFuturePendingTasks() throws {
    let calendar = Calendar.current
    let future = calendar.date(byAdding: .day, value: 2, to: .now)!

    let scheduled = PlanItem(title: "交报告", dueDate: future)
    let snapshot = NotificationService.reminderRequest(for: scheduled)
    #expect(snapshot?.itemID == scheduled.id)
    #expect(snapshot?.title == "交报告")
    #expect(snapshot?.triggerDate ?? .distantPast > Date())

    // 已完成、没有日期、日期已过：都不该留下提醒。
    let completed = PlanItem(title: "已完成", dueDate: future)
    completed.status = .completed
    #expect(NotificationService.reminderRequest(for: completed) == nil)
    #expect(NotificationService.reminderRequest(for: PlanItem(title: "未安排", dueDate: nil)) == nil)
    #expect(NotificationService.reminderRequest(for: PlanItem(title: "过期", dueDate: .now.addingTimeInterval(-3_600))) == nil)
}

// MARK: - F-10 计划上下文按意图最小化外发

@Test func casualMessagesNeverNeedPlanContext() {
    for text in ["你好", "谢谢", "今天天气怎么样", "讲个笑话", "你是谁", ""] {
        #expect(AIContextPolicy.needsPlanContext(for: text) == false, "不该外发任务标题：\(text)")
    }
}

@Test func planRelatedMessagesNeedPlanContext() {
    for text in ["我今天还有什么任务", "帮我看看这周的安排", "明天提交周报", "本周复盘"] {
        #expect(AIContextPolicy.needsPlanContext(for: text), "该带上下文却没带：\(text)")
    }
}

@Test @MainActor func contextIsOnlySentWhenTheMessageActuallyNeedsIt() async throws {
    let container = try makeInMemoryContainer()
    let context = ModelContext(container)
    let settings = try configuredSettings(in: context)
    context.insert(PlanItem(title: "内部代号-朱雀", dueDate: Calendar.current.startOfDay(for: .now)))
    try context.save()
    let planItems = try context.fetch(FetchDescriptor<PlanItem>())

    let service = ScriptedAIService(results: [.success("你好"), .success("你今天有 1 个任务")])
    let viewModel = AIChatViewModel(serviceFactory: { _ in service })

    // 普通问候：请求体里一个任务标题都不该出现。
    viewModel.inputText = "你好"
    viewModel.send(
        imageDataList: [],
        messages: [],
        settings: settings,
        planItems: planItems,
        selectedDate: .now,
        modelContext: context
    )
    try await Task.sleep(nanoseconds: 150_000_000)
    #expect(service.capturedContexts.count == 1)
    #expect(service.capturedContexts[0] == nil)

    // 计划类问题：这时才注入摘要。
    viewModel.inputText = "我今天还有什么任务"
    viewModel.send(
        imageDataList: [],
        messages: [],
        settings: settings,
        planItems: planItems,
        selectedDate: .now,
        modelContext: context
    )
    try await Task.sleep(nanoseconds: 150_000_000)
    #expect(service.capturedContexts.count == 2)
    #expect(service.capturedContexts[1]?.todayTaskTitles.contains("内部代号-朱雀") == true)
}

@Test func promptNeverCarriesNoteContent() throws {
    // 上下文结构本身就不该有笔记字段（spec §三：笔记正文默认不发）。
    let messages = AIPromptBuilder.makeMessages(
        text: "整理一下",
        history: [],
        context: AIDataContext(todayTaskTitles: ["交房租"], upcomingTaskTitles: []),
        language: "zh-Hans"
    )
    let system = messages.first?.content ?? ""
    #expect(system.contains("交房租"))
    #expect(!system.contains("最近笔记"))
}

// MARK: - F-09 结构化意图解码

@Test func decodesStructuredCreateTaskFromFencedJSON() throws {
    let reply = """
    好，我把它整理成一条任务。

    ```json
    {"intent":"create_task","data":{"title":"交房租","notes":"转账到房东招商银行",\
    "dueDate":"2026-07-01T00:00:00Z","priority":"high","reminderTime":"2026-06-30T09:30:00Z"}}
    ```
    """
    let draft = AIIntentDecoder.decodeCreateTask(from: reply)

    #expect(draft?.title == "交房租")
    #expect(draft?.notes == "转账到房东招商银行")
    #expect(draft?.priority == .high)
    #expect(draft?.dueDate != nil)
    #expect(draft?.reminderTime != nil)
}

@Test func decodesBareJSONEmbeddedInProseAndToleratesMissingOptionals() throws {
    let reply = "建议这样安排 {\"intent\":\"create_task\",\"data\":{\"title\":\"买机票\"}} 之后再确认"
    let draft = AIIntentDecoder.decodeCreateTask(from: reply)

    #expect(draft?.title == "买机票")
    #expect(draft?.notes == nil)
    #expect(draft?.dueDate == nil)
    // 没给 priority 不等于猜一个：留 nil，由确认页按默认值展示。
    #expect(draft?.priority == nil)
}

@Test func rejectsUntrustworthyStructuredPayloadsInsteadOfGuessing() throws {
    // 未知 priority 不能静默降级成 none。
    #expect(AIIntentDecoder.decodeCreateTask(
        from: "{\"intent\":\"create_task\",\"data\":{\"title\":\"交租\",\"priority\":\"urgent\"}}"
    ) == nil)
    // 标题为空。
    #expect(AIIntentDecoder.decodeCreateTask(
        from: "{\"intent\":\"create_task\",\"data\":{\"title\":\"   \"}}"
    ) == nil)
    // V1.2 才有的 create_event：当前 schema 不认，回退纯文本。
    #expect(AIIntentDecoder.decodeCreateTask(
        from: "{\"intent\":\"create_event\",\"data\":{\"title\":\"周会\"}}"
    ) == nil)
    // 日期格式不对（非 ISO 8601）→ 整体解码失败，不写入半截草稿。
    #expect(AIIntentDecoder.decodeCreateTask(
        from: "{\"intent\":\"create_task\",\"data\":{\"title\":\"交租\",\"dueDate\":\"7月1号\"}}"
    ) == nil)
    // 纯文本没有 JSON。
    #expect(AIIntentDecoder.decodeCreateTask(from: "这周你完成了 3 个任务。") == nil)
    // 半截 JSON。
    #expect(AIIntentDecoder.decodeCreateTask(from: "{\"intent\":\"create_task\",\"data\":{\"title\":") == nil)
}

@Test @MainActor func structuredReplyCreatesDraftThatLocalRulesMissed() async throws {
    let container = try makeInMemoryContainer()
    let context = ModelContext(container)
    let settings = try configuredSettings(in: context)
    let reply = """
    我按图片内容整理如下：
    ```json
    {"intent":"create_task","data":{"title":"带护照","dueDate":"2026-07-10T00:00:00Z","priority":"high"}}
    ```
    """
    let service = ScriptedAIService(results: [.success(reply)])
    let viewModel = AIChatViewModel(serviceFactory: { _ in service })
    // 这句话本地规则识别不出创建意图，草稿只能来自结构化回复。
    viewModel.inputText = "看看这两张照片"

    viewModel.send(
        imageDataList: [Data("fake-image".utf8)],
        messages: [],
        settings: settings,
        planItems: [],
        selectedDate: .now,
        modelContext: context
    )
    try await Task.sleep(nanoseconds: 200_000_000)

    #expect(viewModel.pendingTask?.title == "带护照")
    #expect(viewModel.pendingTask?.priority == .high)
    #expect(viewModel.pendingTask?.dueDate != nil)
    #expect(viewModel.isShowingConfirmation)

    let assistant = try context.fetch(FetchDescriptor<AIChatMessage>()).filter { $0.role == "assistant" }
    #expect(assistant.count == 1)
    // 已经拿到草稿，就不该再出现「整理不出来」的提示。
    #expect(assistant.first?.content.contains("没能从图片里整理出") == false)
}

@Test @MainActor func imageRequestWithoutDraftExplainsItself() async throws {
    let container = try makeInMemoryContainer()
    let context = ModelContext(container)
    let settings = try configuredSettings(in: context)
    let service = ScriptedAIService(results: [.success("这是一张风景照，没有可整理的事项。")])
    let viewModel = AIChatViewModel(serviceFactory: { _ in service })
    viewModel.inputText = "看看这两张照片"

    viewModel.send(
        imageDataList: [Data("fake-image".utf8)],
        messages: [],
        settings: settings,
        planItems: [],
        selectedDate: .now,
        modelContext: context
    )
    try await Task.sleep(nanoseconds: 200_000_000)

    // 图片请求不能静默返回 nil：要么给可确认结果，要么明确说明没有。
    #expect(viewModel.pendingTask == nil)
    let assistant = try context.fetch(FetchDescriptor<AIChatMessage>()).filter { $0.role == "assistant" }
    #expect(assistant.first?.content.contains("没能从图片里整理出") == true)
}

@Test @MainActor func structuredDraftPersistsReminderTime() throws {
    let container = try makeInMemoryContainer()
    let context = ModelContext(container)
    let reminder = Calendar.current.date(bySettingHour: 20, minute: 15, second: 0, of: Date())!

    let draft = AIParsedTask(
        title: "带护照",
        notes: nil,
        dueDate: Calendar.current.startOfDay(for: Date()),
        dueDateText: nil,
        priority: .high,
        reminderTime: reminder
    )
    let item = PlanAIIntentRecorder.createTask(draft, in: context)
    try context.save()

    // AI 给的提醒时间必须真的落到任务上，否则 schema 里的字段是摆设。
    #expect(item.reminderTime != nil)
    #expect(Calendar.current.isDate(item.reminderTime!, equalTo: reminder, toGranularity: .minute))
    #expect(item.priority == .high)
}

// MARK: - F-08 重试成功后要重新进入任务确认

private final class ScriptedAIService: AIService, @unchecked Sendable {
    private let results: [Result<String, Error>]
    private(set) var callCount = 0
    private(set) var capturedContexts: [AIDataContext?] = []

    init(results: [Result<String, Error>]) {
        self.results = results
    }

    func sendMessage(_ text: String, history: [AIChatHistoryItem], context: AIDataContext?) async throws -> String {
        let index = min(callCount, results.count - 1)
        callCount += 1
        capturedContexts.append(context)
        switch results[index] {
        case .success(let reply): return reply
        case .failure(let error): throw error
        }
    }

    func sendMessageWithImage(_ text: String, imageData: Data, history: [AIChatHistoryItem], context: AIDataContext?) async throws -> String {
        try await sendMessage(text, history: history, context: context)
    }

    func sendMessageWithImages(_ text: String, imageDataList: [Data], history: [AIChatHistoryItem], context: AIDataContext?) async throws -> String {
        try await sendMessage(text, history: history, context: context)
    }
}

@Test @MainActor func retryAfterFailedRequestStillOffersTaskConfirmation() async throws {
    let container = try makeInMemoryContainer()
    let context = ModelContext(container)
    let settings = try configuredSettings(in: context)
    let service = ScriptedAIService(results: [
        .failure(AIClientError.providerError("网络中断")),
        .success("已整理为一条任务"),
    ])
    let viewModel = AIChatViewModel(serviceFactory: { _ in service })
    viewModel.inputText = "明天提交周报"

    viewModel.send(
        imageDataList: [],
        messages: [],
        settings: settings,
        planItems: [],
        selectedDate: .now,
        modelContext: context
    )
    try await Task.sleep(nanoseconds: 200_000_000)

    // 第一次失败：留下重试入口，但没有草稿。
    #expect(viewModel.failedRequestText == "明天提交周报")
    #expect(viewModel.pendingTask == nil)

    viewModel.retryLastRequest(
        settings: settings,
        planItems: [],
        selectedDate: .now,
        modelContext: context
    )
    try await Task.sleep(nanoseconds: 200_000_000)

    // 重试成功必须和首次成功一致：解析出草稿并打开确认卡。
    #expect(service.callCount == 2)
    #expect(viewModel.pendingTask?.title == "提交周报")
    #expect(viewModel.isShowingConfirmation)
}

@Test @MainActor func plainChatRetryDoesNotOpenConfirmation() async throws {
    let container = try makeInMemoryContainer()
    let context = ModelContext(container)
    let settings = try configuredSettings(in: context)
    let service = ScriptedAIService(results: [
        .failure(AIClientError.providerError("请求超时")),
        .success("这周你完成了 3 个任务。"),
    ])
    let viewModel = AIChatViewModel(serviceFactory: { _ in service })
    viewModel.inputText = "我这周做得怎么样"

    viewModel.send(
        imageDataList: [],
        messages: [],
        settings: settings,
        planItems: [],
        selectedDate: .now,
        modelContext: context
    )
    try await Task.sleep(nanoseconds: 120_000_000)

    viewModel.retryLastRequest(
        settings: settings,
        planItems: [],
        selectedDate: .now,
        modelContext: context
    )
    try await Task.sleep(nanoseconds: 120_000_000)

    // 非创建意图：只留一条回复，不能凭空弹确认卡。
    #expect(viewModel.pendingTask == nil)
    #expect(viewModel.isShowingConfirmation == false)
    let assistant = try context.fetch(FetchDescriptor<AIChatMessage>()).filter { $0.role == "assistant" }
    #expect(assistant.count == 1)
}

// MARK: - F-07 「停止」必须真的取消网络请求

private final class SlowAIService: AIService, @unchecked Sendable {
    private(set) var sawCancellation = false
    private(set) var callCount = 0

    func sendMessage(_ text: String, history: [AIChatHistoryItem], context: AIDataContext?) async throws -> String {
        callCount += 1
        do {
            try await Task.sleep(nanoseconds: 10_000_000_000)
            return "晚到的回复"
        } catch {
            sawCancellation = true
            throw CancellationError()
        }
    }

    func sendMessageWithImage(_ text: String, imageData: Data, history: [AIChatHistoryItem], context: AIDataContext?) async throws -> String {
        try await sendMessage(text, history: history, context: context)
    }

    func sendMessageWithImages(_ text: String, imageDataList: [Data], history: [AIChatHistoryItem], context: AIDataContext?) async throws -> String {
        try await sendMessage(text, history: history, context: context)
    }
}

@MainActor
private func configuredSettings(in context: ModelContext) throws -> UserSettings {
    let settings = try SettingsBootstrap.ensureSettings(in: context)
    settings.isAIConfigured = true
    try context.save()
    return settings
}

@Test @MainActor func stoppingARequestCancelsTaskAndSuppressesLateResult() async throws {
    let container = try makeInMemoryContainer()
    let context = ModelContext(container)
    let settings = try configuredSettings(in: context)

    let service = SlowAIService()
    let viewModel = AIChatViewModel(serviceFactory: { _ in service })
    viewModel.inputText = "明天提交周报"

    viewModel.send(
        imageDataList: [],
        messages: [],
        settings: settings,
        planItems: [],
        selectedDate: .now,
        modelContext: context
    )
    #expect(viewModel.isLoading)

    viewModel.stopLoading()
    #expect(viewModel.isLoading == false)

    // 给被取消的任务一点时间走完收尾：晚到的结果不能写进会话。
    try await Task.sleep(nanoseconds: 300_000_000)

    #expect(service.callCount == 1)
    #expect(service.sawCancellation)

    let messages = try context.fetch(FetchDescriptor<AIChatMessage>())
    #expect(messages.contains { $0.role == "user" })
    #expect(!messages.contains { $0.role == "assistant" })
    // 用户主动取消不算失败：不能留下「重试」入口（banner 是共享单例，
    // 并行测试下互相干扰，所以断言实例状态而不是全局状态）。
    #expect(viewModel.failedRequestText == nil)
    #expect(viewModel.failedRequestImages.isEmpty)
}

@Test @MainActor func cancelledRequestDoesNotOpenTaskConfirmation() async throws {
    let container = try makeInMemoryContainer()
    let context = ModelContext(container)
    let settings = try configuredSettings(in: context)
    let service = SlowAIService()
    let viewModel = AIChatViewModel(serviceFactory: { _ in service })

    // 「创建任务」意图 + 立即停止：不能因为取消而弹出确认卡。
    viewModel.inputText = "明天提交周报"
    viewModel.send(
        imageDataList: [],
        messages: [],
        settings: settings,
        planItems: [],
        selectedDate: .now,
        modelContext: context
    )
    viewModel.stopLoading()
    try await Task.sleep(nanoseconds: 300_000_000)

    #expect(viewModel.isShowingConfirmation == false)
    #expect(viewModel.pendingTask == nil)
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
