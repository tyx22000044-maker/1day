import Foundation

/// 应用统一错误类型
enum AppError: LocalizedError, Identifiable {
    case aiMissingAPIKey
    case aiRequestFailed(String)
    case aiTimeout
    case aiInvalidResponse
    case dataExportFailed(String)
    case dataImportFailed(String)
    case dataCorruption(String)
    case general(String)

    var id: String {
        switch self {
        case .aiMissingAPIKey: return "aiMissingAPIKey"
        case .aiRequestFailed(let msg): return "aiRequestFailed-\(msg)"
        case .aiTimeout: return "aiTimeout"
        case .aiInvalidResponse: return "aiInvalidResponse"
        case .dataExportFailed(let msg): return "dataExportFailed-\(msg)"
        case .dataImportFailed(let msg): return "dataImportFailed-\(msg)"
        case .dataCorruption(let msg): return "dataCorruption-\(msg)"
        case .general(let msg): return "general-\(msg)"
        }
    }

    var errorDescription: String? {
        switch self {
        case .aiMissingAPIKey:
            return "请先在设置中配置 AI API Key"
        case .aiRequestFailed(let detail):
            return "AI 请求失败，请稍后重试"
        case .aiTimeout:
            return "AI 响应超时，请检查网络后重试"
        case .aiInvalidResponse:
            return "AI 返回了无法识别的结果"
        case .dataExportFailed(let detail):
            return "数据导出失败：\(detail)"
        case .dataImportFailed(let detail):
            return "数据导入失败：\(detail)"
        case .dataCorruption(let detail):
            return "数据异常：\(detail)"
        case .general(let message):
            return message
        }
    }

    var recoverySuggestion: String? {
        switch self {
        case .aiMissingAPIKey:
            return "前往「设置 → AI 配置」添加 API Key"
        case .aiTimeout:
            return "请检查网络连接，或切换其他 AI 服务商"
        case .aiRequestFailed:
            return "可尝试切换其他 AI 服务商或稍后再试"
        default:
            return nil
        }
    }

    /// 从 AI 错误转换
    static func from(_ error: Error) -> AppError {
        if let appError = error as? AppError {
            return appError
        }
        if let aiError = error as? AIClientError {
            switch aiError {
            case .missingAPIKey:
                return .aiMissingAPIKey
            case .invalidResponse:
                return .aiInvalidResponse
            case .providerError(let msg):
                return .aiRequestFailed(msg)
            default:
                return .aiRequestFailed(aiError.localizedDescription)
            }
        }
        return .general(error.localizedDescription)
    }
}
