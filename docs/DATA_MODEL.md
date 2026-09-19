# 1Day — 数据模型

> 版本：v3.1 · 最后更新：2026-09-20
> 目的：保证所有开发者（含 AI Coding）对字段定义一致，避免字段名/类型前后不同。
> V1.0 部分以代码为准（`1Day/Models/`、`1Day/Services/Backup/JSONBackupService.swift`）；
> V1.1 及以后仍是规划，尚未落地。

---

## 模型总览

渐进式扩展：每个版本只引入该版本需要的模型和字段。

| 版本 | 模型 | 作用 |
|------|------|------|
| V1.0 | PlanItem | 任务（核心模型） |
| V1.0 | Note | 独立笔记 |
| V1.0 | UserSettings | 用户设置（全库单例） |
| V1.0 | AIChatMessage | AI 对话历史与工具调用记录 |
| V1.1 | Collection | 收藏集/项目分组 |
| V1.1 | Tag | 标签 |
| V1.2 | RecurrenceRule | 重复规则 |
| V1.3 | Idea | 想法 |
| V1.3 | Document | 证件元数据 |
| V1.3 | ReviewEntry | 复盘记录 |

---

## V1.0 模型

### PlanItem

任务的核心模型。V1.0 中所有事项都是"任务"类型。

| 字段 | 类型 | 必填 | 默认值 | 说明 |
|------|------|------|--------|------|
| id | UUID | ✅ | auto | 主键，`@Attribute(.unique)` |
| title | String | ✅ | — | 任务标题 |
| notes | String | ❌ | "" | 备注 |
| dueDate | Date? | ❌ | nil | 截止日期，nil = "未安排" |
| statusRawValue | String | ✅ | "pending" | 存储字段，`ItemStatus` 的 rawValue |
| priorityRawValue | String | ✅ | "none" | 存储字段，`Priority` 的 rawValue |
| reminderTime | Date? | ❌ | nil | 自定义提醒时间；只用它的时分，落在 `dueDate` 当天；nil 表示跟随全局默认 |
| createdAt | Date | ✅ | now | 创建时间 |
| updatedAt | Date | ✅ | now | 最后更新时间 |
| completedAt | Date? | ❌ | nil | 完成时间，由 `status` setter 维护 |

`status` 和 `priority` 在模型里是计算属性，读写上面的 rawValue 字段；未知 rawValue 会退回
`.pending` / `.none`，以免旧数据直接崩溃。备份导入不允许这种回退（见「JSON 备份格式」）。

**枚举 ItemStatus**：
```swift
enum ItemStatus: String, Codable {
    case pending
    case completed
}
```

**枚举 Priority**：
```swift
enum Priority: String, Codable, CaseIterable {
    case none
    case low
    case medium
    case high
}
```

**Swift 模型（与代码一致）**：
```swift
@Model
final class PlanItem {
    @Attribute(.unique) var id: UUID
    var title: String
    var notes: String
    var dueDate: Date?
    var statusRawValue: String
    var priorityRawValue: String
    var reminderTime: Date?
    var createdAt: Date
    var updatedAt: Date
    var completedAt: Date?

    var status: ItemStatus { get set }     // 经由 statusRawValue
    var priority: Priority { get set }     // 经由 priorityRawValue
    var isCompleted: Bool { get }
    var isUnscheduled: Bool { get }
    func isOverdue(asOf: Date) -> Bool     // 按天比较，不按时刻
}
```

**示例 JSON**（备份文件里的记录形态，见「JSON 备份格式」）：
```json
{
  "id": "A1B2C3D4-...",
  "title": "交房租",
  "notes": "转账到房东招商银行",
  "dueDate": "2026-07-01T00:00:00Z",
  "statusRawValue": "pending",
  "priorityRawValue": "high",
  "createdAt": "2026-06-29T10:00:00Z",
  "updatedAt": "2026-06-29T10:00:00Z",
  "completedAt": null,
  "reminderTime": null
}
```

---

### Note

