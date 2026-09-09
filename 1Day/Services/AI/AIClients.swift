import Foundation

// MARK: - Claude

struct ClaudeClient: AIClient {
    let provider: AIProvider = .claude

    func send(_ request: AIClientRequest) async throws -> AIClientResponse {
        guard let url = URL(string: "https://api.anthropic.com/v1/messages") else {
            throw AIClientError.invalidResponse
        }

        let systemContent = request.messages.first(where: { $0.role == .system })?.content
        let conversation = request.messages.filter { $0.role != .system }

        let body = ClaudeRequestBody(
            model: request.model,
            maxTokens: 1024,
            system: systemContent,
            messages: conversation.map { ClaudeMessage(role: $0.role.rawValue, content: $0.content) }
        )

        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.setValue(request.apiKey, forHTTPHeaderField: "x-api-key")
        urlRequest.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        urlRequest.timeoutInterval = request.timeoutInterval
        urlRequest.httpBody = try JSONEncoder().encode(body)

        let (data, response) = try await URLSession.shared.data(for: urlRequest)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw AIClientError.invalidResponse
        }

        let rawPayload = String(data: data, encoding: .utf8)

        guard (200..<300).contains(httpResponse.statusCode) else {
            let err = try? JSONDecoder().decode(ClaudeErrorBody.self, from: data)
            throw AIClientError.providerError(err?.error.message ?? "Claude 请求失败（\(httpResponse.statusCode)）")
        }

        let decoded = try JSONDecoder().decode(ClaudeResponseBody.self, from: data)
        let text = decoded.content.compactMap { $0.text }.joined()
        guard !text.isEmpty else { throw AIClientError.invalidResponse }

        return AIClientResponse(text: text, rawPayload: rawPayload)
    }
}

private struct ClaudeRequestBody: Encodable {
    let model: String
    let maxTokens: Int
    let system: String?
    let messages: [ClaudeMessage]

    enum CodingKeys: String, CodingKey {
        case model, system, messages
        case maxTokens = "max_tokens"
    }
}

private struct ClaudeMessage: Encodable {
    let role: String
    let content: String
}

private struct ClaudeResponseBody: Decodable {
    let content: [ClaudeContentBlock]
}

private struct ClaudeContentBlock: Decodable {
    let type: String
    let text: String?
}

private struct ClaudeErrorBody: Decodable {
    struct ErrorDetail: Decodable { let message: String }
    let error: ErrorDetail
}

extension ClaudeClient: AIVisionClient {
    var supportsVision: Bool { true }

    func sendWithImage(_ request: AIVisionRequest) async throws -> AIClientResponse {
        guard let url = URL(string: "https://api.anthropic.com/v1/messages") else {
            throw AIClientError.invalidResponse
        }

        let systemContent = request.messages.first(where: { $0.role == .system })?.content
        let textContent = request.messages.last(where: { $0.role == .user })?.content ?? "请分析这张图片。"
        let imageBlocks = request.images.map { image in
            [
                "type": "image",
                "source": [
                    "type": "base64",
                    "media_type": image.mediaType,
                    "data": image.data.base64EncodedString()
                ]
            ]
        }
        let message: [String: Any] = [
            "role": "user",
            "content": imageBlocks + [["type": "text", "text": textContent]]
        ]
        var body: [String: Any] = [
            "model": request.model,
            "max_tokens": 1024,
            "messages": [message]
        ]
        if let systemContent, !systemContent.isEmpty {
            body["system"] = systemContent
        }

        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.setValue(request.apiKey, forHTTPHeaderField: "x-api-key")
        urlRequest.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        urlRequest.timeoutInterval = request.timeoutInterval
        urlRequest.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: urlRequest)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw AIClientError.invalidResponse
        }
        let rawPayload = String(data: data, encoding: .utf8)
        guard (200..<300).contains(httpResponse.statusCode) else {
            let err = try? JSONDecoder().decode(ClaudeErrorBody.self, from: data)
            throw AIClientError.providerError(err?.error.message ?? "Claude 图片请求失败（\(httpResponse.statusCode)）")
        }
        let decoded = try JSONDecoder().decode(ClaudeResponseBody.self, from: data)
        let text = decoded.content.compactMap { $0.text }.joined()
        guard !text.isEmpty else { throw AIClientError.invalidResponse }
        return AIClientResponse(text: text, rawPayload: rawPayload)
    }
}

