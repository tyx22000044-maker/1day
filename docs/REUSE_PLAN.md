# 1Day — 文件复用清单

> 版本：v1.0 · 最后更新：2026-06-29
> 目的：明确哪些文件从 1Cash 复制、哪些需要改、哪些全新写。减少重复开发。
> 来源：1Cash（75 个 Swift 文件）、1Track（51 个 Swift 文件）

---

## 总览

| 分类 | 数量 | 说明 |
|------|------|------|
| 直接复制 | 19 个文件 | 改 import/命名空间即可，逻辑不动 |
| 复制后改写 | 14 个文件 | 骨架保留，替换业务逻辑 |
| 全新编写 | ~12 个文件 | 1Day 独有的业务视图和模型 |

---

## 一、直接复制（19 个文件）

这些文件是家族共享的基础设施，逻辑通用，复制后只改 bundle ID / app name。

### Components/（6 个）

| 源文件（1Cash） | 1Day 路径 | 改动 |
|---|---|---|
| Components/UserAvatarView.swift | Components/UserAvatarView.swift | 无 |
| Components/PrimaryButton.swift | Components/PrimaryButton.swift | 无 |
| Components/AppEmptyStateView.swift | Components/AppEmptyStateView.swift | 无 |
| Components/AppErrorBanner.swift | Components/AppErrorBanner.swift | 无 |
| Components/AppSettingsRow.swift | Components/AppSettingsRow.swift | 无 |
| Components/SectionHeader.swift | Components/SectionHeader.swift | 无 |

### Services/AI/（7 个）

| 源文件（1Cash） | 1Day 路径 | 改动 |
|---|---|---|
| Services/AI/AIClient.swift | Services/AI/AIClient.swift | 无 |
| Services/AI/AIClients.swift | Services/AI/AIClients.swift | 无 |
| Services/AI/AIConfigurationService.swift | Services/AI/AIConfigurationService.swift | 无 |
| Services/AI/KeychainService.swift | Services/AI/KeychainService.swift | 无 |
| Services/AI/AIService.swift | Services/AI/AIService.swift | 无（通用 AI 请求调度） |
| Services/Image/ImageService.swift | Services/Image/ImageService.swift | 无 |
| Services/AppLogger.swift | Services/AppLogger.swift | 改 subsystem 字符串 |

### Views/AIChat/ 通用部分（4 个）

| 源文件（1Cash） | 1Day 路径 | 改动 |
|---|---|---|
| Views/AIChat/AIChatFormatting.swift | Views/AIChat/AIChatFormatting.swift | 无 |
| Views/AIChat/AIChatComponents.swift | Views/AIChat/AIChatComponents.swift | 无 |
| Views/AIChat/AIImagePicker.swift | Views/AIChat/AIImagePicker.swift | 无 |
| Views/AIChat/SpeechInputController.swift | Views/AIChat/SpeechInputController.swift | 无 |

### 其他（2 个）

| 源文件（1Cash） | 1Day 路径 | 改动 |
|---|---|---|
| Views/Splash/SplashView.swift | Views/Splash/SplashView.swift | 改 appName、iconName |
| Services/AppError.swift | Services/AppError.swift | 无（通用错误类型） |

---

## 二、复制后改写（14 个文件）

保留文件骨架和通用模式，替换业务逻辑部分。

### 核心架构（4 个）

| 源文件（1Cash） | 1Day 路径 | 保留 | 改写 |
|---|---|---|---|
| Extensions.swift | Extensions.swift | Typography、Haptics、Color、Date 格式化 | 删除 currency 格式化、account balance 逻辑 |
| App/AppRoute.swift | App/AppTab.swift | Tab 枚举结构 | Tab 改为 today/plan/ai/notes/settings |
| ContentView.swift | ContentView.swift | TabView 骨架、AI 中央按钮处理 | 替换各 Tab 对应的 View |
| OneCashApp.swift | OneDayApp.swift | SwiftData container 配置、环境注入 | Schema 改为 PlanItem/Note/UserSettings |

### Models（2 个）

| 源文件（1Cash） | 1Day 路径 | 保留 | 改写 |
|---|---|---|---|
| Models/SharedTypes.swift | Models/SharedTypes.swift | AppLanguage、AppearanceMode、AIProvider 枚举 | 删除 TransactionKind/AccountKind 等；新增 ItemStatus/Priority/ItemType 枚举 |
| Models/UserSettings.swift | Models/UserSettings.swift | @Model 结构、userName、avatar、language、appearance、AI 配置字段 | 删除 monthlyIncome/savingsTarget 等；新增 defaultReminderTime |

