# 1Day 对齐 1Life 视觉设计系统的一致性审查（2026-07-14）

> 本轮是 1Day 的第二轮家族对齐核验，覆盖用户提供的 200 点清单：全局共享元素、Onboarding、Today、任务/计划列表、AI、笔记/次要 Tab、设置。对照材料为 `1Life/docs/structure/00-06`、`APP_FAMILY_CONTEXT.md`，以及 1Day 本文档上一版的已知结论。
>
> 本文仍以视觉设计系统为主：颜色、控件、圆角、间距、字重、面板结构和 AI Chat Lockstep。发现的明显交互问题单独列在第九节，不作为本轮主要修复范围。
>
> 本轮只做源码与文档核验；未运行 `xcodebuild`，未运行模拟器。

> **修复状态（同日）**：已完成本轮可执行修复：AppSettingsRow、FamilyAddButton、Today 趋势默认呈现与任务行、计划完成色、Settings 外观选择器与资料 Sheet、Splash 骨架、PrimaryButton/空状态 CTA，以及 AI 图片输入、重试入口、输入控件/气泡/错误反馈样式。未运行 `xcodebuild` 或模拟器，仅完成源码静态核验。

## 0. 结论摘要

1Day 的 FamilyUI、AppSpacing、AppSwitchStyle 和头像组件已经基本对齐，且 `accentDeep` 已真实定义，项目没有 `AppCornerRadius` 的死引用问题。当前最影响家族观感和使用路径的不是底层 token，而是以下几项：

1. **Today 周趋势已改为默认展开**：首屏现在有常驻柱状趋势图；是否进一步替换为更小圆环，留待渲染核验。
2. **AI Chat 已完成输入锁步**：输入框、麦克风、相机、图片附件、发送按钮、气泡宽度/圆角、错误反馈和重试入口已对齐。
3. **Onboarding 的 AI 配置步骤已可实际使用**：已提供服务商、模型和 API Key 的可选配置，仍支持跳过。
4. **`AppSettingsRow` 已回到家族规格**：图标盒使用固定中性底和描边，标题/值字重、间距、chevron 已统一。
5. **三个“+”入口已统一为 `FamilyAddButton`**：Today、计划、笔记现在共用 34×34 黑色圆角新增按钮。
6. **PrimaryButton 与空状态 CTA 已回归家族 accent**：启用态使用 `FamilyUI.accent`、黑色 18% 描边和家族字号/内边距。

### 200 点覆盖状态

| 清单范围 | 覆盖状态 | 本轮结论 |
|---|---|---|
| 1-30 全局共享元素 | 已核验 | token、SettingsRow、加号入口和 CTA 已对齐；保留少量明确语境下的裸色/裸圆角 |
| 31-55 Onboarding | 已核验 | Splash 与 AI 可选配置已补齐；步骤面板密度仍保留 1Day 领域差异 |
| 56-80 Today | 已核验 | 板块数量适中；周趋势默认展开，任务行图标盒已补齐；quickInputPanel 保留 |
| 81-130 任务/计划列表 | 已核验 | 分组、详情、创建/编辑、搜索/筛选现状均已检查；重复任务、标签属于 MVP 外计划项 |
| 131-155 AI | 已核验 | Header/进度/芯片、图片输入、气泡、错误反馈和重试入口已锁步 |
| 156-185 次要 Tab | 已核验 | 笔记列表、空状态、无结果、编辑页已检查；1Day 没有独立统计 Tab，图表/周期选择不适用 |
| 186-200 设置 | 已核验 | 资料、AI、备份恢复、清空数据、外观、关于均已检查；资料为 Sheet、外观为分段选择器 |

## 一、全局共享元素（1-30）

### 1.1 FamilyUI、AppSpacing、圆角基础

- `1Day/1Day/Extensions.swift:116-170` 的 `AppSpacing` 和 `FamilyUI` 与 1Life 对应定义一致。
- `FamilyUI.accentDeep` 已真实定义为 `#173a98`，不是只有引用没有定义。
- 1Day 没有 `AppCornerRadius` 枚举，全文也没有引用；所有家族级圆角走 `FamilyUI.panelCornerRadius`、`controlCornerRadius`、`badgeCornerRadius`。
- 全量裸数字圆角扫描结果：`8` 用于图标盒、`3` 用于趋势柱、`7` 用于开关 knob、`18` 用于 Splash 图标裁剪。前四类分别有 1Life 对应或明确的组件语境，不属于死引用；AI 气泡已使用 `FamilyUI.panelCornerRadius`。
- Splash 的图标裁剪圆角已改为 `18`，并补齐 1Life 的中性外框、描边、阴影和副标题骨架。