// MARK: - OpenAI

struct OpenAIClient: AIClient {
    let provider: AIProvider = .chatGPT

    func send(_ request: AIClientRequest) async throws -> AIClientResponse {
        guard let url = URL(string: "https://api.openai.com/v1/responses") else {
            throw AIClientError.invalidResponse
        }

        let body = OpenAIRequestBody(
            model: request.model,
            input: request.messages.map {
                OpenAIInputMessage(role: $0.role.rawValue, content: $0.content)
            }
        )

        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.setValue("Bearer \(request.apiKey)", forHTTPHeaderField: "Authorization")
        urlRequest.timeoutInterval = request.timeoutInterval
        urlRequest.httpBody = try JSONEncoder().encode(body)

        let (data, response) = try await URLSession.shared.data(for: urlRequest)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw AIClientError.invalidResponse
        }

        let rawPayload = String(data: data, encoding: .utf8)
        let decoded = try? JSONDecoder().decode(OpenAIResponseBody.self, from: data)

        guard (200..<300).contains(httpResponse.statusCode) else {
            let message = decoded?.error?.message ?? "OpenAI 请求失败（\(httpResponse.statusCode)）"
            throw AIClientError.providerError(message)
        }

        guard let text = decoded?.displayText, !text.isEmpty else {
            throw AIClientError.invalidResponse
        }

        return AIClientResponse(text: text, rawPayload: rawPayload)
    }
}

private struct OpenAIRequestBody: Encodable {
    let model: String
    let input: [OpenAIInputMessage]
}

private struct OpenAIInputMessage: Encodable {
    let role: String
    let content: String
}

private struct OpenAIResponseBody: Decodable {
    let outputText: String?
    let output: [OpenAIOutputItem]?
    let error: OpenAIErrorBody?

    var displayText: String {
        if let outputText, !outputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return outputText
        }
        let textParts = output?
            .flatMap { $0.content ?? [] }
            .compactMap(\.text) ?? []
        return textParts
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: "\n")
    }

    enum CodingKeys: String, CodingKey {
        case outputText = "output_text"
        case output, error
    }
}

private struct OpenAIOutputItem: Decodable {
    let content: [OpenAIOutputContent]?
}

private struct OpenAIOutputContent: Decodable {
    let text: String?
}

private struct OpenAIErrorBody: Decodable {
    let message: String?
}

extension OpenAIClient: AIVisionClient {
    var supportsVision: Bool { true }

    func sendWithImage(_ request: AIVisionRequest) async throws -> AIClientResponse {
        guard let url = URL(string: "https://api.openai.com/v1/responses") else {
            throw AIClientError.invalidResponse
        }

        let imageBlocks: [[String: Any]] = request.images.map { image in
            ["type": "input_image", "image_url": "data:\(image.mediaType);base64,\(image.data.base64EncodedString())"]
        }
        let lastUserIndex = request.messages.lastIndex { $0.role == .user }
        let input = request.messages.enumerated().map { index, message -> [String: Any] in
            if let lastUserIndex, index == lastUserIndex {
                return [
                    "role": message.role.rawValue,
                    "content": [["type": "input_text", "text": message.content]] + imageBlocks
                ]
            }
            return [
                "role": message.role.rawValue,
                "content": message.content
            ]
        }
        let body: [String: Any] = [
            "model": request.model,
            "input": input
        ]

        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.setValue("Bearer \(request.apiKey)", forHTTPHeaderField: "Authorization")
        urlRequest.timeoutInterval = request.timeoutInterval
        urlRequest.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: urlRequest)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw AIClientError.invalidResponse
        }

        let rawPayload = String(data: data, encoding: .utf8)
        let decoded = try? JSONDecoder().decode(OpenAIResponseBody.self, from: data)
        guard (200..<300).contains(httpResponse.statusCode) else {
            let message = decoded?.error?.message ?? "OpenAI 图片请求失败（\(httpResponse.statusCode)）"
            throw AIClientError.providerError(message)
        }
        guard let text = decoded?.displayText, !text.isEmpty else {
            throw AIClientError.invalidResponse
        }
        return AIClientResponse(text: text, rawPayload: rawPayload)
    }
}

// MARK: - OpenAI-compatible helper (Kimi / Qwen / Doubao / Yuanbao / MiMo)

