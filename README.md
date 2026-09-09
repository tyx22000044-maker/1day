# 1Day

1Day 是一款 SwiftUI 个人计划与笔记 App。它负责 1App Family 中“未来要做的事”和“正在思考的内容”：任务、日程、笔记、想法和复盘。

## 当前状态

项目处在 V1.0 MVP 骨架阶段。当前已具备 5 Tab 基础结构、SwiftData 模型、今日视图、计划列表、笔记列表、Onboarding、设置页和家族统一 AI 服务骨架。通知、完整任务编辑、AI 创建任务、JSON 备份恢复和本地化仍在 MVP 范围内继续推进。

## 技术栈

- iOS / SwiftUI
- SwiftData
- Keychain Services
- UserNotifications
- Speech
- 多 AI 服务商 HTTP Client：ChatGPT、Claude、Kimi、通义千问、豆包、腾讯混元

## 目录结构

- `1Day/1Day/`：App 主源码
- `1Day/1Day/Models/`：SwiftData 模型和共享类型
- `1Day/1Day/Services/`：业务服务、AI、图片、通知、备份
- `1Day/1Day/Views/`：Today、Plan、AIChat、Notes、Onboarding、Settings 等页面
- `1Day/docs/MVP_SCOPE.md`：当前版本范围
- `1Day/docs/DATA_MODEL.md`：数据模型定义
- `1Day/docs/UX_FLOW.md`：用户流程
- `1Day/PRD.md`：产品需求文档

## 运行方式

1. 用 Xcode 打开 `1Day/1Day.xcodeproj`
2. 选择 `1Day` scheme
3. 选择真机或模拟器
4. 点击 Run

当前部署版本为 iOS 17.0。

## 重要限制

- V1.0 只做任务和独立笔记，不做事件、日历、重复任务、收藏集、标签、证件管理和复盘模型。
- AI API Key 存在 iOS Keychain；AI 只生成草稿，必须用户确认后才写入 SwiftData。
- 数据默认本地保存；V1.0 不接入 iCloud 同步和账号系统。
- 当前界面文案主要是中文，本地化仍在 MVP 范围内推进。

## 文档索引

- [PRD](PRD.md)
- [MVP 范围](docs/MVP_SCOPE.md)
- [数据模型](docs/DATA_MODEL.md)
- [用户流程](docs/UX_FLOW.md)
- [AI 行为规范](docs/AI_BEHAVIOR_SPEC.md)
- [文件复用清单](docs/REUSE_PLAN.md)
