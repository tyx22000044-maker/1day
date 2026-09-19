import Foundation

enum AIRole: String, Codable {
    case system
    case user
    case assistant
}

struct AIClientMessage: Codable {
    let role: AIRole
    let content: String
}

struct AIClientRequest {
    let messages: [AIClientMessage]
    let model: String
    let apiKey: String
    let timeoutInterval: TimeInterval

    init(messages: [AIClientMessage],
         model: String,
         apiKey: String,
         timeoutInterval: TimeInterval = 30) {
        self.messages = messages
        self.model = model
        self.apiKey = apiKey
        self.timeoutInterval = timeoutInterval
    }
}

struct AIClientResponse {
    let text: String
    let rawPayload: String?
}

enum AIClientError: LocalizedError {
    case missingAPIKey
    case unsupportedProvider(AIProvider)
    case networkNotImplemented(AIProvider)
    case invalidResponse
    case providerError(String)

    var errorDescription: String? {
        switch self {
        case .missingAPIKey:
            return "缺少 API Key"
        case .unsupportedProvider(let provider):
            return "暂不支持的 AI 服务商：\(provider.rawValue)"
        case .networkNotImplemented(let provider):
            return "\(provider.rawValue) 的真实网络请求尚未接入"
        case .invalidResponse:
            return "AI 返回格式无效"
        case .providerError(let message):
            return message
        }
    }
}

protocol AIClient {
    var provider: AIProvider { get }

    func send(_ request: AIClientRequest) async throws -> AIClientResponse
}

struct AIImageAttachment {
    let data: Data
    let mediaType: String
}

struct AIVisionRequest {
    /// 服务商一次请求允许携带的图片上限，超出部分按提交顺序截断。
    static let maximumImageCount = 6

    let messages: [AIClientMessage]
    let images: [AIImageAttachment]
    let model: String
    let apiKey: String
    let timeoutInterval: TimeInterval

    /// 图片请求必须至少带一张图：空数组在以前会让学生在 `images[0]` 上越界崩溃，
    /// 所以直接把「没有图」变成构造失败，调用方拿到可诊断的分支而不是崩溃。
    init?(
        messages: [AIClientMessage],
        images: [AIImageAttachment],
        model: String,
        apiKey: String,
        timeoutInterval: TimeInterval = 45
    ) {
        guard !images.isEmpty else { return nil }
        self.messages = messages
        self.images = Array(images.prefix(Self.maximumImageCount))
        self.model = model
        self.apiKey = apiKey
        self.timeoutInterval = timeoutInterval
    }
}

protocol AIVisionClient {
    var supportsVision: Bool { get }
    func sendWithImage(_ request: AIVisionRequest) async throws -> AIClientResponse
}
