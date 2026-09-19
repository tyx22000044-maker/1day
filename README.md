# 1Day

1Day 是 1App Family 中负责「今天要做什么」的本地优先 SwiftUI App：用任务、提醒、笔记和可选的 AI 草稿，把日常计划收进一个安静的工作台。

## 当前状态

当前仓库是可运行的 V1.0 MVP，包含 Today、Plan、AI、Notes、Settings 五个 Tab，以及 Onboarding、SwiftData 本地存储、任务提醒、笔记搜索、JSON 备份恢复、个人资料和多服务商 AI 配置。AI 生成的任务必须经过用户确认才会写入数据层。

数据可靠性上是「出问题就说」而不是「静默兜底」：存储不可写时 App 仍可用内存容器继续运行，但顶部会常驻一条风险说明并给出导出出口；备份导入先整体校验再落盘，失败回滚到原数据；删除任务和笔记都有二次确认和撤销窗口。

V1.0 的功能边界以 [`docs/MVP_SCOPE.md`](docs/MVP_SCOPE.md) 为准；其中列出的收藏集、标签、子任务、日历、重复任务、iCloud 同步和账号系统不属于当前版本。

## Swiss Ledger 视觉契约

1Day 使用 1App Family 共用的 Swiss Ledger 视觉系统，token 位于 `1Day/Extensions.swift`：

- 冷纸张背景 `#FAFAF7`、主墨色 `#0B0B0A`，深色模式使用对应的反转纸张/墨色。
- 正文和标题优先使用随 App 打包的 Archivo，通过 `FamilyTypography` 统一字号和字重；SF Symbols 保持系统图标字体。
- 面板、输入框、状态徽标使用 `FamilyUI` 的 0–2pt 几何圆角；优先矩形、细边框和网格分隔，不使用阴影或胶囊式标签。
- `#C4321F` 是主要印刷红；成功、警告和危险色只用于小范围语义提示，不替代页面中性层级。
- 页面、面板、按钮、输入和状态组件应复用 `FamilyUI`、`FamilyTypography`、`SystemPanel` 和 `SystemStatusBadge`，不要在页面中新增独立颜色或尺寸 token。

## 技术栈

- iOS 17+ / SwiftUI / SwiftData
- Keychain Services / UserNotifications / Speech
- 多 AI 服务商 HTTP Client：ChatGPT、Claude、Kimi、通义千问、豆包、腾讯混元

## 目录结构

- `1Day/`：App 主源码、资源和字体
- `1Day/Models/`：SwiftData 模型、schema 与迁移计划、共享枚举与文案表
- `1Day/Services/`：业务服务、AI、图片、通知、删除协调器和备份
- `1Day/Components/`：Swiss Ledger 组件（面板、按钮、空状态、错误 Banner）
- `1Day/Views/`：Today、Plan、AIChat、Notes、Onboarding、Settings 等页面
- `1DayTests/`：Swift Testing 回归用例
- `docs/MVP_SCOPE.md`：当前版本范围与后续规划
- `docs/ARCHITECTURE.md`：容器、通知调度、AI 流等设计决策
- `docs/DATA_MODEL.md`：数据模型与备份格式定义
- `docs/UX_FLOW.md`：用户流程
- `docs/AI_BEHAVIOR_SPEC.md`：AI 意图与草稿确认契约
- `PRD.md`：产品需求文档

## 运行方式

1. 用 Xcode 打开 `1Day.xcodeproj`。
2. 选择 `1Day` scheme 和 iOS 17+ 真机或模拟器。
3. 点击 Run。

命令行构建（不需要代码签名）：

```bash
xcodebuild -project 1Day.xcodeproj -scheme 1Day \
  -destination 'generic/platform=iOS Simulator' \
  -configuration Debug CODE_SIGNING_ALLOWED=NO build
```

命令行跑测试（替换成一台已启动模拟器的 UDID）：

```bash
xcodebuild -project 1Day.xcodeproj -scheme 1Day \
  -destination 'platform=iOS Simulator,id=<UDID>' \
  -derivedDataPath /tmp/qoder-1day-dd \
  CODE_SIGNING_ALLOWED=NO test
```

## 重要限制

- 数据默认保存在本机 SwiftData；当前不接入 iCloud 同步、账号系统或跨 App 数据互通。
- AI API Key 存在 iOS Keychain，不写入 JSON 备份；AI 输出可能遗漏或误解输入，保存前应自行核对。
- 本地通知依赖用户授权；系统拒绝通知权限时，任务和笔记仍可正常使用。通知正文会出现在锁屏和通知中心，不要写入只在 App 内查看的敏感内容。
- 主页面、标签、日期和提醒文案已跟随界面语言；设置详情页、静态说明与部分通知文案仍以中文为主，完整本地化不属于本次 MVP 收口范围。

## 文档索引

- [PRD](PRD.md)
- [MVP 范围](docs/MVP_SCOPE.md)
- [架构说明](docs/ARCHITECTURE.md)
- [数据模型](docs/DATA_MODEL.md)
- [用户流程](docs/UX_FLOW.md)
- [AI 行为规范](docs/AI_BEHAVIOR_SPEC.md)
- [文件复用清单](docs/REUSE_PLAN.md)