独立笔记。V1.0 中没有关联关系，是纯粹的文本笔记。

| 字段 | 类型 | 必填 | 默认值 | 说明 |
|------|------|------|--------|------|
| id | UUID | ✅ | auto | 主键，`@Attribute(.unique)` |
| title | String | ❌ | "" | 笔记标题，可为空 |
| content | String | ❌ | "" | 笔记正文，纯文本 |
| createdAt | Date | ✅ | now | 创建时间 |
| updatedAt | Date | ✅ | now | 最后更新时间 |

**Swift 模型（与代码一致）**：
```swift
@Model
final class Note {
    @Attribute(.unique) var id: UUID
    var title: String
    var content: String
    var createdAt: Date
    var updatedAt: Date

    var displayTitle: String { get }   // 标题 → 正文首 50 字 → 「空笔记」
    var isEmpty: Bool { get }          // 标题和正文都是空白
}
```

**列表预览规则**：
- 有标题 → 显示标题
- 无标题 → 显示 content 第一行（截取前 50 字符）
- 标题和内容都为空 → 显示「空笔记」

---

### UserSettings

用户设置，单例模型（App 内只有一条记录）。

单例由两件事共同保证：新建记录一律使用固定 id `UserSettings.singletonID`
（`1da01da0-0000-4000-8000-000000000001`），启动时 `SettingsBootstrap.ensureSettings(in:)`
把历史遗留的多条记录收敛成 `createdAt` 最早的一条并显式 `save()`。
`@Attribute(.unique)` 只挡得住相同 id 的重复插入，挡不住「两条不同 id 的设置」。

| 字段 | 类型 | 必填 | 默认值 | 说明 |
|------|------|------|--------|------|
| id | UUID | ✅ | `singletonID` | 主键，`@Attribute(.unique)` |
| dataSchemaVersion | Int | ✅ | 1 | 应用层数据版本（与 SwiftData schema 版本不同） |
| nickname | String | ❌ | "" | 用户昵称 |
| avatarSymbolName | String | ✅ | "person.crop.circle" | 无照片时的 SF Symbol 头像 |
| avatarImageData | Data? | ❌ | nil | 头像照片数据（写入前压缩到 512 KB 内） |
| languageRawValue | String | ✅ | "system" | `AppLanguage` 的 rawValue |
| appearanceRawValue | String | ✅ | "system" | `AppearanceMode` 的 rawValue |
| defaultReminderHour | Int | ✅ | 9 | 默认提醒小时（0–23） |
| defaultReminderMinute | Int | ✅ | 0 | 默认提醒分钟（0–59） |
| selectedAIProviderRawValue | String | ✅ | "claude" | `AIProvider` 的 rawValue |
| selectedAIModel | String | ✅ | "claude-sonnet" | 模型 ID |
| aiProcessingModeRawValue | String | ✅ | "ruleFirst" | `AIProcessingMode` 的 rawValue |
| isAIConfigured | Bool | ✅ | false | 当前服务商是否真的有 Key（由 Keychain 实际内容重算） |
| isHapticsEnabled | Bool | ✅ | true | 触觉开关 |
| isSoundEffectsEnabled | Bool | ✅ | true | 声音开关 |
| hasCompletedOnboarding | Bool | ✅ | false | 是否走完引导 |
| createdAt | Date | ✅ | now | 创建时间 |
| updatedAt | Date | ✅ | now | 最后更新时间 |

计算属性：`language`、`appearance`、`selectedAIProvider`、`aiProcessingMode`、
`defaultReminderTime: DateComponents`、`reminderDate(on:)`（表单预填提醒时刻用）。

**API Key 不是这个模型的字段**，它只存在 iOS Keychain，不进 SwiftData，也不进 JSON 备份。

**枚举 AppearanceMode**：
```swift
enum AppearanceMode: String, Codable, CaseIterable {
    case system
    case light
    case dark
}
```

**枚举 AppLanguage**：
```swift
enum AppLanguage: String, Codable, CaseIterable {
    case system
    case zhHans   // 简体中文
    case english  // English
}
```

