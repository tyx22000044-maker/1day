import Foundation
import SwiftData
import SwiftUI

/// 对外唯一的 AI 能力面：把用户输入变成一段回复文本。
///
/// 之前这里还挂着 `parseStructuredIntent` / `…WithImage(s)` 三个方法，零调用点，
/// 其中图片版本直接 `return nil` —— 等于对外宣称支持、实际静默不实现。
/// 结构化意图现在由 `AIIntentDecoder` 在真正处理回复的地方解码，契约只有一条。
protocol AIService {
    func sendMessage(_ text: String, history: [AIChatHistoryItem], context: AIDataContext?) async throws -> String
    func sendMessageWithImage(_ text: String, imageData: Data, history: [AIChatHistoryItem], context: AIDataContext?) async throws -> String
    func sendMessageWithImages(_ text: String, imageDataList: [Data], history: [AIChatHistoryItem], context: AIDataContext?) async throws -> String
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

/// 外发给服务商的最小上下文。
///
/// 刻意不含笔记标题/正文：AI_BEHAVIOR_SPEC §三 把笔记正文列为「默认不发」，
/// 之前那个从未被填充的 `recentNoteTitles` 字段只会让人以为它在往外发。
struct AIDataContext: Codable, Equatable {
    var todayTaskTitles: [String] = []
    var upcomingTaskTitles: [String] = []
}

/// 计划上下文的外发闸门。
///
/// AI_BEHAVIOR_SPEC §二 把「擅自读取全部数据」列为禁止项，§三 要求上下文按意图可选注入；
/// 之前只要配置了 AI，任何一句话都会把本地任务标题打包进 system prompt 发给第三方。
enum AIContextPolicy {
    /// 明确指向计划对象才算需要上下文；「今天」「明天」这类时间词单独出现不算，
    /// 「今天天气怎么样」不应该触发任务标题外发。
    private static let planMarkers = [
        "任务", "待办", "计划", "安排", "日程", "提醒", "截止", "复盘", "周报", "清单",
        "进度", "事项", "task", "Task", "todo", "Todo", "deadline", "schedule"
    ]

    static func needsPlanContext(for text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        if LocalAIIntentParser.hasTaskCreationIntent(in: trimmed) { return true }
        return planMarkers.contains { trimmed.contains($0) }
    }
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
            reminderTime: task.reminderTime,
            priority: task.priority ?? .none
        )
        return PlanItemService.createTask(draft, in: context)
            ?? PlanItemService.createTask(
                title: task.title,
                notes: task.notes ?? "",
                dueDate: task.dueDate,
                priority: task.priority ?? .none,
                in: context
            )
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

struct AIParsedTask: Codable, Equatable {
    var title: String
    var notes: String?
    var dueDate: Date?
    var dueDateText: String?
    var priority: Priority?
    var reminderTime: Date?
}

// MARK: - Structured intent payload

/// AI 服务商返回的结构化草稿（docs/AI_BEHAVIOR_SPEC.md §四 · V1.0 create_task）。
///
/// 之所以自己定义一份 Codable 而不是直接把 `AIParsedTask` 当协议：模型输出的字段
/// 需要独立于内部草稿类型的校验和版本策略，`AIParsedTask` 是我们自己的落库前草稿。
struct AIStructuredTaskPayload: Codable, Equatable {
    static let createTaskIntent = "create_task"
    static let supportedIntentRawValues: Set<String> = [createTaskIntent]

    /// 字段规则按 spec：title 必填，其余可选，AI 不确定时给 null 由用户在确认页补。
    struct Fields: Codable, Equatable {
        var title: String
        var notes: String?
        var dueDate: Date?
        var priority: String?
        var reminderTime: Date?
    }

    var intent: String
    var data: Fields
}

enum AIIntentDecoder {
    /// 从 AI 回复中提取并校验 create_task 草稿。
    ///
    /// 任何不认识的形状都返回 nil，让调用方回退到纯文本展示——绝不把半截数据
    /// 送进确认卡，也不静默改写字段。
    static func decodeCreateTask(from reply: String) -> AIParsedTask? {
        guard let json = extractJSONObject(from: reply),
              let payload = try? JSONDecoder.iso8601.decode(AIStructuredTaskPayload.self, from: json) else {
            return nil
        }
        guard payload.intent == AIStructuredTaskPayload.createTaskIntent else { return nil }
        return validate(payload.data)
    }

    private static func validate(_ fields: AIStructuredTaskPayload.Fields) -> AIParsedTask? {
        let title = fields.title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return nil }

        var priority: Priority?
        if let raw = fields.priority {
            // 严格：出现无法识别的优先级就当作不可信回复，回退纯文本，不猜。
            guard let parsed = Priority(rawValue: raw.trimmingCharacters(in: .whitespacesAndNewlines)) else {
                return nil
            }
            priority = parsed
        }

