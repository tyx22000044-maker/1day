import Foundation

struct AIProviderOption: Identifiable {
    let provider: AIProvider
    let displayName: String
    let defaultModel: String
    let models: [String]
    let capabilityDescription: String
    /// API Key 绑定了特定接入点/模型版本（如豆包、元宝），
    /// 模型 ID 必须与控制台接入点一致，不能自由切换。
    var usesEndpointBoundKey: Bool = false

    var id: AIProvider { provider }
}

struct AIConfigurationStatus {
    let provider: AIProvider
    let model: String
    let hasAPIKey: Bool
    let maskedKey: String
}

protocol AIConfigurationService {
    var providerOptions: [AIProviderOption] { get }

    func status(for settings: UserSettings) throws -> AIConfigurationStatus
    func saveAPIKey(_ apiKey: String, provider: AIProvider) throws
    func readAPIKey(provider: AIProvider) throws -> String?
    func deleteAPIKey(provider: AIProvider) throws
    func maskedKey(for apiKey: String?) -> String
    func validateLocalConfiguration(settings: UserSettings) throws -> Bool
}

struct LocalAIConfigurationService: AIConfigurationService {
    let keychain: KeychainService

    init(keychain: KeychainService = AppKeychainService()) {
        self.keychain = keychain
    }

    var providerOptions: [AIProviderOption] {
        [
            AIProviderOption(
                provider: .claude,
                displayName: "Claude",
                defaultModel: "claude-sonnet-4-6",
                models: ["claude-opus-4-8", "claude-sonnet-4-6", "claude-haiku-4-5", "claude-sonnet", "claude-opus", "claude-haiku"],
                capabilityDescription: "支持日常对话、任务草稿整理和计划/笔记图片识别。"
            ),
            AIProviderOption(
                provider: .chatGPT,
                displayName: "ChatGPT",
                defaultModel: "gpt-5.5",
                models: ["gpt-5.5", "gpt-5.4", "gpt-5.4-mini", "gpt-5.4-nano", "gpt-5-mini", "gpt-5-nano", "gpt-5.2", "o4-mini", "gpt-4.1-mini", "gpt-4.1-nano", "gpt-4o", "gpt-4o-mini"],
                capabilityDescription: "支持日常对话、任务草稿整理和计划/笔记图片识别。"
            ),
            AIProviderOption(
                provider: .kimi,
                displayName: "Kimi",
                defaultModel: "kimi-k2.6",
                models: ["kimi-k2.6", "kimi-k2.5", "moonshot-v1-8k-vision-preview", "moonshot-v1-32k-vision-preview", "moonshot-v1-128k-vision-preview", "moonshot-v1-8k", "moonshot-v1-32k", "moonshot-v1-128k"],
                capabilityDescription: "支持日常对话、任务草稿整理和计划/笔记图片识别；非视觉 moonshot 模型仅支持文字。"
            ),
            AIProviderOption(
                provider: .qwen,
                displayName: "通义千问",
                defaultModel: "qwen-vl-plus",
                models: ["qwen-vl-plus", "qwen-vl-max", "qwen3-vl", "qwen2.5-vl", "qwen-ocr", "qwen3.7-plus", "qwen3.7-max", "qwen3.6-flash"],
                capabilityDescription: "支持日常对话、任务草稿整理和计划/笔记图片识别；非 VL/OCR 模型仅支持文字。"
            ),
            AIProviderOption(
                provider: .doubao,
                displayName: "豆包",
                defaultModel: "doubao-1.6-vision",
                models: ["doubao-1.6-vision", "doubao-seed-2-0-vision", "doubao-seed-2-1-pro-260628", "doubao-pro-32k", "doubao-lite-32k"],
                capabilityDescription: "支持日常对话、任务草稿整理和计划/笔记图片识别；模型 ID 需填写控制台接入点。",
                usesEndpointBoundKey: true
            ),
            AIProviderOption(
                provider: .yuanbao,
                displayName: "腾讯混元",
                defaultModel: "hunyuan-vision-1.5-instruct",
                models: ["hunyuan-vision-1.5-instruct", "hunyuan-t1-vision-20250916", "hunyuan-turbos-vision-video", "hunyuan-turbos-latest", "hunyuan-a13b", "hunyuan-lite", "hunyuan-turbo", "hunyuan-pro"],
                capabilityDescription: "支持日常对话、任务草稿整理和计划/笔记图片识别；模型 ID 需与接入点配置一致。",
                usesEndpointBoundKey: true
            ),
            AIProviderOption(
                provider: .mimo,
                displayName: "小米 MiMo",
                defaultModel: "mimo-v2.5",
                models: ["mimo-v2.5", "mimo-v2.5-pro"],
                capabilityDescription: "支持日常对话、任务草稿整理和计划/笔记图片识别；模型 ID 需与接入点配置一致。",
                usesEndpointBoundKey: true
            ),
            AIProviderOption(
                provider: .deepseek,
                displayName: "DeepSeek",
                defaultModel: "deepseek-chat",
                models: ["deepseek-v4-flash", "deepseek-v4-pro", "deepseek-chat", "deepseek-reasoner"],
                capabilityDescription: "支持日常对话和任务草稿整理。deepseek-reasoner 适合复杂问答；当前不支持图片识别。"
            )
        ]
    }