---

### AIChatMessage

AI 对话历史，用于把多轮上下文发给服务商，也记录一次工具调用产生的草稿。

| 字段 | 类型 | 必填 | 默认值 | 说明 |
|------|------|------|--------|------|
| id | UUID | ✅ | auto | 主键，`@Attribute(.unique)` |
| role | String | ✅ | — | "user" / "assistant" |
| content | String | ✅ | "" | 消息正文 |
| providerRawValue | String | ✅ | "claude" | 这条消息所属的服务商 |
| createdAt | Date | ✅ | now | 创建时间 |
| toolName | String? | ❌ | nil | 工具调用名，例如 `create_task` |
| toolPayloadJSON | String? | ❌ | nil | 工具调用的值负载（草稿 JSON，非正式数据） |

聊天历史会整体发给所选服务商，因此不应写入只在 App 内查看的敏感内容。
它不进 JSON 备份，由「设置 → AI 配置 → 清空聊天历史」单独删除（有二次确认，不可恢复）。

---

## V1.1 新增

### Collection

收藏集，用于将多个 PlanItem 分组（旅行计划、搬家清单等）。

| 字段 | 类型 | 必填 | 默认值 | 说明 |
|------|------|------|--------|------|
| id | UUID | ✅ | auto | 主键 |
| name | String | ✅ | — | 收藏集名称 |
| icon | String | ✅ | "folder" | SF Symbol 名称 |
| color | String | ✅ | "#007AFF" | 颜色 hex 值 |
| sortOrder | Int | ✅ | 0 | 排序序号 |
| createdAt | Date | ✅ | now | 创建时间 |

### Tag

标签，可跨 PlanItem 和 Note 使用。

| 字段 | 类型 | 必填 | 默认值 | 说明 |
|------|------|------|--------|------|
| id | UUID | ✅ | auto | 主键 |
| name | String | ✅ | — | 标签名称 |
| color | String | ✅ | "#007AFF" | 颜色 hex 值 |

### PlanItem V1.1 新增字段

| 字段 | 类型 | 默认值 | 说明 |
|------|------|--------|------|
| collection | Collection? | nil | 所属收藏集（relationship） |
| tags | [Tag] | [] | 标签列表（relationship） |
| parentItem | PlanItem? | nil | 父任务（子任务用，relationship） |
| subItems | [PlanItem] | [] | 子任务列表（relationship，inverse of parentItem） |
| sortOrder | Int | 0 | 手动排序序号 |

### Note V1.1 新增字段

| 字段 | 类型 | 默认值 | 说明 |
|------|------|--------|------|
| tags | [Tag] | [] | 标签列表（relationship，复用 Tag 模型） |

---

## V1.2 新增

### PlanItem V1.2 新增字段

| 字段 | 类型 | 默认值 | 说明 |
|------|------|--------|------|
| type | ItemType | .task | 事项类型 |
| startDate | Date? | nil | 事件开始时间（type = .event 时使用） |
| endDate | Date? | nil | 事件结束时间（type = .event 时使用） |
| location | String? | nil | 事件地点 |
| isRecurring | Bool | false | 是否重复 |
| recurrenceRule | RecurrenceRule? | nil | 重复规则（relationship） |

**枚举 ItemType**：
```swift
enum ItemType: String, Codable {
    case task   // 任务：有截止日期，核心动作是"完成"
    case event  // 事件：有开始/结束时间，核心动作是"参加"并"记录"
}
```

**task vs event 的字段使用差异**：
- task：使用 dueDate（截止日期），status 可切换 pending/completed
- event：使用 startDate + endDate（时间段），status 不常用（事件按时间自动归入"已过去"）

### Note V1.2 新增字段

| 字段 | 类型 | 默认值 | 说明 |
|------|------|--------|------|
| linkedItem | PlanItem? | nil | 关联的事件或任务（relationship） |