private func sendChatCompletion(baseURL: String, request: AIClientRequest) async throws -> String {
    guard let url = URL(string: baseURL) else { throw AIClientError.invalidResponse }

    let body = CCBody(
        model: request.model,
        messages: request.messages.map { CCMsg(role: $0.role.rawValue, content: $0.content) }
    )

    var urlRequest = URLRequest(url: url)
    urlRequest.httpMethod = "POST"
    urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
    urlRequest.setValue("Bearer \(request.apiKey)", forHTTPHeaderField: "Authorization")
    urlRequest.timeoutInterval = request.timeoutInterval
    urlRequest.httpBody = try JSONEncoder().encode(body)

    let (data, response) = try await URLSession.shared.data(for: urlRequest)
    guard let httpResponse = response as? HTTPURLResponse else { throw AIClientError.invalidResponse }

    guard (200..<300).contains(httpResponse.statusCode) else {
        let err = try? JSONDecoder().decode(CCError.self, from: data)
        throw AIClientError.providerError(err?.error.message ?? "请求失败（\(httpResponse.statusCode)）")
    }

    let decoded = try JSONDecoder().decode(CCResponse.self, from: data)
    guard let text = decoded.choices.first?.message.content, !text.isEmpty else {
        throw AIClientError.invalidResponse
    }
    return text
}

private func sendOpenAICompatibleMultimodal(baseURL: String, request: AIVisionRequest) async throws -> String {
    guard let url = URL(string: baseURL) else { throw AIClientError.invalidResponse }
    let lastUserIndex = request.messages.lastIndex { $0.role == .user }
    let imageBlocks: [[String: Any]] = request.images.map { image in
        [
            "type": "image_url",
            "image_url": ["url": "data:\(image.mediaType);base64,\(image.data.base64EncodedString())"]
        ]
    }

    let messages: [[String: Any]] = request.messages.enumerated().map { index, message in
        if let lastUserIndex, index == lastUserIndex {
            return [
                "role": message.role.rawValue,
                "content": imageBlocks + [["type": "text", "text": message.content]]
            ]
        }
        return ["role": message.role.rawValue, "content": message.content]
    }

    let body: [String: Any] = [
        "model": request.model,
        "messages": messages
    ]

    var urlRequest = URLRequest(url: url)
    urlRequest.httpMethod = "POST"
    urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
    urlRequest.setValue("Bearer \(request.apiKey)", forHTTPHeaderField: "Authorization")
    urlRequest.timeoutInterval = request.timeoutInterval
    urlRequest.httpBody = try JSONSerialization.data(withJSONObject: body)

    let (data, response) = try await URLSession.shared.data(for: urlRequest)
    guard let httpResponse = response as? HTTPURLResponse else { throw AIClientError.invalidResponse }

    guard (200..<300).contains(httpResponse.statusCode) else {
        let err = try? JSONDecoder().decode(CCError.self, from: data)
        throw AIClientError.providerError(err?.error.message ?? "多模态请求失败（\(httpResponse.statusCode)）")
    }

    let decoded = try JSONDecoder().decode(CCResponse.self, from: data)
    guard let text = decoded.choices.first?.message.content, !text.isEmpty else {
        throw AIClientError.invalidResponse
    }
    return text
}

private struct CCBody: Encodable {
    let model: String
    let messages: [CCMsg]
}

private struct CCMsg: Encodable {
    let role: String
    let content: String
}

private struct CCResponse: Decodable {
    struct Choice: Decodable {
        struct Msg: Decodable { let content: String }
        let message: Msg
    }
    let choices: [Choice]
}

private struct CCError: Decodable {
    struct Body: Decodable { let message: String }
    let error: Body
}

// MARK: - Kimi

struct KimiClient: AIClient, AIVisionClient {
    let provider: AIProvider = .kimi
    var supportsVision: Bool { true }

    func send(_ request: AIClientRequest) async throws -> AIClientResponse {
        let text = try await sendChatCompletion(
            baseURL: "https://api.moonshot.cn/v1/chat/completions",
            request: request
        )
        return AIClientResponse(text: text, rawPayload: nil)
    }

    func sendWithImage(_ request: AIVisionRequest) async throws -> AIClientResponse {
        let text = try await sendOpenAICompatibleMultimodal(
            baseURL: "https://api.moonshot.cn/v1/chat/completions",
            request: request
        )
        return AIClientResponse(text: text, rawPayload: nil)
    }
}

// MARK: - 通义千问

