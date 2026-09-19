import SwiftUI
import SwiftData
import UniformTypeIdentifiers
import PhotosUI

struct SettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var settings: [UserSettings]
    @Query private var planItems: [PlanItem]
    @Query private var notes: [Note]

    @State private var backupURL: URL?
    @State private var pendingImportURL: URL?
    @State private var isShowingImporter = false
    @State private var clearDataStep = 0
    @State private var isShowingInbox = false
    @State private var isShowingProfileEditor = false
    @State private var statusMessage: String?
    @State private var errorMessage: String?

    private var currentSettings: UserSettings? { settings.first }

    private func localized(_ chinese: String, _ english: String) -> String {
        AppSettingsLocalization.text(chinese, english, language: currentSettings?.language ?? .system)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: AppSpacing.sectionSpacing) {
                    if let s = currentSettings {
                        profileSection(s)
                        aiSection(s)
                        generalSection(s)
                        feedbackSection(s)
                        dataSection
                        displaySection(s)
                        aboutSection
                    }
                }
                .padding(.horizontal, AppSpacing.pageHorizontal)
                .padding(.bottom, AppSpacing.pageBottom)
                .padding(.top, 4)
            }
            .scrollIndicators(.hidden)
            .background(FamilyUI.pageBackground.ignoresSafeArea())
            .navigationTitle(localized("设置", "Settings"))
            .navigationBarTitleDisplayMode(.inline)
            .fileImporter(
                isPresented: $isShowingImporter,
                allowedContentTypes: [.json],
                allowsMultipleSelection: false
            ) { result in
                switch result {
                case .success(let urls): pendingImportURL = urls.first
                case .failure(let error): errorMessage = "选择备份失败：\(error.localizedDescription)"
                }
            }
            .alert("导入备份将替换当前数据", isPresented: Binding(
                get: { pendingImportURL != nil },
                set: { if !$0 { pendingImportURL = nil } }
            )) {
                Button("取消", role: .cancel) { pendingImportURL = nil }
                Button("导入", role: .destructive) { importBackup() }
            } message: {
                Text("会替换任务、笔记和设置，并重建任务提醒。建议先导出当前备份。")
            }
            .alert("清空任务和笔记？", isPresented: Binding(
                get: { clearDataStep == 1 },
                set: { if !$0 { clearDataStep = 0 } }
            )) {
                Button("继续", role: .destructive) { clearDataStep = 2 }
                Button("取消", role: .cancel) {}
            } message: {
                Text("会删除所有任务、笔记和待办提醒，但保留个人资料和 AI 配置。")
            }
            .alert("最后确认", isPresented: Binding(
                get: { clearDataStep == 2 },
                set: { if !$0 { clearDataStep = 0 } }
            )) {
                Button("清空所有数据", role: .destructive) { clearUserData() }
                Button("取消", role: .cancel) {}
            } message: {
                Text("此操作不可撤销。建议先导出备份。")
            }
            .alert("数据管理", isPresented: statusAlertBinding) {
                Button("好", role: .cancel) {
                    statusMessage = nil
                    errorMessage = nil
                }
            } message: {
                Text(statusMessage ?? errorMessage ?? "")
            }
            .sheet(isPresented: $isShowingInbox) {
                InAppInboxSheet()
            }
            .sheet(isPresented: $isShowingProfileEditor) {
                if let s = currentSettings {
                    ProfileSettingsView(settings: s)
                }
            }
        }
    }

    // MARK: - Sections

    private func profileSection(_ settings: UserSettings) -> some View {
        SystemPanel {
            Button {
                isShowingProfileEditor = true
            } label: {
                HStack(spacing: 14) {
                    UserAvatarView(
                        avatarData: settings.avatarImageData,
                        symbolName: settings.avatarSymbolName,
                        name: settings.nickname,
                        size: 56
                    )
                    VStack(alignment: .leading, spacing: 6) {
                        Text(settings.nickname.isEmpty ? "未设置昵称" : settings.nickname)
                            .font(.headline)
                            .foregroundStyle(.primary)
                        HStack(spacing: 8) {
                            SystemStatusBadge(
                                text: settings.isAIConfigured ? "AI 已配置" : "AI 未设置",
                                tone: settings.isAIConfigured ? .success : .warning
                            )
                            SystemStatusBadge(text: "\(planItems.count) 个任务", tone: .neutral)
                        }
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
            }
            .buttonStyle(.plain)
        }
    }

    private func generalSection(_ settings: UserSettings) -> some View {
        SystemPanel(title: localized("基础设置", "General")) {
            VStack(alignment: .leading, spacing: 0) {
                NavigationLink {
                    ReminderSettingsView(settings: settings)
                } label: {
                    AppSettingsRow(
                        icon: "bell.fill",
                        title: "默认提醒时间",
                        value: String(format: "%02d:%02d", settings.defaultReminderHour, settings.defaultReminderMinute),
                        showsChevron: true
                    )
                }
                .buttonStyle(.plain)

            }
        }
    }

    private func displaySection(_ settings: UserSettings) -> some View {
        SystemPanel(title: localized("显示", "Display")) {
            VStack(alignment: .leading, spacing: 0) {
                Menu {
                    Picker("语言", selection: languageBinding(settings)) {
                        ForEach(AppLanguage.allCases) { language in
                            Text(language.displayName).tag(language)
                        }
                    }
                } label: {
                    AppSettingsRow(icon: "globe", title: localized("语言", "Language"), value: settings.language.displayName, showsChevron: true)
                }
                .buttonStyle(.plain)

                SystemPanelDivider()

                AppSettingsRow(
                    icon: "circle.lefthalf.filled",
                    title: localized("外观", "Appearance"),
                    subtitle: localized("浅色、深色或跟随系统", "Light, dark, or system"),
                    value: settings.appearance.displayName
                )

                Picker("外观", selection: appearanceBinding(settings)) {
                    ForEach(AppearanceMode.allCases) { appearance in
                        Text(appearance.displayName).tag(appearance)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .padding(.top, 4)
            }
        }
    }

    private func feedbackSection(_ settings: UserSettings) -> some View {
        SystemPanel(title: localized("反馈", "Feedback")) {
            VStack(alignment: .leading, spacing: 0) {
                Toggle(isOn: hapticsBinding(settings)) {
                    AppSettingsRow(icon: "hand.tap.fill", title: "震动反馈", subtitle: "操作时提供触感反馈")
                }
                .tint(FamilyUI.accent)

                SystemPanelDivider()

                Toggle(isOn: soundBinding(settings)) {
                    AppSettingsRow(icon: "speaker.wave.2.fill", title: "提示音", subtitle: "完成操作时播放确认音")
                }
                .tint(FamilyUI.accent)
            }
        }
    }

    private func aiSection(_ settings: UserSettings) -> some View {
        SystemPanel(title: localized("AI 配置", "AI Configuration")) {
            NavigationLink {
                AIConfigurationSettingsView()
            } label: {
                VStack(alignment: .leading, spacing: 12) {
                    AppSettingsRow(
                        icon: "sparkles",
                        title: "AI 服务商",
                        value: settings.isAIConfigured ? settings.selectedAIProvider.displayName : "未配置",
                        showsChevron: true
                    )

                    HStack(spacing: 8) {
                        SystemStatusBadge(
                            text: settings.isAIConfigured ? "已配置" : "未设置",
                            tone: settings.isAIConfigured ? .success : .warning
                        )
                        SystemStatusBadge(
                            text: settings.selectedAIProvider.supportsVision(model: settings.selectedAIModel) ? "支持视觉" : "仅文本",
                            tone: settings.selectedAIProvider.supportsVision(model: settings.selectedAIModel) ? .accent : .neutral
                        )
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }

    private var dataSection: some View {
        SystemPanel(title: localized("数据管理", "Data")) {
            VStack(alignment: .leading, spacing: 0) {
                Button {
                    exportBackup()
                } label: {
                    AppSettingsRow(
                        icon: "square.and.arrow.up",
                        title: "导出备份",
                        value: backupURL == nil ? "" : "已生成"
                    )
                }
                .buttonStyle(.plain)

                if let backupURL {
                    SystemPanelDivider()
                    ShareLink(item: backupURL) {
                        AppSettingsRow(icon: "square.and.arrow.up.on.square", title: "分享备份文件")
                    }
                    .buttonStyle(.plain)
                }

                SystemPanelDivider()

                Button {
                    isShowingImporter = true
                } label: {
                    AppSettingsRow(icon: "square.and.arrow.down", title: "导入备份")
                }
                .buttonStyle(.plain)

                SystemPanelDivider()

                Button(role: .destructive) {
                    clearDataStep = 1
                } label: {
                    AppSettingsRow(icon: "trash", title: "清空任务和笔记", iconColor: FamilyUI.danger)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var aboutSection: some View {
        SystemPanel(title: localized("关于", "About")) {
            VStack(alignment: .leading, spacing: 0) {
                Button {
                    isShowingInbox = true
                } label: {
                    AppSettingsRow(icon: "tray.full", title: "站内信", showsChevron: true)
                }
                .buttonStyle(.plain)

                SystemPanelDivider()

                NavigationLink {
                    StaticInfoView.userManual
                } label: {
                    AppSettingsRow(icon: "book", title: "用户手册", showsChevron: true)
                }
                .buttonStyle(.plain)

                SystemPanelDivider()

                NavigationLink {
                    StaticInfoView.privacy
                } label: {
                    AppSettingsRow(icon: "hand.raised.fill", title: "隐私说明", showsChevron: true)
                }
                .buttonStyle(.plain)

                SystemPanelDivider()

                Button {
                    contactSupport()
                } label: {
                    AppSettingsRow(icon: "envelope.fill", title: "意见反馈", showsChevron: true)
                }
                .buttonStyle(.plain)

                SystemPanelDivider()

                AppSettingsRow(
                    icon: "info.circle",
                    title: "版本",
                    value: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0",
                    iconColor: FamilyUI.subtleText
                )
            }
        }
    }

    private func languageBinding(_ settings: UserSettings) -> Binding<AppLanguage> {
        Binding {
            settings.language
        } set: { language in
            settings.language = language
            settings.updatedAt = Date()
            // 通知文案是在调度时生成的，拿不到 SwiftData，需要这一步桥接。
            NotificationService.syncInterfaceLanguage(language)
        }
    }

    private func appearanceBinding(_ settings: UserSettings) -> Binding<AppearanceMode> {
        Binding {
            settings.appearance
        } set: { appearance in
            settings.appearance = appearance
            settings.updatedAt = Date()
        }
    }

    private func hapticsBinding(_ settings: UserSettings) -> Binding<Bool> {
        Binding {
            settings.isHapticsEnabled
        } set: { enabled in
            settings.isHapticsEnabled = enabled
            settings.updatedAt = Date()
            FeedbackPreferences.shared.setHapticsEnabled(enabled)
        }
    }

    private func soundBinding(_ settings: UserSettings) -> Binding<Bool> {
        Binding {
            settings.isSoundEffectsEnabled
        } set: { enabled in
            settings.isSoundEffectsEnabled = enabled
            settings.updatedAt = Date()
            FeedbackPreferences.shared.setSoundEffectsEnabled(enabled)
        }
    }

    private var statusAlertBinding: Binding<Bool> {
        Binding {
            statusMessage != nil || errorMessage != nil
        } set: { isPresented in
            if !isPresented {
                statusMessage = nil
                errorMessage = nil
            }
        }
    }

    private func exportBackup() {
        do {
            backupURL = try SettingsDataCoordinator.exportBackup(
                planItems: planItems,
                notes: notes,
                settings: currentSettings
            )
            statusMessage = "备份文件已生成，可以点击「分享备份文件」保存或发送。"
            errorMessage = nil
            HapticEngine.success()
        } catch {
            errorMessage = "导出失败：\(error.localizedDescription)"
            statusMessage = nil
        }
    }

    private func importBackup() {
        do {
            guard let url = pendingImportURL else { return }
            try SettingsDataCoordinator.importBackup(
                from: url,
                existingPlanItems: planItems,
                existingNotes: notes,
                existingSettings: currentSettings,
                in: modelContext
            )
            statusMessage = "备份已恢复"
            errorMessage = nil
            pendingImportURL = nil
            HapticEngine.success()
        } catch {
            errorMessage = "导入失败：\(error.localizedDescription)"
            statusMessage = nil
            pendingImportURL = nil
        }
    }

    private func clearUserData() {
        do {
            try SettingsDataCoordinator.clearAllData(planItems: planItems, notes: notes, in: modelContext)
            backupURL = nil
            statusMessage = "任务和笔记已清空"
            errorMessage = nil
            clearDataStep = 0
            HapticEngine.success()
        } catch {
            errorMessage = "清空失败：\(error.localizedDescription)"
            statusMessage = nil
            clearDataStep = 0
            HapticEngine.warning()
        }
    }

    private func contactSupport() {
        let email = "tyx22000044@gmail.com"
        if let url = URL(string: "mailto:\(email)?subject=1Day%20反馈"),
           UIApplication.shared.canOpenURL(url) {
            UIApplication.shared.open(url)
        }
    }
}

private struct InAppInboxSheet: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage("onePlanReadInAppMessageIDs") private var readIDsRaw = ""

    private static let messages: [InAppMessage] = [
        InAppMessage(
            id: "1day-update-2026-07-15-performance-pass",
            title: "2026-07-15 性能优化",
            dateText: "2026.07.15",
            body: "完成本轮 1Day 性能收口：计划列表分组从 6 次独立 filter 改为单次遍历直接分桶，并在 body 中只计算一次分组结果；今日页把过期/待办/已完成三个各自扫描全部任务的计算属性合并成一次遍历生成的 TodaySnapshot；笔记搜索增加约 250ms 防抖，避免每次按键都重新扫描标题和全文；AI Chat 的任务查询加上 dueDate 非空条件，不再把未安排的历史任务也读入 AI 上下文。全部完成静态语法核验，未执行 build 或模拟器。"
        ),
        InAppMessage(
            id: "1day-update-2026-07-15-family-consistency-audit",
            title: "2026-07-15 家族一致性核验与修复",
            dateText: "2026.07.15",
            body: "以 1Life 为基准核验 Head Tab、AI Chat 和 Settings 三处家族共享界面：AI Chat 清空对话改回确认弹窗样式，发送按钮改为家族统一的黑色方块，空状态和建议词条视觉对齐 1Life 结构；AI 配置页补齐模型选择、掩码 Key 展示、删除 Key、获取 API Key 入口和聊天历史清理；Profile 编辑改为真正的相册取图并支持取消。全部完成静态语法核验，未执行 build 或模拟器。"
        ),
        InAppMessage(
            id: "1day-update-2026-07-15-typography-unification",
            title: "2026-07-15 家族字体统一完成",
            dateText: "2026.07.15",
            body: "完成 1App Family 字体系统统一：以 1Life 热量主数字的圆体视觉为基准，统一 FamilyTypography、页面标题、Hero 数字、按钮、设置行、状态徽标、Splash 和页面显式字号；单号、验证码等机器可读字段继续保留等宽字体。六个 App 已完成 Swift 静态语法核验，未执行 build 或模拟器。"
        ),
        InAppMessage(
            id: "1day-update-2026-07-15-ui-alignment",
            title: "2026-07-15 1Day UI 全面更新",
            dateText: "2026.07.15",
            body: "本次更新完成 1Day 与 1Life 的界面对齐：统一各 Tab 标题栏、AI Chat 气泡与输入区、设置页分组和 FamilyUI Sheet；新建任务、任务详情、日期选择与 AI 草稿确认已改为统一面板布局。Today 与 Plan 任务行也已收口到共享样式。"
        ),
        InAppMessage(
            id: "1day-update-2026-07-14-icon-refresh",
            title: "2026-07-14 图标视觉更新",
            dateText: "2026.07.14",
            body: "1App Family 图标已换成更醒目的 V2 版本：1Day 采用日历与勾选主视觉，突出计划、任务和日程管理；同时补齐浅色、深色和 tinted 图标资源，旧图标已保留备份。本次只更新图标资源与站内信记录，未执行 build。"
        ),
        InAppMessage(
            id: "1day-update-2026-07-14-app-renaming",
            title: "2026-07-14 App 名称更新",
            dateText: "2026.07.14",
            body: "1Plan 已正式更名为 1Day。任务、日程、笔记和本地数据保持不变；本次更新同步了 App 名称、工程和相关文档，正式 Bundle ID 与本地数据兼容标识保持不变。"
        ),

        InAppMessage(
            id: "1day-update-2026-07-14-visual-repair-complete",
            title: "2026-07-14 视觉与 AI 对齐修复",
            dateText: "2026.07.14",
            body: "完成本轮 1Day 家族一致性修复：统一 CTA、设置行、资料编辑 Sheet、Splash、Today 趋势与任务行；补齐 Onboarding AI 配置、AI 图片输入、图片预览和失败重试。源码已完成静态核验，本轮未执行 build 或模拟器验证。"
        ),
        InAppMessage(
            id: "1day-update-2026-07-13-family-alignment-final",
            title: "2026-07-13 家族对齐收口",
            dateText: "2026.07.13",
            body: "完成 App Family 最新一轮静态对齐记录：统一 Family UI 细节、AI 配置语义、设置页站内信和危险操作反馈；本轮只进行代码与结构核验，未执行 build 或模拟器验证。"
        ),
        InAppMessage(
            id: "1day-update-2026-07-10-ai-model-switch",
            title: "2026-07-10 更新记录",
            dateText: "2026.07.10",
            body: "AI Chat 顶部「切换」菜单升级：现在不仅能切换服务商，也能直接切换当前服务商下的模型；切换后会保存到 AI 配置，下一次请求会使用新的模型 ID。AI 身份或模型相关问题不再由 App 规则代答，会交给当前选择的模型自行回复。"
        )
    ]

    private var readIDs: Set<String> {
        get { Set(readIDsRaw.split(separator: ",").map(String.init)) }
        nonmutating set { readIDsRaw = newValue.sorted().joined(separator: ",") }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 12) {
                    SystemPageHeader(
                        eyebrow: "站内信",
                        title: "产品更新",
                        detail: "记录重要功能变化和安全提醒"
                    )

                    ForEach(Self.messages) { message in
                        InAppMessageCard(
                            message: message,
                            isRead: readIDs.contains(message.id)
                        ) {
                            markRead(message)
                        }
                    }
                }
                .padding(.horizontal, AppSpacing.pageHorizontal)
                .padding(.top, 16)
                .padding(.bottom, AppSpacing.pageBottom)
            }
            .background(FamilyUI.pageBackground.ignoresSafeArea())
            .navigationTitle("站内信")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("完成") { dismiss() }
                }
            }
        }
    }

    private func markRead(_ message: InAppMessage) {
        var ids = readIDs
        ids.insert(message.id)
        readIDs = ids
    }
}

private struct InAppMessageCard: View {
    let message: InAppMessage
    let isRead: Bool
    let onMarkRead: () -> Void

    var body: some View {
        Button(action: onMarkRead) {
            SystemPanel {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(message.title)
                            .font(.headline)
                            .foregroundStyle(.primary)
                            .multilineTextAlignment(.leading)

                        if !isRead {
                            Text("未读")
                                .font(.caption2.weight(.bold))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 3)
                                .background(FamilyUI.accent)
                                .foregroundStyle(FamilyUI.onAccent)
                                .clipShape(RoundedRectangle(cornerRadius: FamilyUI.badgeCornerRadius))
                        }

                        Spacer()
                    }

                    Text(message.dateText)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)

                    Text(message.body)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .buttonStyle(.plain)
    }
}

private struct InAppMessage: Identifiable {
    let id: String
    let title: String
    let dateText: String
    let body: String
}

private struct StaticInfoView: View {
    @Environment(\.dismiss) private var dismiss

    let title: String
    let eyebrow: String
    let detail: String
    let panelTitle: String
    let footer: String
    let sections: [StaticInfoSection]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                SystemPageHeader(eyebrow: eyebrow, title: title, detail: detail)

                SystemPanel(title: panelTitle) {
                    ForEach(Array(sections.enumerated()), id: \.element.id) { index, section in
                        if index > 0 { SystemPanelDivider() }

                        HStack(alignment: .top, spacing: 12) {
                            RoundedRectangle(cornerRadius: FamilyUI.controlCornerRadius)
                                .fill(FamilyUI.panelMutedBackground)
                                .overlay(
                                    RoundedRectangle(cornerRadius: FamilyUI.controlCornerRadius)
                                        .stroke(FamilyUI.panelBorder, lineWidth: 1)
                                )
                                .frame(width: FamilyUI.iconBoxSize, height: FamilyUI.iconBoxSize)
                                .overlay(
                                    Image(systemName: section.icon)
                                        .font(.system(size: 14, weight: .semibold))
                                        .foregroundStyle(FamilyUI.accent)
                                )

                            VStack(alignment: .leading, spacing: 4) {
                                Text(section.title)
                                    .font(.subheadline.weight(.semibold))
                                Text(section.body)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                                    .lineSpacing(2)
                            }
                        }
                        .padding(.vertical, 2)
                    }
                }

                Text(footer)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
            }
            .padding(.horizontal, AppSpacing.pageHorizontal)
            .padding(.top, 16)
            .padding(.bottom, AppSpacing.pageBottom)
        }
        .background(FamilyUI.pageBackground.ignoresSafeArea())
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("完成") { dismiss() }
            }
        }
    }

    static var userManual: StaticInfoView {
        StaticInfoView(
            title: "用户手册",
            eyebrow: "用户手册",
            detail: "快速了解 1Day 的任务、AI 和数据管理。",
            panelTitle: "使用指南",
            footer: "1Day v\(oneDayVersion) · 日常计划参考",
            sections: [
                StaticInfoSection(icon: "checklist", title: "任务", body: "在「今天」查看当天事项，在「计划」管理全部任务。点击任务可编辑标题、备注、日期、提醒和优先级。"),
                StaticInfoSection(icon: "sparkles", title: "AI", body: "在 AI 页面输入自然语言，例如「明天下午整理 PRD，高优先级」，确认后会创建任务。API Key 可在设置中配置。"),
                StaticInfoSection(icon: "externaldrive.fill", title: "备份", body: "设置里的数据管理支持导出 JSON 备份、导入备份，以及清空任务和笔记。API Key 不会写入备份文件。")
            ]
        )
    }

    static var privacy: StaticInfoView {
        StaticInfoView(
            title: "隐私说明",
            eyebrow: "隐私政策",
            detail: "本机优先、API Key 隔离和可删除数据。",
            panelTitle: "数据处理",
            footer: "1Day v\(oneDayVersion) · © 2026",
            sections: [
                StaticInfoSection(icon: "lock.shield.fill", title: "本地数据", body: "任务、笔记、个人资料和设置默认保存在本机的 SwiftData 数据库中。"),
                StaticInfoSection(icon: "sparkles", title: "AI 配置", body: "API Key 存储在 iOS Keychain 中，不会进入 JSON 备份。使用 AI 功能时，输入内容会发送给你选择的服务商。"),
                StaticInfoSection(icon: "checkmark.seal.fill", title: "AI 使用边界", body: "AI 只帮助整理任务、笔记和计划草稿，不提供医疗、法律或金融建议。AI 输出可能遗漏或误解输入内容，保存或执行前请自行核对；涉及高风险决定时请咨询合格专业人士。"),
                StaticInfoSection(icon: "bell.fill", title: "通知", body: "如果开启任务提醒，系统会根据任务日期和提醒时间创建本地通知。完成、删除或清空任务时会取消对应提醒。")
            ]
        )
    }
}