### 1.2 开关样式：本轮跳过

`1Day/1Day/Extensions.swift:56-81` 的 `AppSwitchStyle` 与 1Life 逐行一致：轨道 `50×30`、`FamilyUI.controlCornerRadius`、knob `20×20`、padding 5、关闭态 knob 使用 `Color.secondary.opacity(0.55)`。所有 `Toggle` 由 `ContentView:49` 的 `.appSwitchStyle()` 覆盖。

这是目前核对过的家族 App 中唯一可以直接判定“无需修”的开关实现，本轮不碰。

### 1.3 AppSettingsRow：已恢复家族中性盒

对照 `1Life/1Life/Components/AppSettingsRow.swift`，本轮已完成以下修复：

- 图标盒已改为固定 `FamilyUI.panelMutedBackground` + `FamilyUI.panelBorder`。
- 标题已改为 `.semibold`，标题/副标题间距已恢复为 `4`。
- 强调值已改为 `.semibold`。
- chevron 已改为 `.secondary`；Settings 个人资料卡的独立 chevron 也同步改为 `.secondary`。

这是共享组件本体偏差，本轮已收口；彩色分类底色没有保留。

### 1.4 CTA 颜色：已恢复家族 accent

- `PrimaryButton.swift` 启用态已改为 `FamilyUI.accent`。
- `AppEmptyStateView.swift` CTA 已改为 `FamilyUI.accent`。

两处现在与 1Life 对齐：字体为 `.subheadline.weight(.black)`，垂直 padding 为 `14`，启用态使用 accent，并补齐 18% 黑色描边。

### 1.5 “+”入口：已统一为 FamilyAddButton

本轮在 `Components/SystemPanel.swift` 增加了家族 `FamilyAddButton`/`FamilyAddButtonLabel`，并替换以下三处 toolbar 裸图标：

- `Views/Today/TodayView.swift:109-115`
- `Views/Plan/PlanListView.swift:130-137`
- `Views/Notes/NotesListView.swift:78-85`

三处现在共用 34×34 黑色圆角新增按钮，视觉规格与 1Pet 组件一致；仍保留在 toolbar placement 中，避免改变现有导航结构。

### 1.6 裸色与状态色

- `PlanListView.swift` 完成态已统一为 `FamilyUI.success`。
- `SettingsView.swift` 个人资料卡 chevron 已统一为 `.secondary`，资料入口已改为 Sheet。
- `TodayView.swift:182`、`:419` 的系统灰色用于禁用态/未完成态，属于中性状态色，可以保留；不应把它们与语义成功色混用。
- 其余业务层颜色主要走 `FamilyUI.accent/success/warning/danger`。裸色使用率仍处于家族低档位。

## 二、Onboarding 逐屏（31-55）

### 2.1 Splash 与 App 图标

`OneDayApp.swift:20-27` 正确使用 `SplashAppIcon`，App Icon 资产也齐全；Splash 视觉骨架现已跟随 1Life：

- 已补齐 `132×132` 中性外框、描边、阴影和副标题。
- 图标裁剪圆角已改为 `18`。
- 标题已改为 `.black` 并使用 `monospacedDigit()`。

这是品牌入口的 P2 视觉差异，外框、间距、字重、数字处理和领域副标题现已收口。

### 2.2 进度条、Header、BottomBar

- `OnboardingTopBar:357-394` 有返回、STEP 徽标、跳过和进度条，结构清楚。
- `OnboardingProgressBar:397-413` 使用 `FamilyUI.panelMutedBackground`/`FamilyUI.accent`，高度 4，符合家族克制方向。
- `OnboardingStepHeader` 保留居中布局以适应引导流程，字重已提升为 `.black`；与家族页面标题层级保持一致，文案布局保留 1Day 的引导语境。
- 底部 `PrimaryButton` 已使用家族 accent；NextButton 没有独立 disabled 态，因为当前所有步骤都允许继续/跳过。AI 配置保存成功与否不阻断 Onboarding。

