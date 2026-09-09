# 1Day 对齐 1Life 结构文档的补充审查（2026-07-14）

> 本文件是 `docs/1LIFE_UI_VISUAL_CONSISTENCY_REVIEW.md`（视觉设计系统维度）的姊妹篇，**不重复其内容**，只做交互/架构维度的核查：深链接机制、状态管理、数据写入路径、反馈机制、风险操作确认强度。对照基准是 `1Life/docs/structure/00_总览与跨Tab模式索引.md` 列出的跨 Tab 模式清单。
>
> 1Day 此前没有对应的结构维度审查报告可以复核，本文档是首份，因此没有"旧账复核"章节。"+"入口组件化（`FamilyAddButton`）等纯视觉发现已经记录在 `1LIFE_UI_VISUAL_CONSISTENCY_REVIEW.md` 里，本文档不重复。
>
> 已读文件：`ViewModels/AppViewModel.swift`、`ViewModels/GlobalBannerCenter.swift`、`ContentView.swift`、`Services/Plan/PlanItemService.swift`、`Views/AIChat/AIChatView.swift`（重点 1-150、400-540、600-630 行）、`Components/SystemPanel.swift`（80-100 行），以及全项目对 `modelContext.insert/delete/save`、`GlobalBannerCenter.shared.show`、`selectedTab = .`、`PlanItemService.`、`role: .destructive`、`systemName: "plus"` 的全文搜索结果逐条核实。

---

## 一、新发现的差距

### 1. 深链接机制完全缺失——`AppViewModel` 零语境字段，两处跳转全部是裸跳转

`ViewModels/AppViewModel.swift:42-46` 的 `AppViewModel` 只有 `selectedTab`/`selectedDate` 两个字段，没有任何"跳过去之后聚焦哪里"的语境字段（对比 1Life 的 4 组语境字段服务 3 条深链路径，[00§1](../../1Life/docs/structure/00_总览与跨Tab模式索引.md)；1Cash 好歹还有 1 处带语境的 `historyFilterCategory`）。全项目对 `selectedTab = .` 的搜索只有 2 处命中，且都在 `Views/AIChat/AIChatView.swift`（83 行、93 行），都是裸的 `appViewModel.selectedTab = .settings`，跳转前不写任何状态。1Day 是目前审查过的 App 里深链接密度最低的一个——不是"部分实现"，是完全没有这套机制。

### 2. `PlanItemService` 只覆盖任务（`PlanItem`），不覆盖笔记（`Notes`）——和 1Life 自己的 Writer 层缺陷是同一种形状

`Services/Plan/PlanItemService.swift` 被 `Views/Today/TodayView.swift`、`Views/Plan/PlanListView.swift`、`Views/AIChat/AIChatView.swift` 正常调用，是真实被采用的写入层（不是像 1Cash `AppRepository` 那样的死代码）。但 `Views/Notes/NotesListView.swift`、`Views/Notes/NoteEditorView.swift` 两个文件仍然直连 `modelContext.insert/delete/save`，完全绕开了任何 Service 层。

这和 [00§6](../../1Life/docs/structure/00_总览与跨Tab模式索引.md) 记录的 1Life 自己的问题是同一种形状：`FoodTimelineMealWriter` 覆盖 `FoodTimelineView` 的部分方法，但 `AddFoodSheet`/`EditFoodSheet` 仍然直连 `modelContext`——"写好了 Writer 层，但只覆盖了一个实体，没有推广到同 Tab 或其它 Tab 的其它实体"这个具体缺陷模式，在 1Day 里以"Task 有 Service、Notes 没有"的形式原样复现了。

### 3. `GlobalBannerCenter` 100% 集中在 AI Chat 一个 Tab，其余 4 个 Tab 零覆盖

`ViewModels/GlobalBannerCenter.swift:4-6` 的源码注释明确写着"Call `GlobalBannerCenter.shared.show(...)` from any Service or ViewModel instead of building one-off alerts for background failures"——这是目前审查过的所有 App（含 1Life 自己）里唯一一处在代码注释里明确写了使用规范的地方，值得肯定（见三）。但全项目对 `GlobalBannerCenter.shared.show` 的搜索只有 6 处命中，全部在 `Views/AIChat/AIChatView.swift`（199/269/410/469/502/525 行：语音输入异常、图片输入不可用、AI 请求失败×2、任务草稿无效）。`TodayView`/`PlanListView`/`NotesListView`/`SettingsView` 没有一处调用——如果这几个 Tab 也有需要提示用户的后台失败场景（比如 `SettingsView.swift` 的备份导入失败、`PlanItemService.clearAll` 的批量清除结果），目前不清楚它们是完全没有反馈，还是走了别的机制（未深挖，见四）。

---

## 二、（无旧审查报告可复核）

1Day 在本文档之前没有独立的结构/交互维度审查记录，因此没有"旧账复核"内容。

---

## 三、做得好、甚至值得反过来给 1Life 提建议的地方