private var oneDayVersion: String {
    (Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String) ?? "—"
}

private struct StaticInfoSection: Identifiable {
    var id: String { title }
    let icon: String
    let title: String
    let body: String
}

private struct ProfileSettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable var settings: UserSettings
    @State private var nickname: String = ""
    @State private var avatarData: Data?
    @State private var avatarItem: PhotosPickerItem?

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: AppSpacing.sectionSpacing) {
                    SystemPanel(title: "头像", detail: "点击头像即可更换照片") {
                        HStack {
                            Spacer()
                            PhotosPicker(selection: $avatarItem, matching: .images) {
                                ZStack(alignment: .bottomTrailing) {
                                    UserAvatarView(
                                        avatarData: avatarData,
                                        symbolName: settings.avatarSymbolName,
                                        name: nickname,
                                        size: 108
                                    )
                                    RoundedRectangle(cornerRadius: FamilyUI.controlCornerRadius)
                                        .fill(FamilyUI.ink)
                                        .frame(width: 30, height: 30)
                                        .overlay(
                                            Image(systemName: "camera.fill")
                                                .font(.system(size: 12, weight: .semibold))
                                                .foregroundStyle(FamilyUI.paper)
                                        )
                                }
                            }
                            Spacer()
                        }
                    }

                    SystemPanel(title: "身份信息", detail: "昵称会用于设置页等个人标识") {
                        SystemTextField(label: "昵称", text: $nickname, placeholder: "你的昵称")
                    }
                }
                .padding(.horizontal, AppSpacing.pageHorizontal)
                .padding(.vertical, 16)
            }
            .background(FamilyUI.pageBackground.ignoresSafeArea())
            .navigationTitle("编辑资料")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        settings.nickname = nickname.trimmingCharacters(in: .whitespaces)
                        settings.avatarImageData = avatarData
                        settings.updatedAt = Date()
                        HapticEngine.success()
                        dismiss()
                    }
                }
            }
            .onAppear {
                nickname = settings.nickname
                avatarData = settings.avatarImageData
            }
            .onChange(of: avatarItem) { _, item in
                Task {
                    guard let data = try? await item?.loadTransferable(type: Data.self) else { return }
                    // 头像会整块存进 SwiftData，压不下去就不要塞进去。
                    guard let compressed = ImageService.compress(data, maxBytes: 512_000) else {
                        GlobalBannerCenter.shared.show(
                            title: "这张照片做头像太大",
                            message: "压缩后仍然超过上限，换一张清晰的近照试试。",
                            tone: .warning
                        )
                        return
                    }
                    avatarData = compressed
                }
            }
        }
    }
}

