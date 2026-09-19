import Foundation
import SwiftData

/// 1Day 的 SwiftData 结构定义。
///
/// 之前容器是现场用 `Schema([四张表])` 拼出来的，没有版本化 schema 也没有迁移计划：
/// 一旦字段类型、默认值或约束改动，旧 store 打不开，只能掉进「内存容器」那条歧路（见 F-01）。
/// 从现在起，改结构必须在这里加一个 V(n) 并在迁移计划里补一个 stage。
enum OneDaySchemaV1: VersionedSchema {
    static let versionIdentifier = Schema.Version(1, 0, 0)

    /// 这里漏掉任何一个 @Model，它就不会被持久化。
    static let models: [any PersistentModel.Type] = [
        PlanItem.self,
        Note.self,
        UserSettings.self,
        AIChatMessage.self
    ]
}

/// 结构迁移计划。
///
/// 目前只有 V1，所以 stages 为空——但容器已经按「带迁移计划」的方式打开 store，
/// 后续新增版本时才有落点。每个 stage 只能描述一对源版本 → 目标版本。
enum OneDayMigrationPlan: SchemaMigrationPlan {
    static let schemas: [any VersionedSchema.Type] = [OneDaySchemaV1.self]
    static let stages: [MigrationStage] = []
}

enum AppSchema {
    /// 当前运行使用的结构。
    static var current: Schema { Schema(OneDaySchemaV1.models) }

    /// 两个版本号各管各的：`OneDaySchemaV1.versionIdentifier` 是 SwiftData 的表结构版本，
    /// `UserSettings.currentDataSchemaVersion` 是业务数据语义版本（备份兼容看它）。
    static var modelTypes: [any PersistentModel.Type] { OneDaySchemaV1.models }
}