### 2.3 各步骤检查

| 步骤 | 源码核验 | 结论 |
|---|---|---|
| Welcome | `OnboardingView.swift:89-114` | 已使用 `SplashAppIcon` 外框、标题和 4 条功能行；保留 1Day 领域欢迎文案 |
| Profile | `:110-149` | 使用家族 `UserAvatarView`，头像规格正确；昵称输入框已补中性底/描边盒 |
| Preference | `:151-174` | 语言/外观两个 segmented picker 已收纳进 `SystemPanel`，保持家族面板密度 |
| AI Config | `OnboardingView.swift` | 已提供服务商 Picker、模型 ID、SecureField 和可选 Keychain 保存；继续按钮仍允许跳过 |
| Reminder | `:218-263` | DatePicker、快捷时间按钮、通知按钮可用；通知按钮已改为家族中性底/描边控件 |
| Ready | `:265-283` | 有完成图标和汇总行；汇总行使用淡化底并带家族描边 |

### 2.4 头像与选项行

`UserAvatarView.swift` 的四级 fallback 与 1Life 一致：图片 → SF Symbol → 首字母渐变 → 占位图；`accentDeep` 也被正确用于渐变。这里不需要修。

`OnboardingFeatureRow` 已补轻量描边和中性面板容器；它仍是 Onboarding 私有行，不与 `AppSettingsRow` 混用。

## 三、Today 首页逐板块（56-80）

### 3.1 总体密度

`Views/Today/TodayView.swift` 共 480 行，首屏结构为：`DaySelectorView`、`heroCard`、`quickInputPanel`、`overdueSection`、`todaySection`、`completedSection`，内容量适中。`quickInputPanel` 是 1Day 特有的快速建任务设计，符合领域，不是视觉偏差，本轮保留。

### 3.2 DaySelectorView

`ContentView.swift:116-184` 的日期选择器使用 40×40 中性底、1pt 描边、10pt 控件圆角，前后箭头和日期标题层级清晰。禁用的右箭头使用系统灰，属于合理的 disabled 语义色。

### 3.3 heroCard 与周趋势：默认呈现已修复

- `TodayView.swift:138-189` 的 hero 使用 `SystemPanel`，今日完成数字 34pt，周完成数字 accent 色，层级明确。
- `:14` 的 `isProgressExpanded` 已改为 `true`，首屏默认显示 `weekTrendChart`。
- `:191-219` 的柱状图最高 56pt，仍可由用户收起；当前不再出现首屏只有数字、趋势完全隐藏的问题。

本轮采用风险最小的“默认展开”方案；柱状图仍保留手动收起能力，避免首屏信息丢失。

### 3.4 三类任务面板与 TaskRow

- `overdueSection`、`todaySection`、`completedSection` 均使用 `SystemPanel` 和 `SystemPanelDivider`，面板语言对齐。
- `TaskRow` 已使用 `FamilyListIconBox`，完成/未完成图标、颜色与列表图标盒统一。
- 旗标走 `item.priority.color`，优先级语义色已集中在 `SharedTypes.swift:75-81`。
- 过期徽标使用 `SystemStatusBadge(.danger)`，与家族状态徽标一致。
- `ScheduleLaterToast:451-479` 使用中性面板、描边、圆角和阴影，样式合适。

## 四、任务/计划列表与笔记（81-130、156-185）

### 4.1 计划列表

`PlanListView.swift:57-152` 的分组顺序为未安排、已过期、今天、明天、本周、更晚，均包在 `SystemPanel` 中，组头和计数清晰。`PlanItemRow:154-200` 展示完成态、标题、备注、日期、提醒和优先级，信息密度适中。

已发现的视觉问题：

- `PlanListView.swift:161` 完成态已改为 `FamilyUI.success`，与 Today 对齐。
- Today 与 Plan 仍有两份任务行实现；完成色已统一，但图标盒、间距、字段展示和过期信息不完全一致。若后续继续扩展任务行，应抽出共享任务行规格，避免第三套视觉分叉。
- 计划列表工具栏的“+”已统一为 `FamilyAddButton`，见一.5。

