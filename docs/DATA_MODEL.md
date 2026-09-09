# 1Day — 数据模型

> 版本：v3.0 · 最后更新：2026-06-29
> 目的：保证所有开发者（含 AI Coding）对字段定义一致，避免字段名/类型前后不同。
> 权威来源：PRD.md v3.0 第六节

---

## 模型总览

渐进式扩展：每个版本只引入该版本需要的模型和字段。

| 版本 | 模型 | 作用 |
|------|------|------|
| V1.0 | PlanItem | 任务（核心模型） |
| V1.0 | Note | 独立笔记 |
| V1.0 | UserSettings | 用户设置 |
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
| id | UUID | ✅ | auto | 主键 |
| title | String | ✅ | — | 任务标题 |
| notes | String | ❌ | "" | 备注 |
| dueDate | Date? | ❌ | nil | 截止日期，nil = "未安排" |
| status | ItemStatus | ✅ | .pending | 任务状态 |
| priority | Priority | ✅ | .none | 优先级 |
| createdAt | Date | ✅ | now | 创建时间 |
| updatedAt | Date | ✅ | now | 最后更新时间 |
| completedAt | Date? | ❌ | nil | 完成时间，标记完成时写入 |
| reminderTime | Date? | ❌ | nil | 自定义提醒时间，nil 则使用全局默认 |

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

**Swift 模型示例**：
```swift
@Model
final class PlanItem {
    var id: UUID = UUID()
    var title: String = ""
    var notes: String = ""
    var dueDate: Date?
    var status: ItemStatus = .pending
    var priority: Priority = .none
    var createdAt: Date = Date()
    var updatedAt: Date = Date()
    var completedAt: Date?
    var reminderTime: Date?
}
```

**示例 JSON**（导出/AI 草稿）：
```json
{
  "id": "A1B2C3D4-...",
  "title": "交房租",
  "notes": "转账到房东招商银行",
  "dueDate": "2026-07-01T00:00:00Z",
  "status": "pending",
  "priority": "high",
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
| id | UUID | ✅ | auto | 主键 |
| title | String | ❌ | "" | 笔记标题，可为空 |
| content | String | ❌ | "" | 笔记正文，纯文本 |
| createdAt | Date | ✅ | now | 创建时间 |
| updatedAt | Date | ✅ | now | 最后更新时间 |

**Swift 模型示例**：
```swift
@Model
final class Note {
    var id: UUID = UUID()
    var title: String = ""
    var content: String = ""
    var createdAt: Date = Date()
    var updatedAt: Date = Date()
}
```

**列表预览规则**：
- 有标题 → 显示标题
- 无标题 → 显示 content 第一行（截取前 50 字符）
- 标题和内容都为空 → 显示「空笔记」

---

### UserSettings

用户设置，单例模型（App 内只有一条记录）。

| 字段 | 类型 | 必填 | 默认值 | 说明 |
|------|------|------|--------|------|
| id | UUID | ✅ | auto | 主键 |
| userName | String | ❌ | "" | 用户昵称 |
| avatarImageData | Data? | ❌ | nil | 头像照片数据 |
| defaultReminderTime | Date | ✅ | 09:00 | 默认提醒时间 |
| appearance | Appearance | ✅ | .system | 外观模式 |
| language | Language | ✅ | .system | 语言 |

**枚举 Appearance**：
```swift
enum Appearance: String, Codable {
    case system
    case light
    case dark
}
```

**枚举 Language**：
```swift
enum Language: String, Codable {
    case system
    case zhHans  // 简体中文
    case en      // English
}
```

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

## 模型关系图

```
V1.0:
  PlanItem ──(独立)
  Note ──(独立)
  UserSettings ──(独立，单例)

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
