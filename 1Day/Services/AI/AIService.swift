import Foundation
import SwiftData
import SwiftUI

protocol AIService {
    func sendMessage(_ text: String, history: [AIChatHistoryItem], context: AIDataContext?) async throws -> String
    func sendMessageWithImage(_ text: String, imageData: Data, history: [AIChatHistoryItem], context: AIDataContext?) async throws -> String
    func sendMessageWithImages(_ text: String, imageDataList: [Data], history: [AIChatHistoryItem], context: AIDataContext?) async throws -> String
    func parseStructuredIntent(from text: String) async throws -> AIChatIntentResult?
    func parseStructuredIntentWithImage(_ text: String, imageData: Data) async throws -> AIChatIntentResult?
    func parseStructuredIntentWithImages(_ text: String, imageDataList: [Data]) async throws -> AIChatIntentResult?
}

@Model
final class AIChatMessage: Identifiable {
    @Attribute(.unique) var id: UUID
    var role: String
    var content: String
    var providerRawValue: String
    var createdAt: Date
    var toolName: String?
    var toolPayloadJSON: String?

    init(
        id: UUID = UUID(),
        role: String,
        content: String,
        provider: AIProvider = .claude,
        createdAt: Date = Date(),
        toolName: String? = nil,
        toolPayloadJSON: String? = nil
    ) {
        self.id = id
        self.role = role
        self.content = content
        self.providerRawValue = provider.rawValue
        self.createdAt = createdAt
        self.toolName = toolName
        self.toolPayloadJSON = toolPayloadJSON
    }
}

struct AIChatHistoryItem: Codable, Equatable {
    let role: String
    let content: String
}

struct AIDataContext: Codable, Equatable {
    var todayTaskTitles: [String] = []
    var upcomingTaskTitles: [String] = []
    var recentNoteTitles: [String] = []
}

/// Builds the compact, date-aware context sent to the AI service.
/// Keeping this outside the view prevents the chat UI from owning task-query rules.
enum PlanAIDataContextBuilder {
    static func make(items: [PlanItem], selectedDate: Date) -> AIDataContext {
        let calendar = Calendar.current
        let dayStart = calendar.startOfDay(for: selectedDate)
        let nextWeek = calendar.date(byAdding: .day, value: 7, to: dayStart) ?? dayStart

        let today = items
            .filter { !$0.isCompleted && $0.isDue(on: selectedDate) }
            .prefix(10)
            .map(\.title)
        let upcoming = items
            .filter { !$0.isCompleted }
            .filter { item in
                guard let dueDate = item.dueDate else { return false }
                return dueDate > dayStart && dueDate <= nextWeek
            }
            .sorted { ($0.dueDate ?? .distantFuture) < ($1.dueDate ?? .distantFuture) }
            .prefix(10)
            .map(\.title)

        return AIDataContext(
            todayTaskTitles: Array(today),
            upcomingTaskTitles: Array(upcoming)
        )
    }
}

/// Records AI-created tasks and keeps the chat-side persistence contract in one place.
enum PlanAIIntentRecorder {
    static func createTask(_ task: AIParsedTask, in context: ModelContext) -> PlanItem {
        let draft = PlanItemDraft(
            title: task.title,
            notes: task.notes ?? "",
            dueDate: task.dueDate,
            reminderTime: nil,
            priority: task.priority ?? .none
        )
        return PlanItemService.createTask(draft, in: context)
            ?? PlanItemService.createTask(title: task.title, notes: task.notes ?? "", dueDate: task.dueDate, priority: task.priority ?? .none, in: context)
    }
}

enum PlanTaskValidation {
    static func error(for task: AIParsedTask) -> String? {
        guard !task.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return "任务标题不能为空。"
        }
        return nil
    }
}

enum PlanAIReplyBuilder {
    static let unconfigured = "配置 AI 服务商后，可以用自然语言聊天整理任务和计划建议。\n\n直接输入任务指令也可以：「明天提交周报，重要」"
    static let draftReady = "已识别任务草稿，请确认后创建。"

    static func createdTask(_ title: String) -> String { "已创建任务：\(title)" }
    static func requestFailed(_ message: String) -> String {
        "请求失败：\(message)\n\n请检查 API Key 和网络连接，或在设置中重新配置。"
    }
}

enum AIChatIntentResult: Equatable {
    case createTask(AIParsedTask)
}

struct AIParsedTask: Codable, Equatable {
    var title: String
    var notes: String?
    var dueDate: Date?
    var dueDateText: String?
    var priority: Priority?
}