重复任务、标签/分类、按标签筛选、日期范围筛选目前没有对应 UI；`MVP_SCOPE.md` 已将重复任务列为 V1.2、标签/筛选列为后续项，因此本轮记为“范围外/不适用”，不作为视觉 bug。

### 4.2 创建、编辑、周期设置、批量操作

- `TaskEditorSheet:282-384` 是 `Form` + 底部 `PrimaryButton` 显式保存。
- `TaskDetailView:386-513` 同样使用 `Form`，字段可以编辑，但标题/备注/日期/提醒通过 `onChange` 即时写入，页面没有显式保存按钮。
- 这两个入口的字段视觉骨架相近，但保存语义不对称：新建是“编辑后点保存”，详情是“改动立即落盘”。这是交互一致性问题，不是本轮主要视觉修复。
- 没有批量操作，也没有周期任务编辑界面；在当前 MVP 范围内为未实现能力。

### 4.3 笔记列表与编辑

`NotesListView.swift:21-100` 做到了：

- 有 `SystemPanel` 列表容器和分隔线；
- 空列表与搜索无结果使用两种不同的 `AppEmptyStateView`；
- 使用系统 `.searchable`，搜索标题和正文；
- 工具栏新增入口与其它两个 Tab 一致，均使用 `FamilyAddButton`。

`NoteEditorView.swift:12-49` 是沉浸式标题/正文编辑器，自动保存并显示短暂“已保存”状态；这是笔记领域的合理差异。它不使用 `SystemPanel`，但没有发现会破坏家族 Settings/AI/Onboarding 共享表面的明显问题。

## 五、AI Tab（131-155）

AI Chat 是家族明确要求锁步的共享表面，本轮以 `1Life/docs/structure/04_Tab3_AIChat.md` 和 1Life 实际组件为基准。

### 5.1 已对齐部分

- `AIChatView.swift:38-155` 的总体结构为 Header → 消息滚动区 → 请求进度 → 芯片 → 输入栏，与 1Life 的四段式骨架相近。
- `AIConfigurationHeader` 的状态图标盒、服务商/模型 Menu、状态徽标和设置入口与 1Life 基本一致。
- `AIRequestProgressView` 的面板、进度转圈、阶段文字和 `SystemStatusBadge` 结构一致；图片请求现在有独立的“分析图片/逐张提取线索”状态文案。
- 快捷芯片的胶囊、边框和“未配置 AI 时部分芯片仍可用”的策略与 1Life 相近。
- 清空聊天有 destructive confirmation；AI 任务草稿可编辑、可取消、确认后才写入，符合 1Day 的 AI 行为边界。

### 5.2 输入栏和图片能力：已完成锁步

1Life 的输入栏是 `[相机] [麦克风] [输入框] [发送]`。1Day 现已补齐并统一这四个元素的 38pt 尺寸、中性底、描边和家族圆角：

- 已补齐相机/相册入口、最多 6 张图片预览与移除、视觉模型能力判断，并写入相机/相册权限说明。
- 麦克风已改为 38×38 中性/危险态控件，去掉裸圆形图标。
- 输入框已改为 `FamilyUI.panelMutedBackground` + `panelBorder` 输入盒。
- 发送按钮已改为 38×38、`FamilyUI.controlCornerRadius` 的 accent 圆角方块。

因此 AI 输入栏、图片能力和请求状态已收口。

### 5.3 锁步偏差：消息气泡与反馈（样式已修复）

- `AIChatComponents.swift:201-230` 的普通气泡已改用 `FamilyUI.panelCornerRadius`。
- 普通气泡已补 `maxWidth: 280`，长文本不会无约束占满横向空间。
- 1Day assistant 消息额外显示 ProviderBadge，这是领域可接受的附加信息，但要保留与气泡主体的间距和最大宽度约束。
- 请求失败已改为进入 `GlobalBannerCenter`，不再伪装成 assistant 消息；语音错误也已统一进入全局 Banner，不再以内嵌红字显示。
- 请求失败会保留原始文字、图片和历史上下文，并在输入栏显示“重试”入口。

### 5.4 空状态与确认卡

