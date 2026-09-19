# 1Day 架构说明

> 最后更新：2026-09-20

---

## 技术栈

| 层 | 技术 |
|----|------|
| UI | SwiftUI + NavigationStack |
| 数据持久化 | SwiftData（@Model / @Query / VersionedSchema + SchemaMigrationPlan） |
| 敏感数据 | iOS Keychain（API Key） |
| 通知 | UserNotifications + UNUserNotificationCenterDelegate |
| 语音输入 | Speech + AVFoundation |
| AI 接口 | 自定义 AIClient 协议，支持多服务商 |
| 测试 | Swift Testing（`1DayTests/OneDayTests.swift`） |

---

## 目录结构

```
1Day/
├── OneDayApp.swift         # App 入口、ModelContainerHealth、AppContainer、OneDayModelContainer
├── ContentView.swift       # TabView 路由 + Onboarding 条件展示 + 存储风险 Banner + 错误 Banner
├── App/AppTab.swift        # Tab 枚举
├── Components/             # 家族共用视觉组件（Swiss Ledger token 的消费者）
│   ├── SystemPanel.swift   # 面板 / 分隔线 / SystemStatusBadge / FamilyTaskRow / UndoDeleteToast
│   ├── AppErrorBanner.swift、PrimaryButton.swift、AppEmptyStateView.swift
│   └── AppSettingsRow.swift、UserAvatarView.swift、SectionHeader.swift、SystemTextField.swift
├── Models/
│   ├── PlanItem.swift      # 任务模型
│   ├── Note.swift          # 笔记模型
│   ├── UserSettings.swift  # 用户设置（singletonID + SettingsBootstrap 收敛）
│   ├── AppSchema.swift     # OneDaySchemaV1 / OneDayMigrationPlan / AppSchema.current
│   └── SharedTypes.swift   # AppLanguage、Priority、AppText（中英文案表）
├── Services/
│   ├── AI/
│   │   ├── AIService.swift         # ConfiguredAIService、AIIntentDecoder、AIContextPolicy、LocalAIIntentParser、AIChatViewModel
│   │   ├── AIClient.swift          # AIClient 协议 + AIClientRequest / AIVisionRequest（图片上限校验）
│   │   ├── AIClients.swift         # 各服务商 HTTP 实现（Claude/OpenAI/Kimi/…）
│   │   ├── AIConfigurationService.swift  # Keychain 读写 + AIConfigurationCoordinator（服务商/模型切换）
│   │   └── KeychainService.swift   # Keychain 底层 CRUD
│   ├── Backup/JSONBackupService.swift  # 导出/导入/清空：先校验后落盘，失败回滚
│   ├── DeletionCoordinator.swift       # 任务与笔记的快照 → 删除 → 撤销窗口
│   ├── Image/ImageService.swift        # 尺寸/质量双阶梯压缩，保证 maxBytes
│   ├── Notification/NotificationService.swift  # NotificationScheduler actor、权限状态、文案生成
│   ├── Plan/PlanItemService.swift      # 任务 CRUD 与提醒刷新
│   ├── AppError.swift、AppLogger.swift
├── ViewModels/
│   ├── AppViewModel.swift  # 全局 @Observable：selectedTab；FeedbackPreferences：触觉/声音开关
│   └── GlobalBannerCenter.swift  # 全局错误 Banner 状态（按 id 展示与关闭）
├── Views/
│   ├── Today/TodayView.swift       # Tab 1：今日视图
│   ├── Plan/PlanListView.swift     # Tab 2：计划列表（TaskEditorSheet、PlanItemDetailView、QuickScheduleSheet）
│   ├── AIChat/                     # Tab 3：AI 聊天（含图片、语音、草稿确认）
│   ├── Notes/                      # Tab 4：笔记列表与编辑器
│   ├── Settings/SettingsView.swift # Tab 5：设置（含 AI 配置、提醒权限、隐私说明）
│   ├── Onboarding/OnboardingView.swift
│   └── Splash/SplashView.swift
└── Extensions.swift        # FamilyUI / FamilyTypography / AppSpacing / HapticEngine / Date 本地化

1DayTests/OneDayTests.swift # Swift Testing 回归用例
```

---

## 数据流

### 持久化容器

```
OneDayApp.init
  │
  └─ OneDayModelContainer.make(configuration:) → Outcome(container, health)
        │
        ├─ 成功 → health = .persisted
        └─ 失败 → health = .inMemoryOnly(reason)（不再静默当成正常）
              │
              └─ AppContainer.register(_:health:) → ContentView 顶部 StorageRiskBanner
```

全 App 只有一个 `ModelContainer`：`AppContainer.current` 供通知扩展回调、AI 保存等非视图入口使用，
任何地方再建第二个容器都会在同一个 store 上形成写入竞争。

### 任务生命周期

```
用户输入
  │
  ├─ TodayView 快速输入 ──────────────────────┐
  ├─ TaskEditorSheet（Plan/Today 的 + 按钮）  │── PlanItemService.createTask(PlanItemDraft)
  ├─ AIChatView 草稿确认卡 ─────────────────── │     │
  └─ 备份恢复 ────────────────────────────────┘   SwiftData @Model 写入
                                                  │
  完成 ───── PlanItemService.toggleCompletion() ─── NotificationScheduler（重排或取消）
  改期 ───── PlanItemService.updateSchedule() ───── NotificationScheduler
  删除 ───── DeletionCoordinator.snapshot → delete → 撤销窗口内 restore
```

### AI 请求流