1. **`PlanItemService` 是目前全家族审查过的 App 里最完整的 Writer 层实现**：`createTask`/`toggleCompletion`/`setCompletion`/`updateSchedule`/`moveToUnscheduled`/`clearAll`/`delete` 七个方法不仅处理 SwiftData 写入，还统一联动 `NotificationService`（创建任务排提醒、完成任务取消提醒、改期刷新提醒）和 `AppLogger.data` 日志（`PlanItemService.swift:51-52,63-68,84,95,100`）。1Life 自己的 `FoodTimelineMealWriter`（[00§6](../../1Life/docs/structure/00_总览与跨Tab模式索引.md)）只处理数据写入，不联动任何副作用；1Day 这套"数据+副作用一起在 Service 层收口"的模式比 1Life 的参照标准本身更完整，值得反向移植到 1Life。
2. **AI 任务创建有完整的两阶段确认状态机**：`Views/AIChat/AIChatView.swift:14-15` 的 `pendingTask: AIParsedTask?` + `isShowingConfirmation` 状态，配合 606 行起的 `TaskDraftConfirmationView`（可在确认前编辑标题/备注/日期/优先级），与 1Life 家族规范强制要求的"锁步"AI 确认模式一致，且和 1Cash 一样是真实的待确认状态机（不是 1Track 那种缺失两阶段状态机的情况）。
3. **`GlobalBannerCenter` 是唯一在源码里写明"什么场景该用"的实现**：`ViewModels/GlobalBannerCenter.swift:4-6` 的注释直接指导了后来的开发者应该在什么场景调用它（"background failures"），虽然实际执行范围还没跟上这条自己写的规范（见一.3），但"把使用规范写进被使用的文件本身"这个做法本身值得推广到其它 App 甚至 1Life。
4. **清空数据类操作的确认强度与 1Life 的最高风险档位对齐**：`Views/Settings/SettingsView.swift:70,79` 的清空所有数据走"继续→清空所有数据"两段式确认，与 [00§12](../../1Life/docs/structure/00_总览与跨Tab模式索引.md) 记录的 1Life 三级确认（目前全 App 风险处理最高档）是同一量级的谨慎程度，没有出现 1Life 自己在 `UserFoodListView` 批量删除上"零确认"的反直觉情况（本次核查范围内的 10 处 `role: .destructive` 命中都配有确认交互）。

---

## 四、未深挖范围

- `Views/Today/TodayView.swift`、`Views/Plan/PlanListView.swift`、`Views/Notes/NotesListView.swift`、`Views/Settings/SettingsView.swift` 只读了片段（涉及本次核查主题的部分），没有逐行通读整个文件。
- `Services/AI/LocalAIIntentParser.swift`（`AIChatView.swift:417,458` 调用 `LocalAIIntentParser.parseTask`）的具体规则判断逻辑没有细读，只确认了调用存在；1Cash 也有一个同名文件，两者是否共享同一套设计、是否值得和 1Life"本地规则文案引擎"模式（[00§9](../../1Life/docs/structure/00_总览与跨Tab模式索引.md)）做三方对比，没有展开。
- `Views/Onboarding/OnboardingView.swift` 完全没有读，无法判断 Onboarding 阶段是否也存在裸跳转或深链接相关的模式。
- `SettingsView`/`NotesListView`/`TodayView`/`PlanListView` 四个零 `GlobalBannerCenter` 覆盖的 Tab 具体用什么机制做后台失败反馈（`.alert`？内嵌文字？完全没有反馈？），发现 3 里只确认了"没有调用 GlobalBannerCenter"，没有确认替代机制是什么。
- 双语文案（英文大写标题等）没有做全项目核查，`DaySelectorView`（`ContentView.swift:137`）里出现了 `"TODAY"`/`"ARCHIVE"` 这类英文大写文案，和 1Cash 的 `MonthSelectorView` 几乎同一处模式——但这属于视觉/文案维度，如果 `1LIFE_UI_VISUAL_CONSISTENCY_REVIEW.md` 还没记录，应该补在那份文档而不是本文档。
- 没有做深色/浅色模式下的实际渲染验证，也没有运行 Xcode/模拟器。

---

## 五、优先级修复列表

1. **[P1]** `PlanItemService` 未覆盖 `Notes` 实体（发现 2）——`NotesListView`/`NoteEditorView` 直连 `modelContext`，建议补一个 `NoteService`（哪怕只是薄封装 insert/delete/save），让"数据写入统一走 Service 层"这条规则在 1Day 内部贯彻到底，而不是只覆盖 Task 一个实体。
2. **[P2]** 确认 `TodayView`/`PlanListView`/`NotesListView`/`SettingsView` 四个 Tab 的后台失败反馈机制（未深挖范围第 4 条）——如果这几个 Tab 确实没有对应 `GlobalBannerCenter` 覆盖的场景（比如都是同步操作、不存在"后台失败"这种情况），发现 3 就不构成问题；如果存在但用了别的机制，应该统一收口到 `GlobalBannerCenter`，因为源码注释已经明确要求这样做。
3. **[P3]** `AIChatView.swift` 里两处裸跳转（发现 1）补上语境——比如跳转到设置时告诉 Settings 应该展开 AI 配置分区，而不是让用户自己找。
4. **[P4，不紧急]** 确认 `LocalAIIntentParser`（1Day）和同名文件（1Cash）是否本来就是同一套设计的两次实现，如果是，值得评估要不要提炼成家族共享逻辑而不是各自维护一份。