1Day `AIEmptyState` 保留 3 个领域功能卡片，已使用 `SystemPanel` 中性面板层级；与 1Life 的卡片数量不同属于领域文案差异。

`TaskDraftConfirmationView` 使用原生 `Form`，有“任务草稿”标题、标题/备注/日期/优先级字段、取消和创建按钮，满足“先草稿、可编辑、确认后落盘”的 1Day 产品原则。它不是 1Life 的餐食确认卡，字段差异属于领域定制，不要求复制餐食组件。

## 六、设置 Tab（186-200）

### 6.1 主设置页与资料

`SettingsView.swift:25-45` 的主结构为个人资料、基础设置、反馈、AI 配置、数据管理、显示、关于，全部使用 `SystemPanel`，整体骨架对齐。

- 主资料卡使用 `UserAvatarView`，符合家族头像要求。
- 主资料卡 chevron 在 `SettingsView.swift:126-128` 使用 `.secondary`，已与 AppSettingsRow 规则一致。
- 资料编辑入口已由 `NavigationLink` 改为 Sheet，保持与家族资料编辑入口一致；Sheet 内继续复用 1Day 的资料字段和头像选择器。
- ProfileSettingsView 的头像选择网格与 Onboarding 复用同一套风格，字段有中性底和描边，数值基本对齐。

### 6.2 AI 配置、数据管理与危险操作

- `AIConfigurationSettingsView:748-1004` 有服务商、模型 ID、API Key、保存配置、测试连接、能力说明，层级完整；Key 存储提示清楚。
- 数据管理有导出、分享、导入和清空；导入前有替换数据警告，清空有两级确认，且明确保留个人资料和 AI 配置，风险处理比许多兄弟 App 更稳妥。
- AI Chat 清空历史入口在 AI Tab toolbar，不在设置页重复提供；功能可达，但与 1Life 设置页的 AI 历史管理位置不同，低优先级记录。

### 6.3 外观选择器：已改为分段选择器

`SettingsView.swift:148-180` 的外观已改为直接可见的 `Picker(.segmented)`，并保留当前模式摘要行；语言仍使用 Menu，避免扩大本轮变更范围。

### 6.4 关于与静态信息

站内信、用户手册、隐私说明、反馈、版本号均使用 `AppSettingsRow`，行结构和分隔线清晰；修复 AppSettingsRow 后可自动获得家族盒样式。未发现独立的视觉系统分叉。

## 七、问题清单与优先级

| 状态 | 优先级 | 问题 | 位置 | 处理建议 |
|---|---|---|---|---|
| 已修复 | P1 | Today 周趋势默认隐藏 | `Views/Today/TodayView.swift:14,170-186` | 已改为默认展开 |
| 已修复 | P1/P2 | AI Chat 输入栏缺相机/图片附件、控件形态不同 | `Views/AIChat/AIChatView.swift` | 已补齐图片入口、预览、请求路径与权限说明 |
| 已修复 | P1 | Onboarding AI Config 只有说明，没有实际配置控件 | `Views/Onboarding/OnboardingView.swift` | 已加入服务商、模型、API Key 可选配置，继续仍可跳过 |
| 已修复 | P1/P2 | AppSettingsRow 图标盒、字重、间距、chevron 偏离 | `Components/AppSettingsRow.swift:14-51` | 已恢复中性底、描边和语义色 |
| 已修复 | P2 | 三个“+”入口是裸 toolbar 图标 | Today/Plan/Notes 三处 toolbar | 已统一为 `FamilyAddButton` |
| 已修复 | P2 | AI 气泡圆角、宽度和错误反馈未锁步 | `Views/AIChat/AIChatComponents.swift`、`AIChatView.swift` | 已统一圆角、最大宽度、全局 Banner 和重试入口 |
| 已修复 | P2 | Settings 外观是 Menu，不是 segmented Picker | `Views/Settings/SettingsView.swift:148-180` | 已改为可见分段选择器 |
| 已修复 | P2 | Profile 编辑页使用 NavigationLink，不是家族 Profile Sheet | `Views/Settings/SettingsView.swift` | 已改为 Sheet 入口 |
| 已修复 | P2 | Splash 缺少 1Life 的外框/描边/副标题骨架 | `Views/Splash/SplashView.swift` | 已补齐家族 Splash 骨架 |
| 已修复 | P3 | PlanItemRow 完成态使用裸 `.green` | `Views/Plan/PlanListView.swift:160-162` | 已改为 `FamilyUI.success` |
| 已修复 | P3 | Today TaskRow 没有图标盒 | `Views/Today/TodayView.swift`、`Components/SystemPanel.swift` | 已加入 `FamilyListIconBox` |
| 已修复 | — | PrimaryButton/空状态 CTA 使用黑色 | `Components/PrimaryButton.swift`、`AppEmptyStateView.swift` | 已统一为 `FamilyUI.accent` |