        let notes = fields.notes?.trimmingCharacters(in: .whitespacesAndNewlines)
        return AIParsedTask(
            title: title,
            notes: (notes?.isEmpty == false) ? notes : nil,
            dueDate: fields.dueDate,
            dueDateText: nil,
            priority: priority,
            reminderTime: fields.reminderTime
        )
    }

    /// 兼容两种回法：``` 围栏里的 JSON 块，以及裸 JSON 混在解释文字里。
    static func extractJSONObject(from reply: String) -> Data? {
        if let block = fencedJSONObject(in: reply), let data = block.data(using: .utf8) {
            return data
        }
        guard let start = reply.firstIndex(of: "{"), let end = reply.lastIndex(of: "}"), start < end else {
            return nil
        }
        return String(reply[start...end]).data(using: .utf8)
    }

    /// 取第一个看起来是 JSON 对象的围栏块；语言标注忽略，
    /// 因为模型有时写 ```json、有时只写 ```。
    private static func fencedJSONObject(in text: String) -> String? {
        var body: [String] = []
        var inside = false

        for rawLine in text.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("```") {
                if inside {
                    let candidate = body.joined(separator: "\n")
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                    if candidate.hasPrefix("{"), candidate.hasSuffix("}") {
                        return candidate
                    }
                    body = []
                }
                inside.toggle()
                continue
            }
            if inside { body.append(String(rawLine)) }
        }
        return nil
    }
}

private extension JSONDecoder {
    static var iso8601: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
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
        let images: [AIImageAttachment]
        do {
            images = try imageDataList.prefix(AIVisionRequest.maximumImageCount).map { raw in
                AIImageAttachment(data: try ImageService.compressedData(raw), mediaType: "image/jpeg")
            }
        } catch let error as ImageCompressionError {
            // 压不进上限就不发：过去会把超限的原图当压缩结果发出去，
            // 用户只会看到一句泛化的「网络请求失败」。
            AppLogger.aiError("图片压缩失败: \(error.localizedDescription)")
            throw AIClientError.providerError(error.errorDescription ?? "图片处理失败")
        }
        guard let visionClient = try clientFactory.visionClient(for: provider) else {
            throw AIClientError.providerError("当前服务商暂不支持图片输入，请切换到支持视觉输入的模型。")
        }

        let prompt = text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? "请逐张描述这些图片中与计划、任务、日程或笔记有关的信息。不要偷懒：多张图片或多个事项要逐项覆盖，不能只处理第一张或最明显的一项。不要自动创建数据，只返回可供用户确认的文字建议。"
            : text
        guard let request = AIVisionRequest(
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
        ) else {
            throw AIClientError.providerError("图片压缩后没有可用图像，请重新选择或换一张图。")
        }

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
}

enum AIPromptBuilder {
    /// AI 回复里可被确认卡解析的 JSON 约定，见 docs/AI_BEHAVIOR_SPEC.md §四。
    static let structuredTaskContract = """
    当用户这句话是要创建一条任务时，请在回复末尾额外给出一个 ```json 代码块，格式如下；\
    其余情况说明用自然语言写，不要多加别的 JSON 块。
    {"intent":"create_task","data":{"title":"交房租","notes":"转账到房东招商银行",\
    "dueDate":"2026-07-01T00:00:00Z","priority":"high","reminderTime":null}}
    字段规则：title 必填且非空；notes 可选；dueDate 和 reminderTime 为 ISO 8601 或 null；\
    priority 只能是 none / low / medium / high 之一。无法确定的字段给 null，由用户在确认页补填。
    """

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

