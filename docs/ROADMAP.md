# 1Day 功能 Roadmap

> 最后更新：2026-06-30（P0+P1 全部闭环，Tab 功能补齐；AI 语音输入、上下文注入、Today 已完成折叠、Settings 测试连接）
> 状态说明：✅ 已完成 | ❌ 待开发 | 🔮 后续版本

---

## 当前判断

> 基于 2026-06-30 两轮开发后的状态。

- P0 编译错误已修复，P1 全部闭环，部分 Tab 功能已补齐。
- 已修复/完成：TodayView 编译错误、AI 消息持久化（SwiftData）、通知默认时间联动 UserSettings（UserDefaults 桥接）、JSON 备份恢复、AI 配置 Header 接入、Onboarding AI Config 步骤、Today 排序（时间→优先级）、Plan 分组内排序（日期+优先级）、Plan 设定日期快捷操作、TaskDetailView 自定义提醒时间、空笔记自动清理、Notes 搜索空状态引导。
- **下一阶段重点**：Today 已完成区块折叠、进度趋势图、AI 实际接口闭环验证、P2 架构整理（ARCHITECTURE.md）。

---

## V1.0 — MVP 发布闭环

> 目标：把“能跑”提升到“能稳定日用”。优先级顺序必须按：可编译 → 任务闭环 → 通知闭环 → AI 闭环 → 数据闭环。

### 项目基础

- [x] `OneDayApp.swift`：App 入口、Splash、SwiftData 容器 ✅
- [x] `ContentView.swift`：TabView + Onboarding 路由 ✅
- [x] `PlanItem` / `Note` / `UserSettings` SwiftData 模型 ✅
- [x] `AppViewModel`：Tab 状态、全局错误 Banner ✅
- [x] 家族统一 `Extensions.swift`、`PrimaryButton`、`AppErrorBanner`、`UserAvatarView` ✅
- [x] `README.md`：基础项目说明 ✅
- [x] 修复 `Views/Today/TodayView.swift` 文件头拼写错误，恢复可编译状态 ✅

### SwiftData 模型

- [x] `PlanItem`：标题、备注、日期、状态、优先级、提醒时间、完成时间 ✅
- [x] `Note`：标题、正文、创建/更新时间 ✅
- [x] `UserSettings`：昵称、头像、语言、外观、默认提醒时间、AI 配置、Onboarding 状态 ✅
- [x] 补充 `AIChatMessage` 持久化模型（@Model），替代当前仅存在于内存的聊天消息结构 ✅
- [ ] 评估并决定 `PlanItem.id` / `Note.id` / `UserSettings.id` 是否继续保留 `@Attribute(.unique)` 约束

### Tab 1 — 今天（Today）

- [x] 日期标题导航 ✅
- [x] 顶部快速输入栏（回车创建今日任务）✅
- [x] 过期任务区块 ✅
- [x] 今日待办区块 ✅
- [x] 今日已完成区块 ✅
- [x] 今日进度摘要卡 ✅
- [x] 空状态引导 ✅
- [x] 右上角 `+` → 新建任务 Sheet ✅
- [x] 左滑删除 / 右滑完成 ✅
- [x] 点击进入任务详情页 ✅
- [x] 快速输入发送按钮长按选择日期（Menu primaryAction：单击今天，长按菜单选明天/稍后安排）✅
- [x] 今日任务排序补齐到”时间 → 优先级” ✅
- [x] 已完成任务折叠区（带计数的可折叠 header，动画展开收起）✅
- [x] 进度卡点击展开近 7 天趋势迷你图（竖柱图，今天高亮蓝色）✅
- [x] 顶部快速输入创建后支持”稍后安排”（toast 4s，点击移除今天日期）✅

### Tab 2 — 计划（Plan）

- [x] 任务分组：未安排 / 已过期 / 今天 / 明天 / 本周 / 更晚 ✅
- [x] 未安排分组置顶 ✅
- [x] 左滑删除 / 右滑完成 ✅
- [x] 点击进入详情编辑 ✅
- [x] 空状态引导 ✅
- [x] 新建任务 Sheet ✅
- [x] 左滑”设定日期”快捷操作（QuickScheduleSheet）✅
- [x] 分组内排序统一到日期 + 优先级 ✅
- [x] 列表行补充更多任务摘要信息（备注预览 + 提醒图标）✅
- [x] 编辑页补充提醒时间与状态控制 ✅

### Tab 3 — AI