## 八、做得好、应继续保留的部分

1. `FamilyUI`、`AppSpacing` 和 `accentDeep` 定义干净，没有重复 token 系统。
2. `AppSwitchStyle` 与 1Life 完全一致，本轮不碰。
3. `UserAvatarView` 已按家族四级 fallback 实现，且 Onboarding/Settings 都复用同一组件。
4. Today 首页 6 个板块量级适中，`quickInputPanel` 是符合 1Day 领域的正向设计。
5. 空列表与搜索无结果已经区分，Notes 的搜索路径清楚。
6. AI 任务创建遵循“输入 → 草稿 → 用户确认 → 写入 → 限时撤销”，没有绕过确认直接写库。
7. 设置页导入和清空操作有明确警告/确认，备份文件不包含 API Key 的产品边界也有文案提示。

## 九、顺手记录的明显交互问题（非本轮主要修复范围）

1. **Onboarding 跳过仍可从任意步骤直接结束**：这是保留的产品便利行为；AI 配置步骤现在已经提供真实可选配置控件。
2. **新建/编辑任务保存语义不一致**：新建任务必须点击底部“保存”，详情页字段改动即时落盘，没有“保存/取消”边界。建议产品确定统一的显式保存或即时保存模式。
3. **AI 请求失败已补齐重试入口**：错误保留原始输入、图片和历史上下文，输入栏提供“重试”。
4. **AI 图片能力已接通**：主输入栏按 1Life 接入相机/相册、预览、视觉模型判断和图片请求链路。

## 十、下一步建议

本轮已按确认范围完成全部可执行修复：共享表面、Today、设置、Splash、Onboarding AI 配置和 AI 图片/重试链路均已收口。后续只需在允许构建时进行 Xcode 编译和设备渲染核验。

## 十一、修复状态小结逐条复核（2026-07-14）

本节按文档顶部“修复状态”小结逐条重新核对当前源码。以下结论来自源码静态检查，未运行 `xcodebuild`、测试或模拟器。

### 11.1 AppSettingsRow：属实

- 图标盒使用固定中性底 `FamilyUI.panelMutedBackground`、`FamilyUI.panelBorder` 1pt 描边，并使用 `FamilyUI.iconBoxSize`：`1Day/Components/AppSettingsRow.swift:14-20`。
- 标题字重为 `.semibold`、标题/副标题间距为 `4`：`1Day/Components/AppSettingsRow.swift:27-35`。
- 强调值使用 `.semibold`，chevron 使用 `.secondary`：`1Day/Components/AppSettingsRow.swift:40-50`。

结论：文档所写“固定中性底+描边、字重/间距/chevron 已恢复”与当前实现一致。

### 11.2 三个“+”入口：属实

- 共享组件确实定义为 `FamilyAddButton`，内部使用 `FamilyAddButtonLabel`，规格为 34×34、家族圆角：`1Day/Components/SystemPanel.swift:85-105`。
- Today toolbar 使用 `FamilyAddButton`：`1Day/Views/Today/TodayView.swift:108-113`。
- Plan toolbar 使用 `FamilyAddButton`：`1Day/Views/Plan/PlanListView.swift:130-135`。
- Notes toolbar 使用 `FamilyAddButton`：`1Day/Views/Notes/NotesListView.swift:78-83`。

结论：三个入口确实已统一到同一个 `FamilyAddButton` 实现；组件本身按 1Pet 规格保留黑色新增按钮。

### 11.3 Today 周趋势默认展开：属实