private struct ReminderSettingsView: View {
    @Bindable var settings: UserSettings

    @State private var permissionState: ReminderPermissionState?

    private var reminderDate: Binding<Date> {
        Binding {
            Calendar.current.date(
                bySettingHour: settings.defaultReminderHour,
                minute: settings.defaultReminderMinute,
                second: 0,
                of: Date()
            ) ?? Date()
        } set: { date in
            let components = Calendar.current.dateComponents([.hour, .minute], from: date)
            settings.defaultReminderHour = components.hour ?? 9
            settings.defaultReminderMinute = components.minute ?? 0
            settings.updatedAt = Date()
            NotificationService.syncDefaultReminderTime(
                hour: settings.defaultReminderHour,
                minute: settings.defaultReminderMinute
            )
        }
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: AppSpacing.sectionSpacing) {
                SystemPanel(title: "默认提醒时间", detail: "新任务未设置自定义提醒时，会使用这个时间。") {
                    DatePicker("时间", selection: reminderDate, displayedComponents: .hourAndMinute)
                        .datePickerStyle(.wheel)
                        .labelsHidden()
                        .frame(maxWidth: .infinity)
                }

                SystemPanel {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(Array([8, 9, 10, 18].enumerated()), id: \.element) { index, hour in
                            Button {
                                settings.defaultReminderHour = hour
                                settings.defaultReminderMinute = 0
                                settings.updatedAt = Date()
                                NotificationService.syncDefaultReminderTime(hour: hour, minute: 0)
                                HapticEngine.success()
                            } label: {
                                HStack {
                                    Text(String(format: "%02d:00", hour))
                                        .foregroundStyle(.primary)
                                    Spacer()
                                    if settings.defaultReminderHour == hour && settings.defaultReminderMinute == 0 {
                                        Image(systemName: "checkmark")
                                            .foregroundStyle(FamilyUI.accent)
                                    }
                                }
                                .padding(.vertical, 6)
                            }
                            .buttonStyle(.plain)
                            if index < 3 {
                                SystemPanelDivider()
                            }
                        }
                    }
                }