一条笔记可以关联到一个 PlanItem（事件下的会议纪要），也可以不关联（独立笔记）。一个 PlanItem 可以有多条笔记。

### RecurrenceRule

| 字段 | 类型 | 必填 | 默认值 | 说明 |
|------|------|------|--------|------|
| id | UUID | ✅ | auto | 主键 |
| frequency | Frequency | ✅ | — | 重复频率 |
| interval | Int | ✅ | 1 | 每 N 个周期重复一次 |
| endDate | Date? | ❌ | nil | 重复结束日期 |

**枚举 Frequency**：
```swift
enum Frequency: String, Codable {
    case daily
    case weekly
    case monthly
    case yearly
    case weekdays  // 工作日（周一到周五）
}
```

---

## V1.3 新增

### Idea

想法，独立模型。生命周期和任务/笔记不同：想法的核心动作是"转化为任务"或"放弃"。

| 字段 | 类型 | 必填 | 默认值 | 说明 |
|------|------|------|--------|------|
| id | UUID | ✅ | auto | 主键 |
| title | String | ✅ | — | 想法标题 |
| content | String | ❌ | "" | 想法内容 |
| createdAt | Date | ✅ | now | 创建时间 |
| status | IdeaStatus | ✅ | .active | 想法状态 |
| convertedItemId | UUID? | ❌ | nil | 转化后关联的 PlanItem ID |

**枚举 IdeaStatus**：
```swift
enum IdeaStatus: String, Codable {
    case active     // 活跃，未处理
    case converted  // 已转为任务
    case archived   // 已归档/放弃
}
```

### Document

证件元数据。照片文件存储在 App 沙盒 `Documents/Credentials/` 目录，此模型只存元数据和文件名引用。

| 字段 | 类型 | 必填 | 默认值 | 说明 |
|------|------|------|--------|------|
| id | UUID | ✅ | auto | 主键 |
| name | String | ✅ | — | 证件名称，如"我的护照" |
| type | DocumentType | ✅ | — | 证件类型 |
| photoFileNames | [String] | ✅ | [] | 照片文件名列表（正面/反面/其他） |
| expiryDate | Date? | ❌ | nil | 到期日期 |
| notes | String | ❌ | "" | 备注 |
| createdAt | Date | ✅ | now | 创建时间 |
| updatedAt | Date | ✅ | now | 最后更新时间 |

**枚举 DocumentType**：
```swift
enum DocumentType: String, Codable, CaseIterable {
    case idCard         // 身份证
    case passport       // 护照
    case driverLicense  // 驾照
    case hkMacaoPass    // 港澳通行证
    case socialSecurity // 社保卡
    case other          // 其他
}
```

**照片存储规则**：
- 照片文件名格式：`{documentId}_{index}.jpg`（如 `A1B2C3D4_0.jpg`、`A1B2C3D4_1.jpg`）
- 存储路径：`{App Sandbox}/Documents/Credentials/`
- 不存入 SwiftData（避免大二进制影响性能）
- 不包含在 JSON 备份中（防止证件照片泄露）
- 访问需 Face ID / Touch ID 验证

### ReviewEntry

复盘记录。

| 字段 | 类型 | 必填 | 默认值 | 说明 |
|------|------|------|--------|------|
| id | UUID | ✅ | auto | 主键 |
| date | Date | ✅ | — | 复盘日期 |
| type | ReviewType | ✅ | — | 复盘类型 |
| notes | String | ❌ | "" | 用户手写复盘笔记 |
| completedCount | Int | ✅ | 0 | 该时段完成任务数 |
| pendingCount | Int | ✅ | 0 | 该时段未完成任务数 |
| aiSummary | String? | ❌ | nil | AI 生成的复盘摘要 |
| createdAt | Date | ✅ | now | 创建时间 |

**枚举 ReviewType**：
```swift
enum ReviewType: String, Codable {
    case daily
    case weekly
}
```

---

## Schema 与迁移

`1Day/Models/AppSchema.swift` 是模型类型的唯一清单：