### AI 业务层（3 个）

| 源文件（1Cash） | 1Day 路径 | 保留 | 改写 |
|---|---|---|---|
| Services/AI/AIPromptBuilder.swift | Services/AI/AIPromptBuilder.swift | Prompt 构建结构 | 系统提示词全部重写为 1Day 任务/日程场景 |
| Services/AI/AIIntentDecoder.swift | Services/AI/AIIntentDecoder.swift | JSON 解码框架 | 解码目标从 AIParsedTransaction 改为 AIParsedTask |
| Services/AI/AIServiceModels.swift | Services/AI/AIServiceModels.swift | AIChatMessage、AIChatHistoryItem 结构 | 删除 AIParsedTransaction/AIParsedRecurringRule；新增 AIParsedTask |
| Services/AI/LocalAIIntentParser.swift | Services/AI/LocalAIIntentParser.swift | 本地规则匹配框架 | 规则从"记账"模式改为"创建任务/事件"模式 |

### Views（4 个）

| 源文件（1Cash） | 1Day 路径 | 保留 | 改写 |
|---|---|---|---|
| Views/AIChat/AIChatView.swift | Views/AIChat/AIChatView.swift | 聊天 UI 骨架、消息列表、输入栏、语音按钮 | 确认流程从"交易确认"改为"任务确认" |
| Views/AIChat/AIChatConfirmationViews.swift | Views/AIChat/AIChatConfirmationViews.swift | 确认卡片布局 | 字段从金额/分类改为日期/优先级 |
| Views/Settings/AIConfigurationSettingsView.swift | Views/Settings/AIConfigurationSettingsView.swift | 服务商列表、Key 输入、测试连接 | 几乎不改，微调文案 |
| Views/Settings/SettingsView.swift | Views/Settings/SettingsView.swift | 分组列表骨架、Profile 区、AI 区、数据管理区、关于区 | 删除账户/分类/预算/周期规则区；新增提醒时间、收藏集管理(V1.1)、证件管理(V1.3) |

### ViewModels（1 个）

| 源文件（1Cash） | 1Day 路径 | 保留 | 改写 |
|---|---|---|---|
| ViewModels/AIChatViewModel.swift | ViewModels/AIChatViewModel.swift | 消息发送/接收流程、历史管理、错误处理 | 意图处理从 Transaction 改为 Task；确认/保存逻辑适配 PlanItem |

---

## 三、全新编写（~12 个文件）

1Day 独有的业务逻辑，无法从现有 App 复制。

### Models（2 个）

| 文件 | 说明 |
|---|---|
| Models/PlanItem.swift | 任务/事件核心模型（@Model） |
| Models/Note.swift | 笔记模型（@Model） |

### Views — Tab 1 今天（2 个）

| 文件 | 说明 |
|---|---|
| Views/Today/TodayView.swift | 今日视图主页：快速输入栏 + 过期/今日/已完成列表 + 进度卡片 |
| Views/Today/QuickInputBar.swift | 快速输入组件：输入框 + 发送 + 长按日期选择 |

### Views — Tab 2 计划（2 个）

| 文件 | 说明 |
|---|---|
| Views/Plan/PlanListView.swift | 计划列表：任务按日期分组，未安排置顶 |
| Views/Plan/TaskDetailView.swift | 任务详情/编辑页 |

### Views — Tab 4 笔记（2 个）

| 文件 | 说明 |
|---|---|
| Views/Notes/NotesListView.swift | 笔记列表：搜索栏 + 笔记卡片列表 |
| Views/Notes/NoteEditorView.swift | 笔记编辑页：标题 + 正文 + 自动保存 |

### Views — Onboarding（2 个）

| 文件 | 说明 |
|---|---|
| Views/Onboarding/OnboardingView.swift | Onboarding 流程控制器（从 1Cash 改写，但步骤差异大，基本重写） |
| Views/Onboarding/OnboardingSteps.swift | 各步骤 UI（Welcome/Language/Profile/提醒时间/AI Config/Ready） |

### Services（2 个）