```
用户发送文本 / 图片
  │
  ├─ AIChatViewModel.send()：可取消的 Task，停止或重新发送会取消上一次请求
  │
  ├─ AIContextPolicy.needsPlanContext() → false → 不外发任务列表
  │
  └─ ConfiguredAIService（未配置时走本地规则解析）
        │
        ├─ AIIntentDecoder：优先解析服务商返回的结构化 JSON 草稿
        ├─ LocalAIIntentParser：中文规则兜底
        └─ 两条路径都只产出草稿 → TaskDraftConfirmationView → 用户确认后才写入
```

首答、重试、图片三种回复路径共用同一套「解析 → 草稿 → 确认」逻辑；纯聊天回复不会打开确认卡。

### 提醒时间桥接

```
UserSettings.defaultReminderHour/Minute（SwiftData，事实来源）
  │── 表单预填：UserSettings.reminderDate(on:) → 落在任务当天
  │── 服务层镜像：NotificationService.syncDefaultReminderTime() → UserDefaults
  │                 （通知调度和通知扩展拿不到 SwiftData 上下文）
  │── App 启动时：ContentView bootstrap → sync + 校准 AI 配置
  │
  └─ 默认值变更后：applyDefaultReminderRefresh() 重排「跟随默认」的未完成任务，
     新默认点已过的则取消通知；带自定义提醒时间的任务不动。
```

---

## 关键设计决策

### 一个 store 只能有一个容器
`AppContainer` 是唯一注册点。`OneDayModelContainer.make` 在存储不可写时退回内存容器，
同时把原因写进 `ModelContainerHealth`，界面顶部的 `StorageRiskBanner` 持续提示并提供导出出口。
「静默退回内存容器」意味着用户重启后数据消失，这是最不可接受的失败方式。

### Schema 与迁移
模型类型集中在 `AppSchema.current`（`OneDaySchemaV1`）。容器统一带 `OneDayMigrationPlan` 打开，
新增字段走 lightweight migration；`stages` 目前为空，等有破坏性变更时在这里写迁移步骤。

### UserSettings 单例
`singletonID` 固定 + `SettingsBootstrap.ensureSettings(in:)` 把历史遗留的多条记录收敛成
`createdAt` 最早的一条，并显式 `save()`。只 `insert` 不 `save` 会让用户重启后掉回 onboarding。

### 通知按任务串行调度
`NotificationScheduler` 是 actor，按 `itemID` 串成一条链并记录代次：同一任务连续改期时，
后一次一定等前一次结束才开始，被取代的旧操作整段跳过。旧实现裸开 `Task` 会让旧请求后完成，
把已经排好的提醒删掉，通知中心留下指向旧日期的条目。

调度失败与权限被拒都会回报到 `GlobalBannerCenter`（`ReminderDeliveryProblem`），不再只写日志。

### 备份恢复先校验后落盘
`JSONBackupService` 先解码并校验（`schemaVersion` 上限、字段范围、记录 id 冲突），
再关闭 autosave 执行删除与插入，`save()` 失败即 `rollback()`；通知的取消与重排放在 `save()` 成功之后。
`BackupRestoreError` 给出具体的字段和值，而不是「导入失败」。

### 删除有撤销窗口
任务和笔记的删除统一走 `DeletionCoordinator`：先做值快照，删除并保存后给出 `UndoDeleteToast`，
窗口内可原样恢复（含完成时间、提醒时间、图片）。二次确认在删除入口，不在撤销里。

### 图片有硬上限
`ImageService.compressedData(_:maxBytes:)` 沿尺寸阶梯和质量阶梯逐级压缩，压不进上限就抛
`ImageCompressionError` 而不是返回超限数据；`AIVisionRequest` 另有一张图片数和空图片列表的构造期校验。

### AI Key 与配置状态
API Key 永远存 Keychain，不进 SwiftData，也不进 JSON 备份。服务商/模型切换只能通过
`AIConfigurationCoordinator`，它按当前服务商的 Keychain 实际内容重算 `isAIConfigured`；
启动时 `revalidateAIConfiguration()` 再校准一次，避免界面显示「已启用」而当前服务商根本没有 Key。

### 文案与本地化
中英共用文案集中在 `AppText`（`Key` 枚举 + 表格），日期统一走 `Date.dayHeading(in:)` /
`shortDate(in:)` / `weekdayName(in:)` 这类带 `Locale` 的方法，不再有用例残留的写死 `zh_CN` formatter。
设置详情页与部分通知文案仍以中文为主，属于已知覆盖缺口。

### 字体与 Dynamic Type
`FamilyTypography` 用 `Font.custom(_:relativeTo:)` 提供随系统文字大小缩放的字号；
组件不再用固定高度框住文字，大字号下换行而不是截断。

### AI 输入意图过滤
`LocalAIIntentParser.hasTaskCreationIntent()` 四步：
1. 真疑问词或问号直接排除（"什么" / "怎么" / "？"…）
2. 明确创建动词优先通过——句尾的「吧 / 呢 / 吗」是礼貌语气，不是提问
3. 没有创建动词时，句尾语气词仍按疑问排除
4. 日期词 + 任务动词组合兜底判定

### 语音输入
`SpeechInputController` 是 `@Observable @MainActor` 类，用显式阶段机（idle → requesting →
authorizing → recording → finishing）保证一次只有一场识别：录音进行中再次点击是取消，
而不是叠第二个音频会话；权限回调、结果回调和超时都会把状态收回 idle。

---

## 家族复用约定

参见 `docs/REUSE_PLAN.md`。核心复用层：
- `Extensions.swift`：`FamilyUI`、`FamilyTypography`、`AppSpacing`、`HapticEngine`、`AppLogger`
- `Components/`：`SystemPanel`、`PrimaryButton`、`AppEmptyStateView`、`AppSettingsRow`、
  `UserAvatarView`、`AppErrorBanner`
- AI 服务层（`AIClient` 协议 + 各服务商实现）在家族内共享，各 App 分别维护自己的 prompt