- `OneDaySchemaV1: VersionedSchema`（`versionIdentifier = Schema.Version(1, 0, 0)`）声明
  `PlanItem`、`Note`、`UserSettings`、`AIChatMessage`。
- `AppSchema.current` 把上面的版本包成 `Schema`，容器和单测都从这里取，不允许再各写一份模型列表。
- `OneDayMigrationPlan: SchemaMigrationPlan` 的 `stages` 目前为空：现有变更都是新增可选字段，
  由 SwiftData 做 lightweight migration。出现破坏性变更（改类型、改语义、需要回填）时，
  在这里按版本顺序追加 `MigrationStage`，并同步更新 `BackupEnvelope.currentSchemaVersion`。

模型列表散落在多处曾经导致真实故障：视图用一个容器、通知回调用另一个临时容器，
两边在同一个 store 上并存就会写冲突。现在所有入口都通过 `AppContainer.current` 拿同一个容器。

两个版本号各管各的：`OneDaySchemaV1.versionIdentifier` 是 SwiftData 的表结构版本，
`UserSettings.currentDataSchemaVersion` 是业务数据语义版本，备份兼容看后者。

---

## JSON 备份格式

导出文件名：`1Day-Backup-<yyyyMMdd-HHmmss>.json`，写入临时目录后由系统分享面板送出；
App 不长期保存备份副本。

**顶层信封**：

```json
{
  "schemaVersion": 2,
  "exportedAt": "2026-09-20T02:00:00Z",
  "planItems": [ /* PlanItem 的值快照 */ ],
  "notes": [ /* Note 的值快照 */ ],
  "settings": { /* UserSettings 的值快照，可为缺失 */ }
}
```

| schemaVersion | 差异 |
|---------------|------|
| 1 | 没有 `isHapticsEnabled` / `isSoundEffectsEnabled` |
| 2 | 加入触觉与声音偏好；缺失这两个字段的旧备份恢复时保持目标设备当前值，不静默改回默认 |

**不包含的内容**：API Key（只在 Keychain）、AI 聊天历史、证件照片（V1.3 规划，永不进备份）。

**导入规则**（`JSONBackupService.restoreBackup`）：

1. 整体解码并校验后才动手：`schemaVersion` 高于当前版本 → `unsupportedSchemaVersion`；
   枚举 rawValue 读不懂、`title` 为空白、提醒小时不在 0–23、提醒分钟不在 0–59 → `invalidField(field:value:)`；
   备份内部 id 重复 → `duplicateRecordID`。
2. 校验通过后关闭 autosave，再删除现有任务/笔记、插入恢复对象（沿用原 id 和原时间戳）。
3. `context.save()` 失败即 `context.rollback()`，现有数据回到导入前的状态——不存在「删了一半再导入失败」。
4. 通知的取消与重排放在 `save()` 成功之后，避免恢复失败时留下指向已回滚记录的通知。

恢复后的记录会做自洽修复：`completedAt` 按状态补齐，没有 `dueDate` 的任务清掉 `reminderTime`
（没有日期就不会有通知，留着提醒时间只会让人误以为仍会被提醒）。

**错误信息**（`BackupRestoreError`）都带 `recoverySuggestion`，明确告诉用户现有数据有没有被动过。

---

## 模型关系图

```
V1.0:
  PlanItem ──(独立)
  Note ──(独立)
  UserSettings ──(独立，singletonID 单例)
  AIChatMessage ──(独立，按 providerRawValue 归属服务商)

V1.1:
  PlanItem ──→ Collection? (多对一)
  PlanItem ←→ [Tag] (多对多)
  PlanItem ←→ PlanItem (parent/sub，自引用)
  Note ←→ [Tag] (多对多)

V1.2:
  PlanItem ──→ RecurrenceRule? (一对一)
  Note ──→ PlanItem? (多对一，linkedItem)

V1.3:
  Idea ──→ PlanItem? (通过 convertedItemId，弱引用)
  Document ──(独立，照片在文件系统)
  ReviewEntry ──(独立)
```