struct ConfiguredAIService: AIService {
    let settings: UserSettings
    let configurationService: AIConfigurationService
    let clientFactory: AIClientFactory
    var language: String = "zh-Hans"

    var provider: AIProvider {
        AIProvider(rawValue: settings.selectedAIProviderRawValue) ?? .claude
    }

    init(
        settings: UserSettings,
        configurationService: AIConfigurationService = LocalAIConfigurationService(),
        clientFactory: AIClientFactory = AIClientFactory(),
        language: String = "zh-Hans"
    ) {
        self.settings = settings
        self.configurationService = configurationService
        self.clientFactory = clientFactory
        self.language = language
    }

    func sendMessage(_ text: String, history: [AIChatHistoryItem], context: AIDataContext?) async throws -> String {
        guard let apiKey = try configurationService.readAPIKey(provider: provider),
              !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw AIClientError.missingAPIKey
        }

        let client = try clientFactory.client(for: provider)
        let request = AIClientRequest(
            messages: AIPromptBuilder.makeMessages(
                text: text,
                history: history,
                context: context,
                language: language
            ),
            model: settings.selectedAIModel,
            apiKey: apiKey
        )

        do {
            AppLogger.ai("发送消息 → \(provider.rawValue) 模型: \(settings.selectedAIModel)")
            return try await client.send(request).text
        } catch let error as AIClientError {
            AppLogger.aiError("AI 请求失败: \(error.localizedDescription)")
            throw error
        } catch {
            AppLogger.aiError("AI 请求异常: \(error.localizedDescription)")
            throw AIClientError.providerError("网络请求失败，请检查网络连接")
        }
    }

    func sendMessageWithImage(_ text: String, imageData: Data, history: [AIChatHistoryItem], context: AIDataContext?) async throws -> String {
        try await sendMessageWithImages(text, imageDataList: [imageData], history: history, context: context)
    }

    func sendMessageWithImages(_ text: String, imageDataList: [Data], history: [AIChatHistoryItem], context: AIDataContext?) async throws -> String {
        guard provider.supportsVision(model: settings.selectedAIModel) else {
            throw AIClientError.providerError("当前模型不支持图片输入，请切换到支持视觉输入的模型。")
        }
        guard let apiKey = try configurationService.readAPIKey(provider: provider),
              !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw AIClientError.missingAPIKey
        }
        let images = imageDataList.prefix(6).compactMap { ImageService.compress($0) }.map {
            AIImageAttachment(data: $0, mediaType: "image/jpeg")
        }
        guard !images.isEmpty, let visionClient = try clientFactory.visionClient(for: provider) else {
            throw AIClientError.providerError("当前服务商暂不支持图片输入，请切换到支持视觉输入的模型。")
        }

        let prompt = text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? "请逐张描述这些图片中与计划、任务、日程或笔记有关的信息。不要偷懒：多张图片或多个事项要逐项覆盖，不能只处理第一张或最明显的一项。不要自动创建数据，只返回可供用户确认的文字建议。"
            : text
        let request = AIVisionRequest(
            messages: AIPromptBuilder.makeMessages(
                text: prompt,
                history: history,
                context: context,
                language: language
            ),
            images: images,
            model: settings.selectedAIModel,
            apiKey: apiKey,
            timeoutInterval: 45
        )

        do {
            AppLogger.ai("发送图片消息 → \(provider.rawValue) 模型: \(settings.selectedAIModel)")
            return try await visionClient.sendWithImage(request).text
        } catch let error as AIClientError {
            AppLogger.aiError("AI 图片请求失败: \(error.localizedDescription)")
            throw error
        } catch {
            AppLogger.aiError("AI 图片请求异常: \(error.localizedDescription)")
            throw AIClientError.providerError("图片识别失败，请检查网络连接")
        }
    }

    func parseStructuredIntent(from text: String) async throws -> AIChatIntentResult? {
        LocalAIIntentParser.parseTask(from: text).map { .createTask($0) }
    }

    func parseStructuredIntentWithImage(_ text: String, imageData: Data) async throws -> AIChatIntentResult? {
        try await parseStructuredIntentWithImages(text, imageDataList: [imageData])
    }

    func parseStructuredIntentWithImages(_ text: String, imageDataList: [Data]) async throws -> AIChatIntentResult? {
        nil
    }
}

enum AIPromptBuilder {
    static func makeMessages(
        text: String,
        history: [AIChatHistoryItem],
        context: AIDataContext?,
        language: String
    ) -> [AIClientMessage] {
        var messages: [AIClientMessage] = [
            AIClientMessage(role: .system, content: systemPrompt(language: language, context: context))
        ]

        messages.append(contentsOf: history.suffix(8).compactMap { item in
            guard let role = AIRole(rawValue: item.role) else { return nil }
            return AIClientMessage(role: role, content: item.content)
        })

        messages.append(AIClientMessage(role: .user, content: text))
        return messages
    }