                SystemPanel(title: "通知权限", detail: "以系统里的实际设置为准，不只是 App 内的开关") {
                    VStack(alignment: .leading, spacing: 0) {
                        AppSettingsRow(
                            icon: permissionState?.needsUserAction == true ? "bell.slash" : "bell.badge",
                            title: permissionState?.title ?? "正在检查通知权限…",
                            subtitle: permissionState.map { $0.guidance } ?? "正在读取系统设置中的状态。",
                            iconColor: permissionState == .granted ? FamilyUI.success : FamilyUI.warning
                        )

                        if permissionState?.needsUserAction == true {
                            SystemPanelDivider()
                            Button {
                                openSystemNotificationSettings()
                            } label: {
                                AppSettingsRow(icon: "gearshape", title: "前往系统设置开启通知", showsChevron: true)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            .padding(.horizontal, AppSpacing.pageHorizontal)
            .padding(.vertical, 16)
        }
        .background(FamilyUI.pageBackground.ignoresSafeArea())
        .task {
            permissionState = await NotificationService.permissionState()
        }
        .navigationTitle("提醒时间")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func openSystemNotificationSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }
}

private struct AIConfigurationSettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var settings: [UserSettings]
    @Query(sort: [SortDescriptor(\AIChatMessage.createdAt)]) private var chatMessages: [AIChatMessage]

    @State private var apiKey = ""
    @State private var maskedKey = ""
    @State private var statusMessage: String?
    @State private var errorMessage: String?
    @State private var isTesting = false
    @State private var testResultMessage: String?
    @State private var testFailed = false
    @State private var showClearChatAlert = false

    private let configurationService = LocalAIConfigurationService()

    private var currentSettings: UserSettings? {
        settings.first
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: AppSpacing.sectionSpacing) {
                if let settings = currentSettings {
                    providerSection(settings)
                    apiKeySection(settings)
                    capabilitySection(settings)
                    apiKeyLinksSection
                    chatHistorySection
                } else {
                    AppEmptyStateView(icon: "gearshape", title: "设置未初始化")
                }
            }
            .padding(.horizontal, AppSpacing.pageHorizontal)
            .padding(.vertical, 16)
        }
        .background(FamilyUI.pageBackground.ignoresSafeArea())
        .scrollDismissesKeyboard(.interactively)
        .navigationTitle("AI 配置")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear(perform: loadMaskedKey)
        .alert("AI 配置已保存", isPresented: statusIsSavedBinding) { Button("好", role: .cancel) {} }
        .alert("清空聊天历史", isPresented: $showClearChatAlert) {
            Button("取消", role: .cancel) {}
            Button("清空", role: .destructive) {
                HapticEngine.warning()
                for message in chatMessages { modelContext.delete(message) }
            }
        } message: {
            Text("将删除所有 \(chatMessages.count) 条聊天消息，此操作不可恢复。")
        }
    }

    private func providerSection(_ settings: UserSettings) -> some View {
        SystemPanel(title: "服务商") {
            VStack(alignment: .leading, spacing: 12) {
                Menu {
                    Picker("服务商", selection: providerBinding(settings)) {
                        ForEach(configurationService.providerOptions) { option in
                            Text(option.displayName).tag(option.provider)
                        }
                    }
                } label: {
                    AppSettingsRow(icon: "sparkles", title: "AI 服务商", value: selectedOption(for: settings)?.displayName ?? "", showsChevron: true)
                }
                .buttonStyle(.plain)

                SystemPanelDivider()

                if selectedOption(for: settings)?.usesEndpointBoundKey == true {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("模型")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                        TextField("模型 ID", text: modelBinding(settings))
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .padding(.horizontal, 12)
                            .padding(.vertical, 10)
                            .background(FamilyUI.panelMutedBackground)
                            .overlay(
                                RoundedRectangle(cornerRadius: FamilyUI.controlCornerRadius)
                                    .stroke(FamilyUI.panelBorder, lineWidth: 1)
                            )
                            .clipShape(RoundedRectangle(cornerRadius: FamilyUI.controlCornerRadius))
                    }
                } else {
                    Menu {
                        Picker("模型", selection: modelBinding(settings)) {
                            ForEach(selectedOption(for: settings)?.models ?? [settings.selectedAIModel], id: \.self) { model in
                                Text(model).tag(model)
                            }
                        }
                    } label: {
                        AppSettingsRow(icon: "slider.horizontal.3", title: "模型", value: settings.selectedAIModel, showsChevron: true)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func apiKeySection(_ settings: UserSettings) -> some View {
        SystemPanel(title: "API Key") {
            VStack(alignment: .leading, spacing: 12) {
                AppSettingsRow(icon: "key.fill", title: "当前 Key", subtitle: "已保存的密钥会用掩码显示", value: maskedKey)

                SecureField("粘贴新的 API Key", text: $apiKey)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .background(FamilyUI.panelMutedBackground)
                    .overlay(
                        RoundedRectangle(cornerRadius: FamilyUI.controlCornerRadius)
                            .stroke(FamilyUI.panelBorder, lineWidth: 1)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: FamilyUI.controlCornerRadius))

                Button {
                    saveConfiguration(settings)
                } label: {
                    Text("保存配置")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? FamilyUI.panelMutedBackground : FamilyUI.ink)
                        .foregroundStyle(apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? FamilyUI.subtleText : FamilyUI.paper)
                        .clipShape(RoundedRectangle(cornerRadius: FamilyUI.controlCornerRadius))
                }
                .buttonStyle(.plain)
                .disabled(apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                if settings.isAIConfigured {
                    Button {
                        testConnection(settings)
                    } label: {
                        HStack {
                            Text(isTesting ? "连接测试中…" : "测试连接")
                            if isTesting {
                                Spacer()
                                ProgressView().controlSize(.small)
                            }
                        }
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(FamilyUI.panelMutedBackground)
                        .overlay(
                            RoundedRectangle(cornerRadius: FamilyUI.controlCornerRadius)
                                .stroke(FamilyUI.panelBorder, lineWidth: 1)
                        )
                        .clipShape(RoundedRectangle(cornerRadius: FamilyUI.controlCornerRadius))
                    }
                    .buttonStyle(.plain)
                    .disabled(isTesting)

                    Button(role: .destructive) {
                        deleteKey(settings)
                    } label: {
                        Text("删除 Key")
                            .font(.subheadline.weight(.semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                            .background(FamilyUI.danger.opacity(0.08))
                            .foregroundStyle(FamilyUI.danger)
                            .overlay(
                                RoundedRectangle(cornerRadius: FamilyUI.controlCornerRadius)
                                    .stroke(FamilyUI.danger.opacity(0.35), lineWidth: 1)
                            )
                            .clipShape(RoundedRectangle(cornerRadius: FamilyUI.controlCornerRadius))
                    }
                    .buttonStyle(.plain)
                }

                if let testResultMessage {
                    Text(testResultMessage)
                        .font(.caption)
                        .foregroundStyle(testFailed ? FamilyUI.danger : FamilyUI.success)
                }

                if let statusMessage {
                    Text(statusMessage)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if let errorMessage {
                    Text(errorMessage)
                        .font(.caption)
                        .foregroundStyle(FamilyUI.danger)
                }

                Text("API Key 存储在 iOS Keychain，不写入 SwiftData 或备份文件。")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func capabilitySection(_ settings: UserSettings) -> some View {
        SystemPanel(title: "能力说明") {
            if let option = selectedOption(for: settings) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(option.capabilityDescription)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    if option.usesEndpointBoundKey {
                        Label("该服务商的模型 ID 通常需要与控制台接入点保持一致。", systemImage: "info.circle")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    private var apiKeyLinksSection: some View {
        SystemPanel(title: "获取 API Key", detail: "官方开发平台入口，仅供参考") {
            VStack(alignment: .leading, spacing: 0) {
                Text("请确认域名、账号与计费信息安全。不要向非官方页面提交 API Key；1Day 只会把你主动保存的 Key 存入本机 Keychain。")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                SystemPanelDivider()

                ForEach(apiKeyLinks) { item in
                    Link(destination: item.url) {
                        AppSettingsRow(icon: "key.viewfinder", title: item.provider.displayName, subtitle: item.note, showsChevron: false)
                    }
                    if item.id != apiKeyLinks.last?.id {
                        SystemPanelDivider()
                    }
                }
            }
        }
    }

    private var chatHistorySection: some View {
        SystemPanel(title: "聊天历史", detail: "Family 统一 AI 对话清理规则") {
            AppSettingsRow(icon: "text.bubble", title: "消息数量", subtitle: "当前本机保存的 AI 聊天记录", value: "\(chatMessages.count) 条")

            SystemPanelDivider()

            Button(role: .destructive) {
                showClearChatAlert = true
            } label: {
                AppSettingsRow(icon: "trash", title: "清空聊天历史", subtitle: "删除所有 AI 对话消息，不可恢复", value: chatMessages.isEmpty ? "无数据" : "清空", iconColor: FamilyUI.danger)
            }
            .buttonStyle(.plain)
            .disabled(chatMessages.isEmpty)
        }
    }

    private var apiKeyLinks: [AIAPIKeyLink] {
        [
            AIAPIKeyLink(provider: .claude, url: URL(string: "https://console.anthropic.com/settings/keys")!, note: "Anthropic Console"),
            AIAPIKeyLink(provider: .chatGPT, url: URL(string: "https://platform.openai.com/api-keys")!, note: "OpenAI Platform"),
            AIAPIKeyLink(provider: .kimi, url: URL(string: "https://platform.moonshot.cn/console/api-keys")!, note: "Moonshot AI 开放平台"),
            AIAPIKeyLink(provider: .qwen, url: URL(string: "https://bailian.console.aliyun.com/")!, note: "阿里云百炼控制台"),
            AIAPIKeyLink(provider: .doubao, url: URL(string: "https://console.volcengine.com/ark/")!, note: "火山方舟控制台"),
            AIAPIKeyLink(provider: .yuanbao, url: URL(string: "https://console.cloud.tencent.com/hunyuan")!, note: "腾讯云混元控制台"),
            AIAPIKeyLink(provider: .deepseek, url: URL(string: "https://platform.deepseek.com/api_keys")!, note: "DeepSeek 开放平台"),
            AIAPIKeyLink(provider: .mimo, url: URL(string: "https://platform.xiaomimimo.com/")!, note: "MiMo 开放平台")
        ]
    }

    private var statusIsSavedBinding: Binding<Bool> {
        Binding {
            statusMessage != nil && errorMessage == nil
        } set: { isPresented in
            if !isPresented { statusMessage = nil }
        }
    }

    private func providerBinding(_ settings: UserSettings) -> Binding<AIProvider> {
        Binding {
            settings.selectedAIProvider
        } set: { provider in
            // 走统一入口：isAIConfigured 必须按新 provider 的 Keychain 现状重算。
            let configured = AIConfigurationCoordinator.switchProvider(
                to: provider,
                on: settings,
                using: configurationService
            )
            try? modelContext.save()
            apiKey = ""
            statusMessage = configured ? "已沿用该服务商在本机保存的 Key" : nil
            errorMessage = nil
            testResultMessage = nil
            loadMaskedKey()
        }
    }

    private func modelBinding(_ settings: UserSettings) -> Binding<String> {
        Binding {
            settings.selectedAIModel
        } set: { model in
            settings.selectedAIModel = model
            settings.updatedAt = Date()
        }
    }

    private func selectedOption(for settings: UserSettings) -> AIProviderOption? {
        configurationService.providerOptions.first { $0.provider == settings.selectedAIProvider }
    }

    private func loadMaskedKey() {
        guard let settings = currentSettings else {
            maskedKey = "—"
            return
        }
        let key = try? configurationService.readAPIKey(provider: settings.selectedAIProvider)
        maskedKey = configurationService.maskedKey(for: key)
    }

    private func saveConfiguration(_ settings: UserSettings) {
        do {
            try configurationService.saveAPIKey(apiKey, provider: settings.selectedAIProvider)
            settings.isAIConfigured = try configurationService.validateLocalConfiguration(settings: settings)
            settings.updatedAt = Date()
            statusMessage = settings.isAIConfigured ? "AI 配置已保存" : "API Key 至少需要 8 个字符"
            errorMessage = nil
            testResultMessage = nil
            apiKey = ""
            loadMaskedKey()
            HapticEngine.success()
        } catch {
            errorMessage = error.localizedDescription
            statusMessage = nil
        }
    }

    private func deleteKey(_ settings: UserSettings) {
        do {
            try configurationService.deleteAPIKey(provider: settings.selectedAIProvider)
            settings.isAIConfigured = false
            settings.updatedAt = Date()
            statusMessage = "已删除当前服务商的 Key"
            errorMessage = nil
            testResultMessage = nil
            loadMaskedKey()
            HapticEngine.warning()
        } catch {
            errorMessage = error.localizedDescription
            statusMessage = nil
        }
    }

    private func testConnection(_ settings: UserSettings) {
        isTesting = true
        testResultMessage = nil
        testFailed = false
        let service = ConfiguredAIService(settings: settings, configurationService: configurationService)
        Task {
            do {
                let reply = try await service.sendMessage("请只回复两个字：好的", history: [], context: nil)
                await MainActor.run {
                    testResultMessage = "连接成功：\(reply.prefix(40))"
                    testFailed = false
                    isTesting = false
                    HapticEngine.success()
                }
            } catch {
                await MainActor.run {
                    let msg = (error as? AIClientError)?.errorDescription ?? error.localizedDescription
                    testResultMessage = "连接失败：\(msg)"
                    testFailed = true
                    isTesting = false
                    HapticEngine.warning()
                }
            }
        }
    }
}

private struct AIAPIKeyLink: Identifiable {
    let provider: AIProvider
    let url: URL
    let note: String

    var id: String { provider.rawValue }
}