struct QwenClient: AIClient, AIVisionClient {
    let provider: AIProvider = .qwen
    var supportsVision: Bool { true }

    func send(_ request: AIClientRequest) async throws -> AIClientResponse {
        let text = try await sendChatCompletion(
            baseURL: "https://dashscope.aliyuncs.com/compatible-mode/v1/chat/completions",
            request: request
        )
        return AIClientResponse(text: text, rawPayload: nil)
    }

    func sendWithImage(_ request: AIVisionRequest) async throws -> AIClientResponse {
        let text = try await sendOpenAICompatibleMultimodal(
            baseURL: "https://dashscope.aliyuncs.com/compatible-mode/v1/chat/completions",
            request: request
        )
        return AIClientResponse(text: text, rawPayload: nil)
    }
}

// MARK: - 豆包

struct DoubaoClient: AIClient, AIVisionClient {
    let provider: AIProvider = .doubao
    var supportsVision: Bool { true }

    func send(_ request: AIClientRequest) async throws -> AIClientResponse {
        let text = try await sendChatCompletion(
            baseURL: "https://ark.cn-beijing.volces.com/api/v3/chat/completions",
            request: request
        )
        return AIClientResponse(text: text, rawPayload: nil)
    }

    func sendWithImage(_ request: AIVisionRequest) async throws -> AIClientResponse {
        let text = try await sendOpenAICompatibleMultimodal(
            baseURL: "https://ark.cn-beijing.volces.com/api/v3/chat/completions",
            request: request
        )
        return AIClientResponse(text: text, rawPayload: nil)
    }
}

// MARK: - 腾讯元宝（混元）

struct YuanbaoClient: AIClient, AIVisionClient {
    let provider: AIProvider = .yuanbao
    var supportsVision: Bool { true }

    func send(_ request: AIClientRequest) async throws -> AIClientResponse {
        let text = try await sendChatCompletion(
            baseURL: "https://api.hunyuan.cloud.tencent.com/v1/chat/completions",
            request: request
        )
        return AIClientResponse(text: text, rawPayload: nil)
    }

    func sendWithImage(_ request: AIVisionRequest) async throws -> AIClientResponse {
        let text = try await sendOpenAICompatibleMultimodal(
            baseURL: "https://api.hunyuan.cloud.tencent.com/v1/chat/completions",
            request: request
        )
        return AIClientResponse(text: text, rawPayload: nil)
    }
}

// MARK: - 小米 MiMo

struct MiMoClient: AIClient, AIVisionClient {
    let provider: AIProvider = .mimo
    var supportsVision: Bool { true }

    func send(_ request: AIClientRequest) async throws -> AIClientResponse {
        let text = try await sendChatCompletion(
            baseURL: "https://token-plan-cn.xiaomimimo.com/v1/chat/completions",
            request: request
        )
        return AIClientResponse(text: text, rawPayload: nil)
    }

    func sendWithImage(_ request: AIVisionRequest) async throws -> AIClientResponse {
        let text = try await sendOpenAICompatibleMultimodal(
            baseURL: "https://token-plan-cn.xiaomimimo.com/v1/chat/completions",
            request: request
        )
        return AIClientResponse(text: text, rawPayload: nil)
    }
}

// MARK: - DeepSeek

struct DeepSeekClient: AIClient {
    let provider: AIProvider = .deepseek

    func send(_ request: AIClientRequest) async throws -> AIClientResponse {
        let text = try await sendChatCompletion(
            baseURL: "https://api.deepseek.com/v1/chat/completions",
            request: request
        )
        return AIClientResponse(text: text, rawPayload: nil)
    }
}

// MARK: - Factory

struct AIClientFactory {
    func client(for provider: AIProvider) throws -> AIClient {
        switch provider {
        case .claude:  return ClaudeClient()
        case .chatGPT: return OpenAIClient()
        case .kimi:    return KimiClient()
        case .qwen:    return QwenClient()
        case .doubao:  return DoubaoClient()
        case .yuanbao: return YuanbaoClient()
        case .mimo:    return MiMoClient()
        case .deepseek: return DeepSeekClient()
        }
    }

    func visionClient(for provider: AIProvider) throws -> AIVisionClient? {
        let client = try client(for: provider)
        guard let visionClient = client as? AIVisionClient, visionClient.supportsVision else {
            return nil
        }
        return visionClient
    }
}
