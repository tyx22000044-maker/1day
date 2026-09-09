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
    let messages: [AIClientMessage]
    let images: [AIImageAttachment]
    let model: String
    let apiKey: String
    let timeoutInterval: TimeInterval

    var image: AIImageAttachment { images[0] }

    init(messages: [AIClientMessage],
         image: AIImageAttachment,
         model: String,
         apiKey: String,
         timeoutInterval: TimeInterval = 45) {
        self.init(
            messages: messages,
            images: [image],
            model: model,
            apiKey: apiKey,
            timeoutInterval: timeoutInterval
        )
    }

    init(messages: [AIClientMessage],
         images: [AIImageAttachment],
         model: String,
         apiKey: String,
         timeoutInterval: TimeInterval = 45) {
        self.messages = messages
        self.images = Array(images.prefix(6))
        self.model = model
        self.apiKey = apiKey
        self.timeoutInterval = timeoutInterval
    }
}

protocol AIVisionClient {
    var supportsVision: Bool { get }
    func sendWithImage(_ request: AIVisionRequest) async throws -> AIClientResponse
}