        \(structuredTaskContract)
        """

        if let context {
            let sections: [(String, [String])] = [
                ("今日任务", context.todayTaskTitles),
                ("近期任务", context.upcomingTaskTitles)
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
        // 真疑问句永远不是创建指令。
        let strongQuestionMarkers = ["?", "？", "什么", "怎么", "为什么", "如何", "哪", "是否"]
        if strongQuestionMarkers.contains(where: { text.contains($0) }) { return false }

        // 明确创建动词优先：句尾的「吧 / 呢 / 吗」是礼貌语气，
        // 「帮我安排任务吧」是请求，不是提问。
        let creationVerbs = ["创建", "新建", "记下", "加入计划", "安排", "提醒", "记得", "别忘", "要做", "需要做", "帮我"]
        if creationVerbs.contains(where: { text.contains($0) }) { return true }

        // 没有创建动词兜底时，句尾语气词仍按疑问处理。
        let politeParticles = ["吗", "呢", "吧"]
        if politeParticles.contains(where: { text.contains($0) }) { return false }

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

    /// 进行中的网络请求句柄。「停止」必须真的取消它，而不只是收起 loading。
    private var requestTask: Task<Void, Never>?
    private var loadingTimer: Timer?
    private let configService: AIConfigurationService
    private let serviceFactory: (UserSettings) -> AIService

    init(
        configService: AIConfigurationService = LocalAIConfigurationService(),
        serviceFactory: ((UserSettings) -> AIService)? = nil
    ) {
        self.configService = configService
        self.serviceFactory = serviceFactory ?? { settings in
            ConfiguredAIService(settings: settings, configurationService: configService)
        }
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
        let aiService = serviceFactory(s)
        let ctx = buildContext(planItems: planItems, selectedDate: selectedDate, for: text)

        requestTask = Task {
            do {
                let response: String
                if imageDataList.isEmpty {
                    response = try await aiService.sendMessage(text, history: history, context: ctx)
                } else {
                    response = try await aiService.sendMessageWithImages(text, imageDataList: imageDataList, history: history, context: ctx)
                }
                try Task.checkCancellation()
                endLoading()
                handleSuccessfulResponse(
                    response,
                    originalText: text,
                    hadImages: !imageDataList.isEmpty,
                    provider: provider,
                    modelContext: modelContext
                )
            } catch {
                let wasCancelled = error is CancellationError || Task.isCancelled
                endLoading()
                // 用户主动停止：不写消息、不报失败，静默收尾。
                if wasCancelled {
                    AppLogger.ai("请求已被用户取消")
                    return
                }
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

        requestTask = Task {
            do {
                let service = serviceFactory(settings)
                let ctx = buildContext(planItems: planItems, selectedDate: selectedDate, for: text)
                let response: String
                if images.isEmpty {
                    response = try await service.sendMessage(text, history: history, context: ctx)
                } else {
                    response = try await service.sendMessageWithImages(text, imageDataList: images, history: history, context: ctx)
                }
                try Task.checkCancellation()
                endLoading()
                handleSuccessfulResponse(
                    response,
                    originalText: text,
                    hadImages: !images.isEmpty,
                    provider: provider,
                    modelContext: modelContext
                )
            } catch {
                let wasCancelled = error is CancellationError || Task.isCancelled
                endLoading()
                if wasCancelled {
                    AppLogger.ai("重试已被用户取消")
                    return
                }
                failedRequestText = text
                failedRequestImages = images
                failedRequestHistory = history
                let errMsg = (error as? AIClientError)?.errorDescription ?? error.localizedDescription
                GlobalBannerCenter.shared.show(title: "AI 请求失败", message: errMsg, tone: .error)
                HapticEngine.warning()
            }
        }
    }

    // MARK: - Response Handling

    /// 首次发送和重试共用同一条成功路径。
    ///
    /// 之前重试分支只插入回复、不跑意图解析，于是第一次请求失败的
    /// 「明天提交周报」在重试成功后变成一条普通聊天，用户再也拿不到草稿确认卡。
    private func handleSuccessfulResponse(
        _ response: String,
        originalText: String,
        hadImages: Bool,
        provider: AIProvider,
        modelContext: ModelContext
    ) {
        let draft = resolveDraft(from: response, originalText: originalText)
        var content = response
        if draft == nil, hadImages {
            // 发了图片却没整理出可确认的任务：明确说出来，而不是静默只给一段文字。
            content += "\n\n（没能从图片里整理出可确认的任务，可以补一句说明，例如「周五提交报告」，或换一张更清晰的图再试。）"
        }
        modelContext.insert(AIChatMessage(role: "assistant", content: content, provider: provider))
        if let draft {
            pendingTask = draft
            isShowingConfirmation = true
        }
        HapticEngine.success()
    }

    /// 回复 → 草稿的解析优先级：服务商给的结构化 JSON 最可信，其次才是本地规则。
    /// 两者都不认时才按普通聊天展示（AI_BEHAVIOR_SPEC §五 意图识别规则）。
    private func resolveDraft(from response: String, originalText: String) -> AIParsedTask? {
        if let structured = AIIntentDecoder.decodeCreateTask(from: response) {
            return structured
        }
        return LocalAIIntentParser.parseTask(from: originalText)
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

    /// 「停止」= 取消网络请求 + 收起 loading。
    /// URLSession 的 `data(for:)` 会响应协作取消，所以取消 Task 就真的断开了连接。
    func stopLoading() {
        requestTask?.cancel()
        endLoading()
    }

    /// 只收起 loading，不做取消：请求自己的收尾路径用它，避免任务自我取消。
    private func endLoading() {
        isLoading = false
        isLoadingImages = false
        loadingTimer?.invalidate()
        loadingTimer = nil
        requestTask = nil
    }

    // MARK: - Context

    /// 按意图决定是否构建上下文：不需要计划数据的问题，一个字的任务标题都不外发。
    private func buildContext(planItems: [PlanItem], selectedDate: Date, for text: String) -> AIDataContext? {
        guard AIContextPolicy.needsPlanContext(for: text) else { return nil }
        return PlanAIDataContextBuilder.make(items: planItems, selectedDate: selectedDate)
    }
}