- 状态初始值为 `true`：`1Day/Views/Today/TodayView.swift:11-15`，其中 `isProgressExpanded = true`。
- 只有在用户点击收起/展开按钮后才切换状态：`1Day/Views/Today/TodayView.swift:168-180`。
- 趋势图由 `if isProgressExpanded` 控制展示：`1Day/Views/Today/TodayView.swift:182-184`。

结论：Today 首次进入时周趋势图默认可见，文档小结属实；用户仍可手动收起。

### 11.4 PrimaryButton / 空状态 CTA 回到 accent：属实

- `PrimaryButton` 启用态使用 `FamilyUI.accent`，禁用态使用系统灰，并保留家族圆角和黑色 18% 描边：`1Day/Components/PrimaryButton.swift:13-26`。
- `AppEmptyStateView` CTA 使用 `FamilyUI.accent`、白字、家族圆角和黑色 18% 描边：`1Day/Components/AppEmptyStateView.swift:38-53`。

结论：两类 CTA 的启用态确实已从黑色改为 `FamilyUI.accent`；文档小结属实。

### 11.5 AI Chat 输入区、气泡与错误反馈锁步：属实

- 输入区已经是 `[相机] [麦克风] [输入框] [发送]`：相机入口和视觉模型判断在 `1Day/Views/AIChat/AIChatView.swift:262-288`，麦克风在 `:290-306`，输入框在 `:308-326`，发送按钮在 `:328-337`。
- 图片附件支持相册/相机选择，并提供最多 6 张图片预览与移除：`1Day/Views/AIChat/AIChatView.swift:156-181`、`:349-385`。
- 气泡最大宽度为 280：`1Day/Views/AIChat/AIChatComponents.swift:173-189`；主体气泡使用 `FamilyUI.panelCornerRadius`，图片附件使用 `FamilyUI.badgeCornerRadius`：`1Day/Views/AIChat/AIChatComponents.swift:210-238`。
- 语音错误进入 `GlobalBannerCenter`：`1Day/Views/AIChat/AIChatView.swift:197-200`。
- AI 请求失败进入全局错误 Banner，并保存失败请求的文字、图片和历史：`1Day/Views/AIChat/AIChatView.swift:463-470`；输入区提供“重试”，重试会复用保存的请求上下文：`1Day/Views/AIChat/AIChatView.swift:241-255`、`:475-503`。

结论：文档所写 AI 输入图标、气泡尺寸/圆角、错误反馈和重试入口已锁步，当前源码证据支持该结论。

### 11.6 Today 与 Plan 任务行：仍是两套独立实现，未完全收口

- Today 使用私有 `TaskRow`，并已使用 `FamilyListIconBox`；字段为标题、备注、优先级旗标和过期徽标，间距/内边距也独立定义：`1Day/Views/Today/TodayView.swift:410-447`。
- Plan 使用另一份私有 `PlanItemRow`，仍直接使用裸 `Image` 完成图标；字段额外包含日期和提醒图标，没有 Today 的过期徽标，间距和垂直内边距也不同：`1Day/Views/Plan/PlanListView.swift:152-197`。
- 完成态颜色已部分收口：Today 使用 `FamilyUI.success`，Plan 也使用 `FamilyUI.success`：`1Day/Views/Today/TodayView.swift:416-419`、`1Day/Views/Plan/PlanListView.swift:157-160`。

结论：原文所述差异在本轮复核时成立；随后已在本轮修复中抽取共享 `FamilyTaskRow`，Today 与 Plan 现在共用图标盒、完成色、字段排版、间距和过期徽标，仅由 Plan 打开日期/提醒字段。

## 十二、1Day 全面 UI 对齐修复记录（2026-07-15）

本轮按 1Life 的主导航、AI Chat、设置页和 FamilyUI Sheet 结构完成代码修复。以下为源码静态核验结果；未运行 `xcodebuild`、测试或模拟器。

### 12.1 主 Tab 标题栏：已完成

- Today、Plan、Notes、AI、Settings 均使用 `.navigationBarTitleDisplayMode(.inline)`，与 1Life 主页面标题栏保持同一导航层级和显示模式：`1Day/Views/Today/TodayView.swift:107-108`、`1Day/Views/Plan/PlanListView.swift:132-133`、`1Day/Views/Notes/NotesListView.swift:73-74`、`1Day/Views/AIChat/AIChatView.swift:119-120`、`1Day/Views/Settings/SettingsView.swift:46-47`。
- 设置页仍通过 `localized("设置", "Settings")` 根据应用语言切换标题；中文环境不会出现中英文同时显示。