- [x] 家族统一 AI 页面基础布局 ✅
- [x] 本地规则解析 `create_task` 草稿 ✅
- [x] 任务确认 Sheet ✅
- [x] 保存后通过 `PlanItemService` 写入任务 ✅
- [x] AI 基础组件、服务商客户端、Keychain 服务存在 ✅
- [x] 消息跨会话持久化（SwiftData @Model）✅
- [x] 配置状态 Header ✅
- [x] 快捷建议 Chips ✅
- [x] 语音输入（SpeechInputController 接入，麦克风按钮，实时转写）✅
- [x] 真实服务商请求闭环验证（ConfiguredAIService 接入）✅
- [x] AI 未配置空状态与”去设置”路径 ✅
- [x] 任务创建后的撤销 toast ✅
- [x] 普通聊天与结构化任务草稿分流（意图检测：疑问句/闲聊不触发草稿，仅明确创建指令才弹确认 Sheet）✅
- [x] 上下文注入：`get_today_tasks` ✅
- [x] 上下文注入：`get_upcoming` ✅

### Tab 4 — 笔记（Notes）

- [x] 笔记列表 ✅
- [x] 搜索（标题 + 内容）✅
- [x] 新建笔记 ✅
- [x] 编辑笔记 ✅
- [x] 删除笔记 ✅
- [x] 列表按 `updatedAt` 倒序 ✅
- [x] 无标题回退为正文前缀 ✅
- [x] 空状态引导 ✅
- [x] 新建空笔记后若直接返回的清理策略（onDisappear 删除空笔记）✅
- [x] 笔记编辑保存反馈（toolbar 已保存标识）✅
- [x] 搜索结果为空时的更完整引导 ✅

### Tab 5 — 设置（Settings）

- [x] 个人资料（昵称 / 头像）✅
- [x] 语言设置 ✅
- [x] 外观设置 ✅
- [x] 默认提醒时间设置字段 ✅
- [x] AI 配置基础入口 ✅
- [x] 关于 / 隐私文案基础展示 ✅
- [x] 清空数据入口 ✅
- [ ] 默认提醒时间真正联动通知调度
- [x] AI 配置支持测试连接（发送测试消息，显示成功/失败状态）✅
- [ ] 数据导出入口接通 `JSONBackupService`
- [ ] 数据恢复入口
- [ ] 用户手册 / 隐私说明改为稳定 Markdown 单一数据源
- [ ] 设置页文案与 README/PRD 同步

### Onboarding

- [x] Welcome ✅
- [x] Profile ✅
- [x] 基础提醒时间相关字段已存在于模型 ✅
- [x] AI 可跳过的产品方向已确定 ✅
- [x] Language + 外观偏好步骤 ✅
- [x] 默认提醒时间选择步骤（DatePicker + 快捷按钮 + 通知权限申请）✅
- [x] AI Config 步骤（功能介绍 + 可选说明）✅
- [x] Ready 摘要页 ✅
- [x] 进度点 + 返回/跳过体验 ✅

### 通知

- [x] 本地通知授权请求 ✅
- [x] 任务提醒调度 ✅
- [x] 删除任务时取消 pending notification ✅
- [x] 完成任务时取消 pending notification ✅
- [x] 通知快捷动作“标记完成” ✅
- [ ] 使用 `UserSettings.defaultReminderHour/defaultReminderMinute` 作为默认提醒时间
- [ ] 单任务自定义提醒：当天 / 提前 1 天 / 提前 1 小时 / 自定义
- [ ] 首次设置日期时再更精细地触发权限请求
- [x] 通知文案根据日期和任务类型更自然（今天/明天/将来 + 优先级 + 备注分支）✅

### 数据与备份

- [x] `JSONBackupService.swift` 文件已建立 ✅
- [ ] JSON 完整备份打通
- [ ] JSON 恢复打通
- [ ] 明确备份范围：任务 / 笔记 / 设置，排除 AI API Key
- [ ] 清空数据仅删除业务数据，保留个人资料和 AI 配置的策略确认

### 测试

- [x] `1DayTests` target 已存在 ✅
- [ ] 增加 `PlanItemService` 测试：创建 / 完成 / 删除 / 提醒刷新
- [ ] 增加通知测试：默认时间、取消、完成动作
- [ ] 增加 Notes 搜索与空标题显示测试
- [ ] 增加 SwiftData 启动与首条 `UserSettings` 初始化测试
- [ ] 增加 AI 任务草稿解析测试

