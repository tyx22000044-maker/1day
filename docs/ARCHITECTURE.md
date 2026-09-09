# 1Day 架构说明

> 最后更新：2026-06-30

---

## 技术栈

| 层 | 技术 |
|----|------|
| UI | SwiftUI + NavigationStack |
| 数据持久化 | SwiftData（@Model / @Query） |
| 敏感数据 | iOS Keychain（API Key） |
| 通知 | UserNotifications + UNUserNotificationCenterDelegate |
| 语音输入 | Speech + AVFoundation |
| AI 接口 | 自定义 AIClient 协议，支持多服务商 |

---

## 目录结构

```
1Day/
├── 1DayApp.swift          # App 入口，ModelContainer 注册所有 @Model 类型
├── ContentView.swift       # TabView 路由 + Onboarding 条件展示 + 全局 Banner
├── Models/
│   ├── PlanItem.swift      # 任务模型
│   ├── Note.swift          # 笔记模型
│   └── UserSettings.swift  # 用户设置（单例，@Attribute(.unique) id）
├── Services/
│   ├── AI/
│   │   ├── AIService.swift         # 协议定义、ConfiguredAIService、LocalAIIntentParser、AIDataContext
│   │   ├── AIClient.swift          # AIClient 协议 + AIClientRequest/Response
│   │   ├── AIClients.swift         # 各服务商 HTTP 实现（Claude/OpenAI/Kimi/…）
│   │   ├── AIConfigurationService.swift  # 读写 Keychain、validateLocalConfiguration
│   │   └── KeychainService.swift   # Keychain 底层 CRUD
│   ├── Backup/
│   │   └── JSONBackupService.swift # 导出/导入/清空（不含 API Key）
│   ├── Notification/
│   │   └── NotificationService.swift  # 调度/取消提醒、通知快捷动作、文案生成
│   └── PlanItemService.swift       # 任务 CRUD（createTask/toggleCompletion/delete/refreshReminder）
├── ViewModels/
│   └── AppViewModel.swift          # 全局 @Observable：selectedTab、错误 Banner
├── Views/
│   ├── Today/TodayView.swift       # Tab 1：今日视图
│   ├── Plan/PlanListView.swift     # Tab 2：计划列表（含 TaskEditorSheet、TaskDetailView、QuickScheduleSheet）
│   ├── AIChat/
│   │   ├── AIChatView.swift        # Tab 3：AI 聊天
│   │   ├── AIChatComponents.swift  # AIConfigurationHeader、AIEmptyState、AIRequestProgressView、AIMessageBubble
│   │   └── SpeechInputController.swift  # @Observable 语音识别控制器
│   ├── Notes/
│   │   ├── NotesListView.swift
│   │   └── NoteEditorView.swift
│   ├── Settings/SettingsView.swift # Tab 5：设置（含 AIConfigurationSettingsView 内嵌）
│   └── Onboarding/OnboardingView.swift
└── Extensions/
    └── Extensions.swift            # HapticEngine、AppLogger、共享 UI 组件
```

---

## 数据流

### 任务生命周期

```
用户输入
  │
  ├─ TodayView 快速输入 ──────────────────────┐
  ├─ TaskEditorSheet（Plan/Today 的 + 按钮）  │── PlanItemService.createTask()
  ├─ AIChatView 确认 Sheet ─────────────────── │     │
  └─ AI 解析 + 本地确认                        │   SwiftData @Model 写入
                                              │     │
  完成 ────────── PlanItemService.toggleCompletion()
  删除 ────────── PlanItemService.delete()
  提醒刷新 ───── PlanItemService.refreshReminder() ── NotificationService.scheduleTaskReminder()
```

### AI 请求流

```
用户发送文本
  │
  ├─ LocalAIIntentParser.hasTaskCreationIntent() → false → 纯聊天路径
  │
  └─ true（任务意图）
        │
        ├─ 未配置 AI：本地解析草稿 → TaskDraftConfirmationView
        │
        └─ 已配置 AI：
              ConfiguredAIService.sendMessage(text, history, context: AIDataContext)
                   │
                   ├─ AI 回复作为 assistant 消息写入 SwiftData
                   └─ LocalAIIntentParser 解析 → 有草稿 → TaskDraftConfirmationView
```

### 默认提醒时间桥接

```
UserSettings.defaultReminderHour/Minute（SwiftData）
  │── 设置变更时 → NotificationService.syncDefaultReminderTime() → UserDefaults
  │── App 启动时 → ContentView.onAppear → syncDefaultReminderTime()
  │
NotificationService.reminderDate() 读 UserDefaults（可在后台/通知扩展中访问）
```

---

## 关键设计决策

### SwiftData 模型注册
`OneDayApp.swift` 的 `.modelContainer(for: [PlanItem.self, Note.self, UserSettings.self, AIChatMessage.self])` 必须包含所有 `@Model` 类型。`NotificationService.completeTask()` 里的临时容器同样需要同步。

### UserSettings 单例
通过 `@Attribute(.unique) var id` 保证只有一条记录。视图用 `@Query private var settings: [UserSettings]` 取 `settings.first`。

### API Key 隔离
永远存 Keychain，不进 SwiftData，不进 JSON 备份。`JSONBackupService` 的 `UserSettingsBackup` 故意不包含 `aiAPIKey` 字段。

### 通知文案生成
`NotificationService.notificationBody(for:triggerDate:)` 根据截止日期（今天/明天/将来）+ 优先级 + 备注动态生成，避免所有通知显示同一文案。

### AI 对话 / 任务草稿分流
`LocalAIIntentParser.hasTaskCreationIntent()` 三层过滤：
1. 疑问句排除（含"什么"/"怎么"/"？"等）
2. 明确创建动词直接通过
3. 日期词 + 任务动词组合判定

### 语音输入
`SpeechInputController` 是 `@Observable @MainActor` 类，持有 AVAudioEngine + SFSpeechRecognizer。`AIChatView` 用 `@State private var speechController = SpeechInputController()` 持有，通过 `toggleRecording(onTranscript:)` 回调实时更新 `inputText`。

---

## 家族复用约定

参见 `docs/REUSE_PLAN.md`。核心复用层：
- `Extensions.swift`：`HapticEngine`、`AppLogger`、`PrimaryButton`、`AppEmptyStateView`、`AppSettingsRow`、`UserAvatarView`、`AppErrorBanner`
- AI 服务层（AIClient 协议 + 各服务商实现）在家族内共享，各 App 分别维护自己的 prompt