### 12.2 AI Chat 锁步样式：已完成

- AI 页面现在按“配置头 → 聊天区 → 输入区”组织，聊天区使用 16pt 内容内边距、FamilyUI 页面背景、交互式收起键盘和点击收起焦点：`1Day/Views/AIChat/AIChatView.swift:88-107`。
- 输入区统一包含请求进度、图片预览、快捷芯片和输入栏，快捷芯片不再只在空会话显示：`1Day/Views/AIChat/AIChatView.swift:195-218`。
- 输入栏保持 1Life 的相机、麦克风、文本输入、发送/停止四个入口，并保留 FamilyUI 控件圆角、描边和 accent 发送按钮：`1Day/Views/AIChat/AIChatView.swift:241-347`。
- 消息气泡保留左右对齐、AI 提供商头像、280pt 最大宽度、FamilyUI panel 圆角和图片附件气泡：`1Day/Views/AIChat/AIChatComponents.swift:167-238`。
- 请求失败保留失败文本、图片和历史上下文，输入区显示“重试”入口；语音错误仍通过全局 Banner 反馈：`1Day/Views/AIChat/AIChatView.swift:243-255`、`:463-503`、`:197-200`。

### 12.3 设置页信息架构：已完成

- 分组顺序已调整为“个人资料 → AI 配置 → 基础设置 → 反馈 → 数据管理 → 显示 → 关于”，与 1Life 的信息架构方向一致；各组继续使用 `SystemPanel` 和 `AppSpacing.sectionSpacing`：`1Day/Views/Settings/SettingsView.swift:27-43`。
- 主设置页及个人资料、提醒时间、AI 配置等二级页均使用 FamilyUI 页面背景和 inline 标题：`1Day/Views/Settings/SettingsView.swift:46-47`、`:681-737`、`:767-812`、`:832-849`。
- `AppSettingsRow` 已与 1Life 对齐为中性底色、固定描边、12pt 横向间距、4pt 垂直内边距和 `.secondary` chevron：`1Day/Components/AppSettingsRow.swift:13-56`。

### 12.4 Sheet 与新建任务布局：已完成

- 快速设定日期、创建任务、任务详情和 AI 任务草稿确认不再使用原生 `Form`；全部改为 `ScrollView`、`SystemPanel`、FamilyUI 文本框、分隔线、Toggle 和底部 PrimaryButton：`1Day/Views/Plan/PlanListView.swift:203-286`、`:283-426`、`:438-568`、`1Day/Views/AIChat/AIChatView.swift:606-695`。
- 任务标题、备注、日期、提醒和优先级现在按“任务/安排”面板分组，输入框和 TextEditor 使用 `FamilyUI.panelMutedBackground` + `FamilyUI.panelBorder`，Sheet 页面使用 inline 标题和交互式键盘收起。
- 笔记编辑页也已从裸 TextEditor 布局改为 FamilyUI 面板，并统一为 inline 标题和页面背景：`1Day/Views/Notes/NoteEditorView.swift:12-49`。

### 12.5 文案核验说明

- 中文界面中的设置、任务、提示、错误和操作文案已保持中文；`AI`、`API Key`、服务商名称、`SwiftData`、`Keychain` 等属于产品/技术专有名词，保留以避免改变实际含义。
- `TODAY` / `ARCHIVE` 保留是因为 1Life 的 DaySelector 同样采用该家族状态标记，不属于 1Day 单独的中英混用偏差。

### 12.6 任务行收口：已完成

- Today 与 Plan 的页面包装仍保留各自私有入口，但实际渲染已统一委托给 `FamilyTaskRow`；共享组件负责 FamilyListIconBox、完成色、标题/备注排版、优先级、过期徽标和 8pt 垂直内边距：`1Day/Components/SystemPanel.swift:129-190`。
- Today 使用默认字段，Plan 通过 `showsScheduleDetails: true` 增加日期和提醒字段：`1Day/Views/Today/TodayView.swift:411-417`、`1Day/Views/Plan/PlanListView.swift:156-162`。