---

## 代码走读后发现的近期优先级

### P0 — 正确性 / 先修再谈新功能

- [ ] 修复 `Views/Today/TodayView.swift` 第 1 行拼写错误，恢复编译
- [ ] 校验 `TaskEditorSheet`、`TaskDetailView`、`TodayView`、`PlanListView` 的创建/编辑日期逻辑是否完全一致
- [ ] 校验通知快捷动作完成任务时，主数据容器和通知用临时容器之间的一致性
- [ ] 检查当前 AI 页面是否会在切换页面后丢失对话状态

### P1 — MVP 闭环补齐

- [ ] 把 AI 聊天改为 SwiftData 持久化，而不是 `@State [AIChatMessage]`
- [ ] 把通知默认时间从服务层硬编码迁移到 `UserSettings`
- [ ] 补 AI 配置状态 Header、未配置空状态和设置跳转
- [ ] 打通 JSON 备份/恢复
- [ ] Onboarding 步骤补齐到 PRD 要求

### P2 — 架构与可维护性

- [ ] 拆分 `SettingsView.swift` 内嵌的 `AIConfigurationSettingsView`（需在 Xcode 先建文件）
- [x] 统一任务创建/编辑/删除入口经 `PlanItemService` ✅
- [x] AI 功能数据流：输入 → 意图检测 → 草稿 → 确认 → 写库 → 撤销 ✅
- [x] `ARCHITECTURE.md` ✅

---

## V1.1 — 组织能力

- [ ] 收藏集（Collection）：创建、编辑、删除、任务归属、进度显示
- [ ] 标签（Tag）：创建、编辑、删除、按标签筛选
- [ ] 子任务：任务内添加子任务，可折叠
- [ ] 筛选：按状态 / 标签 / 日期范围
- [ ] 排序：按日期 / 优先级 / 创建时间 / 手动拖拽
- [ ] 全局搜索：跨任务和笔记全文搜索
- [ ] Tab 2 增加“收藏集”分段视图
- [ ] 笔记支持标签分类

---

## V1.2 — 日程与日历

- [ ] `PlanItem` 增加 type：task / event
- [ ] 事件：`startDate` + `endDate` + `location`
- [ ] 日历视图：月 / 周 / 日
- [ ] 时间块显示
- [ ] 笔记挂载到事件
- [ ] 重复任务 / 重复事件
- [ ] AI：`create_event`
- [ ] AI：`create_tasks`
- [ ] AI：`get_today_tasks`
- [ ] AI：`get_upcoming`

---

## V1.3 — 想法、证件与复盘

- [ ] `Idea` 独立模型
- [ ] 想法转任务
- [ ] 证件管理：元数据 + 到期提醒
- [ ] 证件照片文件存储与分享
- [ ] Face ID 保护
- [ ] 日/周复盘笔记
- [ ] AI 复盘摘要：`get_review_summary`
- [ ] AI 笔记整理：`organize_notes`

---

## 文档建设

- [x] `README.md` ✅
- [x] `PRD.md` ✅
- [x] `docs/MVP_SCOPE.md` ✅
- [x] `docs/DATA_MODEL.md` ✅
- [x] `docs/UX_FLOW.md` ✅
- [x] `docs/AI_BEHAVIOR_SPEC.md` ✅
- [x] `docs/REUSE_PLAN.md` ✅
- [ ] `docs/ROADMAP.md` 持续维护
- [x] `ARCHITECTURE.md` ✅
- [ ] `USER_MANUAL.md`
- [ ] `PRIVACY.md`
- [ ] `CHANGELOG.md`

---

## 产品补充想法

**录入效率**
- [ ] Today 快速输入支持自然语言日期解析
- [ ] 最近使用优先级 / 常用短语快捷输入
- [ ] 长按任务快速改期到今天 / 明天 / 本周

**笔记体验**
- [ ] 会议纪要模板
- [ ] Pin 置顶笔记
- [ ] 从笔记中一键抽取待办

**AI 体验**
- [ ] “帮我整理今天”晨间建议
- [ ] 晚间未完成事项总结
- [ ] 根据近期未完成任务建议拆分成更小步骤

**系统能力**
- [ ] iCloud 同步（远期）
- [ ] Widget
- [ ] Siri Shortcuts / App Intents
- [ ] Spotlight 搜索

---

*此文件用于记录 1Day 的功能状态、近期优先级和后续规划；每次功能更新后同步维护。*