| 文件 | 说明 |
|---|---|
| Services/Plan/PlanItemService.swift | 任务业务入口：创建、完成/撤销完成、删除；后续承接通知副作用 |
| Services/Notification/NotificationService.swift | 本地通知调度：创建/取消通知、权限请求 |

### Backup（1 个）

| 文件 | 说明 |
|---|---|
| Services/Backup/JSONBackupService.swift | JSON 备份/恢复（从 1Cash 改写，模型不同，基本重写） |

---

## 四、不需要的文件（1Cash 有但 1Day 不用）

以下 1Cash 文件**不复制**到 1Day：

| 文件 | 原因 |
|---|---|
| Models/Transaction.swift | 1Cash 交易模型 |
| Models/BudgetCategory.swift | 1Cash 预算分类 |
| Models/SupportingModels.swift | 1Cash 账户/退款等模型 |
| DashboardView.swift | 1Cash 仪表盘 |
| HistoryView.swift | 1Cash 交易历史 |
| ReportsView.swift | 1Cash 报表 |
| AddTransactionView.swift | 1Cash 添加交易 |
| TransactionDetailView.swift | 1Cash 交易详情 |
| Views/TransactionEditorView.swift | 1Cash 交易编辑 |
| Views/TransferView.swift | 1Cash 转账 |
| Views/RefundView.swift | 1Cash 退款 |
| Views/ReimbursementView.swift | 1Cash 报销 |
| Views/Reports/*.swift（5 个） | 1Cash 报表视图 |
| Views/Settings/AccountSettingsViews.swift | 1Cash 账户设置 |
| Views/Settings/CategorySettingsViews.swift | 1Cash 分类设置 |
| Views/Settings/RecurringRuleSettingsViews.swift | 1Cash 周期规则设置 |
| Views/AIChat/AIRuleIdentificationConfirmationView.swift | 1Cash 规则识别 |
| Services/AI/RuleIdentificationConfirmation.swift | 1Cash 规则确认模型 |
| Services/Currency/*.swift（2 个） | 1Cash 货币服务 |
| Services/History/HistoryService.swift | 1Cash 历史服务 |
| Services/Ledger/LedgerCategoryResolver.swift | 1Cash 分类解析 |
| Services/Recurring/*.swift（2 个） | 1Cash 周期规则服务 |
| Services/Reports/BudgetSummaryService.swift | 1Cash 预算汇总 |
| Services/Export/ExportService.swift | 1Cash CSV 导出 |
| Services/Settings/SettingsDataService.swift | 1Cash 设置数据（可能部分复用） |
| Services/AppStartupService.swift | 1Cash 启动服务 |
| Repository/SeedData.swift | 1Cash 种子数据 |
| Repository/AppRepository.swift | 1Cash 仓库（1Day 可能需要自己的版本） |

---

## 五、开发顺序建议

### Phase 1：骨架搭建（让 App 能跑起来）
1. 用户在 Xcode 创建 1Day 项目
2. 复制 19 个直接复制文件
3. 改写 OneDayApp.swift + AppTab.swift + ContentView.swift
4. 创建 PlanItem.swift + Note.swift + UserSettings.swift（空壳模型）
5. 创建 TodayView / PlanListView / NotesListView 的空壳
6. → **目标：5 个 Tab 能切换，App 能运行**

### Phase 2：核心 CRUD
7. 完成 PlanItem 模型 + TodayView + PlanListView + TaskDetailView
8. 创建 PlanItemService，收口任务创建、完成、删除
9. 完成快速输入栏（QuickInputBar）
10. → **目标：能创建、编辑、完成、删除任务**

### Phase 3：笔记
11. 完成 Note 模型 + NotesListView + NoteEditorView
12. → **目标：能创建、编辑、搜索笔记**

### Phase 4：通知
13. 创建 NotificationService
14. 任务设置日期时调度通知
15. → **目标：到期自动提醒**

### Phase 5：AI
16. 改写 AI 业务层（AIPromptBuilder / AIIntentDecoder / AIServiceModels / LocalAIIntentParser）
17. 改写 AIChatView + AIChatConfirmationViews + AIChatViewModel
18. → **目标：自然语言创建任务**

### Phase 6：设置 + Onboarding
19. 改写 SettingsView
20. 新写 OnboardingView + OnboardingSteps
21. → **目标：完整的首次使用体验**

### Phase 7：备份 + 收尾
22. 新写 JSONBackupService
23. 空状态、本地化、进度卡片
24. → **目标：V1.0 可发布**