    func status(for settings: UserSettings) throws -> AIConfigurationStatus {
        let provider = AIProvider(rawValue: settings.selectedAIProviderRawValue) ?? .claude
        let apiKey = try readAPIKey(provider: provider)
        return AIConfigurationStatus(
            provider: provider,
            model: settings.selectedAIModel,
            hasAPIKey: apiKey?.isEmpty == false,
            maskedKey: maskedKey(for: apiKey)
        )
    }

    func saveAPIKey(_ apiKey: String, provider: AIProvider) throws {
        let trimmed = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            try deleteAPIKey(provider: provider)
        } else {
            try keychain.save(trimmed, account: keychainAccount(for: provider))
        }
    }

    func readAPIKey(provider: AIProvider) throws -> String? {
        try keychain.read(account: keychainAccount(for: provider))
    }

    func deleteAPIKey(provider: AIProvider) throws {
        try keychain.delete(account: keychainAccount(for: provider))
    }

    func maskedKey(for apiKey: String?) -> String {
        guard let apiKey, !apiKey.isEmpty else { return "未配置" }
        if apiKey.count <= 8 { return "••••" }
        return "\(apiKey.prefix(4))••••\(apiKey.suffix(4))"
    }

    func validateLocalConfiguration(settings: UserSettings) throws -> Bool {
        let provider = AIProvider(rawValue: settings.selectedAIProviderRawValue) ?? .claude
        guard let apiKey = try readAPIKey(provider: provider) else { return false }
        return apiKey.trimmingCharacters(in: .whitespacesAndNewlines).count >= 8
    }

    private func keychainAccount(for provider: AIProvider) -> String {
        "ai-api-key-\(provider.rawValue)"
    }
}

/// 服务商 / 模型切换的唯一入口。
///
/// `isAIConfigured` 必须反映**当前** provider 在 Keychain 里到底有没有可用 key。
/// 之前两处切换 UI 只改了 provider 和模型，留下上一个 provider 的布尔值：
/// 界面显示「已启用」而当前服务商根本没有 key，发送时才失败。
enum AIConfigurationCoordinator {
    @discardableResult
    static func switchProvider(
        to provider: AIProvider,
        on settings: UserSettings,
        using service: AIConfigurationService
    ) -> Bool {
        settings.selectedAIProvider = provider
        if let option = service.providerOptions.first(where: { $0.provider == provider }) {
            settings.selectedAIModel = option.defaultModel
        }
        settings.updatedAt = Date()
        settings.isAIConfigured = (try? service.validateLocalConfiguration(settings: settings)) ?? false
        AppLogger.ai("切换服务商 → \(provider.rawValue)，模型 \(settings.selectedAIModel)，已配置 \(settings.isAIConfigured)")
        return settings.isAIConfigured
    }

    /// 启动时校准一次：Keychain 可能被系统清理或用户换过服务商，
    /// 存量的 `isAIConfigured` 不能继续被当作事实。
    @discardableResult
    static func revalidate(settings: UserSettings, using service: AIConfigurationService) -> Bool {
        let configured = (try? service.validateLocalConfiguration(settings: settings)) ?? false
        if settings.isAIConfigured != configured {
            settings.isAIConfigured = configured
            AppLogger.ai("校准 AI 配置状态 → \(configured)")
        }
        return configured
    }

    @discardableResult
    static func selectModel(
        _ model: String,
        on settings: UserSettings,
        using service: AIConfigurationService
    ) -> Bool {
        let models = service.providerOptions.first { $0.provider == settings.selectedAIProvider }?.models ?? []
        guard models.contains(model), settings.selectedAIModel != model else {
            return settings.isAIConfigured
        }
        settings.selectedAIModel = model
        settings.updatedAt = Date()
        return settings.isAIConfigured
    }
}