    private static func systemPrompt(language: String, context: AIDataContext?) -> String {
        var prompt = """
        你是 1Day 的 AI 计划助手。你可以帮助用户整理任务、日程想法和笔记草稿。
        当前阶段只输出自然语言建议，不直接写入数据库。
        如果用户想创建任务，请用简洁结构列出标题、日期、优先级和备注建议，并提醒需要用户确认。
        不要偷懒：必须覆盖用户输入中的所有任务、日期、人物、地点、约束和备注线索；不确定的信息要标注“待确认”，不能静默省略。
        如果用户给出多张图片或多个事项，逐项整理，不要只处理第一项或最明显的一项。
        不要提供金融、医疗或法律建议。
        请优先使用 \(language) 回复。
        """

        if let context {
            let sections: [(String, [String])] = [
                ("今日任务", context.todayTaskTitles),
                ("近期任务", context.upcomingTaskTitles),
                ("最近笔记", context.recentNoteTitles)
            ]
            let contextText = sections
                .filter { !$0.1.isEmpty }
                .map { title, items in "\(title)：\(items.prefix(6).joined(separator: "、"))" }
                .joined(separator: "\n")
            if !contextText.isEmpty {
                prompt += "\n\n可用上下文：\n\(contextText)"
            }
        }

        return prompt
    }
}

enum LocalAIIntentParser {
    static func parseTask(from text: String, referenceDate: Date = Date()) -> AIParsedTask? {
        let rawText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard rawText.count >= 2 else { return nil }
        guard hasTaskCreationIntent(in: rawText) else { return nil }

        let priority = parsePriority(from: rawText)
        let dateResult = parseDueDate(from: rawText, referenceDate: referenceDate)
        let title = cleanTitle(rawText, dateText: dateResult.text, priority: priority)

        guard !title.isEmpty else { return nil }

        return AIParsedTask(
            title: title,
            notes: rawText == title ? nil : rawText,
            dueDate: dateResult.date,
            dueDateText: dateResult.text,
            priority: priority
        )
    }

    // Returns true only when the text reads like a task-creation command, not a question or chat.
    static func hasTaskCreationIntent(in text: String) -> Bool {
        // Questions are never task creation
        let questionMarkers = ["?", "？", "什么", "怎么", "为什么", "如何", "哪", "是否", "吗", "呢", "吧"]
        if questionMarkers.contains(where: { text.contains($0) }) { return false }

        // Explicit creation verbs always qualify
        let creationVerbs = ["创建", "新建", "记下", "加入计划", "安排", "提醒", "记得", "别忘", "要做", "需要做", "帮我"]
        if creationVerbs.contains(where: { text.contains($0) }) { return true }

        // Date keyword + action verb = task intent
        let dateKeywords = ["今天", "今日", "明天", "明日", "后天", "周一", "周二", "周三", "周四", "周五", "周六", "周日", "周天", "星期"]
        let actionKeywords = [
            "做", "写", "发", "交", "开", "打", "约", "见", "买",
            "整理", "准备", "汇报", "更新", "提交", "推进", "跟进",
            "联系", "回复", "查", "完成", "处理", "解决", "讨论",
            "参加", "出席", "审查", "检查", "调研", "调查"
        ]
        let hasDate = dateKeywords.contains(where: { text.contains($0) })
        let hasAction = actionKeywords.contains(where: { text.contains($0) })
        return hasDate && hasAction
    }

    private static func parsePriority(from text: String) -> Priority {
        if text.contains("高优先级") || text.contains("重要") || text.contains("紧急") {
            return .high
        }
        if text.contains("中优先级") || text.contains("一般优先") {
            return .medium
        }
        if text.contains("低优先级") || text.contains("不急") {
            return .low
        }
        return .none
    }

    private static func parseDueDate(from text: String, referenceDate: Date) -> (date: Date?, text: String?) {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: referenceDate)

        if text.contains("后天") {
            return (calendar.date(byAdding: .day, value: 2, to: today), "后天")
        }
        if text.contains("明天") || text.contains("明日") {
            return (calendar.date(byAdding: .day, value: 1, to: today), "明天")
        }
        if text.contains("今天") || text.contains("今日") {
            return (today, "今天")
        }

