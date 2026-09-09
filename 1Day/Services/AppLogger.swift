import Foundation
import os

/// 统一日志系统，封装 os.Logger
enum AppLogger {
    private static let base = Logger(
        subsystem: "com.yunxuan.1day",
        category: "general"
    )

    // MARK: - 通用

    static func info(_ message: String, file: String = #fileID, function: String = #function) {
        base.info("[\(file):\(function)] \(message)")
    }

    static func warning(_ message: String, file: String = #fileID, function: String = #function) {
        base.warning("[\(file):\(function)] \(message)")
    }

    static func error(_ message: String, file: String = #fileID, function: String = #function) {
        base.error("[\(file):\(function)] \(message)")
    }

    // MARK: - 数据迁移

    static func migration(_ message: String) {
        base.info("[Migration] \(message)")
    }

    // MARK: - AI 请求

    static func ai(_ message: String) {
        base.info("[AI] \(message)")
    }

    static func aiError(_ message: String) {
        base.error("[AI] \(message)")
    }

    // MARK: - 数据操作

    static func data(_ message: String) {
        base.info("[Data] \(message)")
    }

    static func dataError(_ message: String) {
        base.error("[Data] \(message)")
    }
}