        let weekdays: [(String, Int)] = [
            ("周一", 2), ("星期一", 2),
            ("周二", 3), ("星期二", 3),
            ("周三", 4), ("星期三", 4),
            ("周四", 5), ("星期四", 5),
            ("周五", 6), ("星期五", 6),
            ("周六", 7), ("星期六", 7),
            ("周日", 1), ("周天", 1), ("星期日", 1), ("星期天", 1)
        ]

        for (keyword, weekday) in weekdays where text.contains(keyword) {
            return (nextDate(matching: weekday, from: today), keyword)
        }

        return (nil, nil)
    }

    private static func nextDate(matching weekday: Int, from startOfDay: Date) -> Date? {
        let calendar = Calendar.current
        let currentWeekday = calendar.component(.weekday, from: startOfDay)
        var daysToAdd = weekday - currentWeekday
        if daysToAdd < 0 { daysToAdd += 7 }
        return calendar.date(byAdding: .day, value: daysToAdd, to: startOfDay)
    }

    private static func cleanTitle(_ text: String, dateText: String?, priority: Priority) -> String {
        var title = text
        let removablePhrases = [
            "提醒我", "帮我", "记得", "安排", "创建任务", "新建任务",
            "高优先级", "中优先级", "低优先级", "重要", "紧急", "不急"
        ]
        for phrase in removablePhrases {
            title = title.replacingOccurrences(of: phrase, with: "")
        }
        if let dateText {
            title = title.replacingOccurrences(of: dateText, with: "")
        }
        return title
            .trimmingCharacters(in: CharacterSet(charactersIn: " ，,。.！!？?：:；;"))
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

// MARK: - AI Chat View Model

/// Owns AIChatView's session state and orchestration: composing/sending a message,
/// the loading lifecycle, retrying a failed request, and confirming/undoing an
/// AI-parsed task draft. `AIChatView` stays a thin renderer — it reads its own
/// `@Query`/`@Environment` values (settings, messages, plan items, model context)
/// and forwards them into these methods as parameters rather than the view-model
/// caching them itself.
///
/// Image-picker staging (`selectedImageDataList`, `PhotosPicker` selection, source
/// dialog flags) intentionally stays in the View: it's UI-component state owned by
/// `PhotosPicker`/`UIImagePickerController`, not session data, and only becomes
/// session data once `send(imageDataList:...)` receives a snapshot of it.
@Observable
@MainActor
final class AIChatViewModel {
    var inputText = ""
    var pendingTask: AIParsedTask?
    var isShowingConfirmation = false
    var isLoading = false
    var isLoadingImages = false
    var loadingSeconds = 0
    var undoItem: PlanItem?
    var undoTaskTitle = ""
    var failedRequestText: String?
    var failedRequestImages: [Data] = []
    var failedRequestHistory: [AIChatHistoryItem] = []

    private var loadingTimer: Timer?
    private let configService: AIConfigurationService

    init(configService: AIConfigurationService = LocalAIConfigurationService()) {
        self.configService = configService
    }

    // MARK: - Sending

    func send(
        imageDataList: [Data],
        messages: [AIChatMessage],
        settings: UserSettings?,
        planItems: [PlanItem],
        selectedDate: Date,
        modelContext: ModelContext
    ) {
        let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty || !imageDataList.isEmpty else { return }

        let provider = settings?.selectedAIProvider ?? .claude

        // Capture history before inserting new message
        let history = Array(messages.suffix(8).map { AIChatHistoryItem(role: $0.role, content: $0.content) })
        inputText = ""
        failedRequestText = nil
        let storedText = imageDataList.isEmpty ? text : "[图片附件]\(text.isEmpty ? "" : "\n\(text)")"
        modelContext.insert(AIChatMessage(role: "user", content: storedText, provider: provider))

        guard settings?.isAIConfigured == true, let s = settings else {
            if !imageDataList.isEmpty {
                GlobalBannerCenter.shared.show(title: "图片输入不可用", message: "请先配置支持视觉输入的 AI 模型。", tone: .warning)
                failedRequestText = text
                failedRequestImages = imageDataList
                failedRequestHistory = history
                return
            }
            // Local rule-only path (no API key configured)
            if let draft = LocalAIIntentParser.parseTask(from: text) {
                pendingTask = draft
                modelContext.insert(AIChatMessage(
                    role: "assistant",
                    content: PlanAIReplyBuilder.draftReady,
                    provider: provider,
                    toolName: "create_task"
                ))
                isShowingConfirmation = true
            } else {
                modelContext.insert(AIChatMessage(
                    role: "assistant",
                    content: PlanAIReplyBuilder.unconfigured,
                    provider: provider
                ))
            }
            HapticEngine.success()
            return
        }

        // AI 请求路径
        startLoading(images: !imageDataList.isEmpty)
        let aiService = ConfiguredAIService(settings: s, configurationService: configService)
        let ctx = buildContext(planItems: planItems, selectedDate: selectedDate)

        Task {
            do {
                let response: String
                if imageDataList.isEmpty {
                    response = try await aiService.sendMessage(text, history: history, context: ctx)
                } else {
                    response = try await aiService.sendMessageWithImages(text, imageDataList: imageDataList, history: history, context: ctx)
                }
                stopLoading()
                // Show AI response as a plain message first
                modelContext.insert(AIChatMessage(
                    role: "assistant",
                    content: response,
                    provider: provider
                ))
                // Only open task draft confirmation if the original text was a task-creation command
                if let draft = LocalAIIntentParser.parseTask(from: text) {
                    pendingTask = draft
                    isShowingConfirmation = true
                }
                HapticEngine.success()
            } catch {
                stopLoading()
                let errMsg = (error as? AIClientError)?.errorDescription ?? error.localizedDescription
                failedRequestText = text
                failedRequestImages = imageDataList
                failedRequestHistory = history
                GlobalBannerCenter.shared.show(title: "AI 请求失败", message: errMsg, tone: .error)
                HapticEngine.warning()
            }
        }
    }

    func retryLastRequest(
        settings: UserSettings?,
        planItems: [PlanItem],
        selectedDate: Date,
        modelContext: ModelContext
    ) {
        guard let text = failedRequestText, let settings else { return }
        let images = failedRequestImages
        let history = failedRequestHistory
        let provider = settings.selectedAIProvider
        failedRequestText = nil
        failedRequestImages = []
        failedRequestHistory = []
        startLoading(images: !images.isEmpty)

        Task {
            do {
                let service = ConfiguredAIService(settings: settings, configurationService: configService)
                let ctx = buildContext(planItems: planItems, selectedDate: selectedDate)
                let response: String
                if images.isEmpty {
                    response = try await service.sendMessage(text, history: history, context: ctx)
                } else {
                    response = try await service.sendMessageWithImages(text, imageDataList: images, history: history, context: ctx)
                }
                stopLoading()
                modelContext.insert(AIChatMessage(role: "assistant", content: response, provider: provider))
                HapticEngine.success()
            } catch {
                stopLoading()
                failedRequestText = text
                failedRequestImages = images
                failedRequestHistory = history
                let errMsg = (error as? AIClientError)?.errorDescription ?? error.localizedDescription
                GlobalBannerCenter.shared.show(title: "AI 请求失败", message: errMsg, tone: .error)
                HapticEngine.warning()
            }
        }
    }

    // MARK: - Task Draft Confirmation

    func save(_ task: AIParsedTask, settings: UserSettings?, modelContext: ModelContext) {
        if let validationError = PlanTaskValidation.error(for: task) {
            GlobalBannerCenter.shared.show(title: "任务草稿无效", message: validationError, tone: .warning)
            return
        }
        let provider = settings?.selectedAIProvider ?? .claude
        let item = PlanAIIntentRecorder.createTask(task, in: modelContext)
        modelContext.insert(AIChatMessage(
            role: "assistant",
            content: PlanAIReplyBuilder.createdTask(task.title),
            provider: provider,
            toolName: "create_task"
        ))
        pendingTask = nil
        HapticEngine.success()

        // 撤销 Toast — 3 秒后自动消失并给出 warning 触感
        undoItem = item
        undoTaskTitle = task.title
        Task {
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            await MainActor.run {
                guard undoItem != nil else { return }
                HapticEngine.warning()
                withAnimation(.easeInOut(duration: 0.25)) { undoItem = nil }
            }
        }
    }

    func undoTaskCreation(modelContext: ModelContext) {
        guard let item = undoItem else { return }
        HapticEngine.warning()
        PlanItemService.delete(item, in: modelContext)
        undoItem = nil
    }

    // MARK: - Loading

    func startLoading(images: Bool = false) {
        isLoading = true
        isLoadingImages = images
        loadingSeconds = 0
        loadingTimer?.invalidate()
        loadingTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.loadingSeconds += 1 }
        }
    }

    func stopLoading() {
        isLoading = false
        isLoadingImages = false
        loadingTimer?.invalidate()
        loadingTimer = nil
    }

    // MARK: - Context

    private func buildContext(planItems: [PlanItem], selectedDate: Date) -> AIDataContext {
        PlanAIDataContextBuilder.make(items: planItems, selectedDate: selectedDate)
    }
}
