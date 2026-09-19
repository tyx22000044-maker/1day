import SwiftUI
import SwiftData

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var settings: [UserSettings]
    @Query private var planItems: [PlanItem]
    @Query private var notes: [Note]

    @State private var appViewModel = AppViewModel()
    @State private var bootstrapSettings: UserSettings?
    @State private var bannerCenter = GlobalBannerCenter.shared

    private var currentSettings: UserSettings? {
        settings.first ?? bootstrapSettings
    }

    var body: some View {
        Group {
            if let s = currentSettings {
                if s.hasCompletedOnboarding {
                    mainTabView
                } else {
                    OnboardingView(settings: s)
                }
            } else {
                ZStack {
                    FamilyUI.pageBackground.ignoresSafeArea()
                    ProgressView("正在初始化 1Day...")
                }
            }
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            // 常驻、不可关闭：降级运行时必须让用户知道数据不会落盘。
            if case .inMemoryOnly(let reason) = AppContainer.health {
                StorageRiskBanner(planItems: planItems, notes: notes, settings: currentSettings, reason: reason)
            }
        }
        .onAppear {
            bootstrapSettings = bootstrapOrRepairSettings()
            applyFeedbackPreferences()
            revalidateAIConfiguration()
            if let s = settings.first {
                NotificationService.syncDefaultReminderTime(
                    hour: s.defaultReminderHour,
                    minute: s.defaultReminderMinute
                )
                NotificationService.syncInterfaceLanguage(s.language)
            }
        }
        .onChange(of: currentSettings?.isHapticsEnabled) { _, _ in
            applyFeedbackPreferences()
        }
        .onChange(of: currentSettings?.isSoundEffectsEnabled) { _, _ in
            applyFeedbackPreferences()
        }
        .preferredColorScheme(preferredColorScheme)
        .environment(\.locale, appLocale)
        .appSwitchStyle()
        .dismissKeyboardOnTap()
        .overlay(alignment: .top) {
            if let banner = bannerCenter.currentBanner {
                AppErrorBanner(
                    presentationID: banner.id,
                    title: banner.title,
                    message: banner.message,
                    tone: banner.tone
                ) {
                    bannerCenter.dismiss(id: banner.id)
                }
                // 换一条 banner 就换一份视图状态，别把上一条的收起计时带过来。
                .id(banner.id)
            }
        }
    }

    private var preferredColorScheme: ColorScheme? {
        switch currentSettings?.appearance ?? .system {
        case .system:
            return nil
        case .light:
            return .light
        case .dark:
            return .dark
        }
    }

    private var appLocale: Locale {
        switch currentSettings?.language ?? .system {
        case .english: return Locale(identifier: "en")
        case .zhHans: return Locale(identifier: "zh-Hans")
        case .system: return .current
        }
    }

    private var mainTabView: some View {
        ZStack(alignment: .bottom) {
            Group {
                switch appViewModel.selectedTab {
                case .today:
                    TodayView()
                case .plan:
                    PlanListView()
                case .ai:
                    AIChatView()
                case .notes:
                    NotesListView()
                case .settings:
                    SettingsView()
                }
            }
            .padding(.bottom, 64)

            AppTabBar(selectedTab: Bindable(appViewModel).selectedTab, language: currentSettings?.language ?? .system)
        }
        .background(FamilyUI.pageBackground)
        .environment(appViewModel)
    }

    /// 每次启动都过一遍：没有设置就建一条，历史上多出来的收敛成一条。
    /// 不能只在 `settings.isEmpty` 时调用——已经有多条的情况恰恰需要修复。
    private func bootstrapOrRepairSettings() -> UserSettings? {
        do {
            return try SettingsBootstrap.ensureSettings(in: modelContext)
        } catch {
            // 首启动就写不下时不能继续假装一切正常：用户接下来看到的
            // 「已完成设置」会在重启后消失，又会掉回 onboarding。
            AppLogger.dataError("初始化或修复设置失败: \(error.localizedDescription)")
            GlobalBannerCenter.shared.show(
                title: "无法保存初始设置",
                message: "存储空间可能不可用。完成引导后请先在「设置 → 数据管理」导出备份。",
                tone: .error
            )
            return nil
        }
    }

    private func applyFeedbackPreferences() {
        guard let currentSettings else { return }
        FeedbackPreferences.shared.apply(settings: currentSettings)
    }

    /// 让存量的「AI 已配置」标记重新对齐当前服务商的 Keychain 实际内容。
    private func revalidateAIConfiguration() {
        guard let currentSettings else { return }
        AIConfigurationCoordinator.revalidate(
            settings: currentSettings,
            using: LocalAIConfigurationService()
        )
    }
}

/// 持久化不可用时的常驻提示条。
///
/// 不可关闭：静默降级到内存容器会让用户以为任务已保存，重启后才发现全部丢失。
/// 除了警示，还提供唯一出路——把当前内存里的数据导成 JSON 备份，避免边用边丢。
struct StorageRiskBanner: View {
    let planItems: [PlanItem]
    let notes: [Note]
    let settings: UserSettings?
    let reason: String

    @State private var exportURL: URL?
    @State private var exportFailed = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(FamilyTypography.text(.subheadline, .bold))
                Text("存储不可用 · 本次修改不会保存")
                    .font(FamilyTypography.text(.subheadline, .bold))
                Spacer(minLength: 0)
            }

            Text("重启 App 可再次尝试打开数据库。在恢复正常前，请先导出当前数据，否则退出后会把任务和笔记一起丢掉。")
                .font(FamilyTypography.text(.caption))
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 10) {
                if let exportURL {
                    ShareLink(item: exportURL) {
                        Text("分享备份文件")
                            .font(FamilyTypography.text(.caption, .bold))
                    }
                } else {
                    Button {
                        exportBackup()
                    } label: {
                        Text("导出当前数据")
                            .font(FamilyTypography.text(.caption, .bold))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 7)
                            .background(FamilyUI.panelBackground)
                            .overlay(
                                RoundedRectangle(cornerRadius: FamilyUI.controlCornerRadius)
                                    .stroke(FamilyUI.panelBorder, lineWidth: 1)
                            )
                            .clipShape(RoundedRectangle(cornerRadius: FamilyUI.controlCornerRadius))
                    }
                    .buttonStyle(.plain)
                }

                if exportFailed {
                    Text("导出失败，请重试")
                        .font(FamilyTypography.text(.caption2))
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(FamilyUI.danger.opacity(0.12))
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(FamilyUI.danger)
                .frame(height: 2)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("存储不可用，本次修改不会被保存")
        .accessibilityHint(reason)
    }

    private func exportBackup() {
        do {
            exportURL = try SettingsDataCoordinator.exportBackup(
                planItems: planItems,
                notes: notes,
                settings: settings
            )
            exportFailed = false
        } catch {
            exportFailed = true
            AppLogger.dataError("降级模式导出备份失败: \(error.localizedDescription)")
        }
    }
}

struct DaySelectorView: View {
    @Binding var selectedDate: Date
    @Query private var settings: [UserSettings]
    @State private var isShowingDatePicker = false

    private var isToday: Bool { Calendar.current.isDateInToday(selectedDate) }
    private var language: AppLanguage { settings.first?.language ?? .system }
    private var locale: Locale { language.locale }

    var body: some View {
        HStack {
            Button {
                HapticEngine.tap()
                selectedDate = Calendar.current.date(byAdding: .day, value: -1, to: selectedDate) ?? selectedDate
            } label: {
                dayControlIcon("chevron.left")
            }

            Spacer()

            Button { isShowingDatePicker = true } label: {
                VStack(spacing: 2) {
                    Text(selectedDate.dayHeading(in: locale))
                        .font(FamilyTypography.text(.subheadline, .bold))
                        .minimumScaleFactor(0.8)
                        .monospacedDigit()
                    Text(AppSettingsLocalization.text(isToday ? "今天" : "归档", isToday ? "TODAY" : "ARCHIVE", language: language))
                        .font(FamilyTypography.fixed(10, .semibold))
                        .tracking(1)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.plain)
            .sheet(isPresented: $isShowingDatePicker) {
                NavigationStack {
                    DatePicker(
                        AppSettingsLocalization.text("选择日期", "Choose a date", language: language),
                        selection: $selectedDate,
                        in: ...Date.now,
                        displayedComponents: .date
                    )
                        .datePickerStyle(.graphical)
                        .padding()
                        .navigationTitle(AppSettingsLocalization.text("选择日期", "Choose a date", language: language))
                        .navigationBarTitleDisplayMode(.inline)
                        .toolbar {
                            ToolbarItem(placement: .confirmationAction) {
                                Button(AppSettingsLocalization.text("完成", "Done", language: language)) {
                                    isShowingDatePicker = false
                                }
                            }
                        }
                }
                .presentationDetents([.height(340)])
                .presentationDragIndicator(.visible)
            }

            Spacer()

            Button {
                guard let next = Calendar.current.date(byAdding: .day, value: 1, to: selectedDate) else { return }
                HapticEngine.tap()
                selectedDate = min(next, Calendar.current.startOfDay(for: .now))
            } label: {
                dayControlIcon("chevron.right", disabled: isToday)
            }
            .disabled(isToday)
        }
        .padding(.horizontal, 2)
        .frame(minHeight: 40)
    }

    private func dayControlIcon(_ name: String, disabled: Bool = false) -> some View {
        RoundedRectangle(cornerRadius: FamilyUI.controlCornerRadius)
            .fill(FamilyUI.panelMutedBackground)
            .overlay(RoundedRectangle(cornerRadius: FamilyUI.controlCornerRadius).stroke(FamilyUI.panelBorder, lineWidth: 1))
            .frame(width: 40, height: 40)
            .overlay(Image(systemName: name).font(.body.weight(.semibold)).foregroundStyle(disabled ? FamilyUI.subtleText : FamilyUI.ink))
    }
}

private struct AppTabBar: View {
    @Binding var selectedTab: AppTab
    let language: AppLanguage

    var body: some View {
        HStack(spacing: 0) {
            ForEach(AppTab.allCases) { tab in
                Button {
                    HapticEngine.tap()
                    withAnimation(.snappy(duration: 0.22)) {
                        selectedTab = tab
                    }
                } label: {
                    VStack(spacing: 4) {
                        if tab == .ai {
                            // AI tab: solid accent block mark, per the Swiss Ledger mockups
                            Image(systemName: tab.systemImage)
                                .font(.system(size: 12, weight: .bold))
                                .frame(width: 22, height: 22)
                                .background(FamilyUI.accent)
                                .foregroundStyle(FamilyUI.paper)
                        } else {
                            Image(systemName: tab.systemImage)
                                .font(.system(size: 16, weight: .semibold))
                                .frame(height: 17)
                                .foregroundStyle(selectedTab == tab ? FamilyUI.ink : FamilyUI.subtleText)
                        }
                        Text(tab.title(for: language))
                            .font(FamilyTypography.fixed(9, .bold))
                            .tracking(0.5)
                            .foregroundStyle(selectedTab == tab ? FamilyUI.ink : FamilyUI.subtleText)
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 46)
                    .accessibilityAddTraits(selectedTab == tab ? .isSelected : [])
                    .overlay(alignment: .top) {
                        if selectedTab == tab {
                            Rectangle()
                                .fill(tab == .ai ? FamilyUI.accent : FamilyUI.ink)
                                .frame(height: 2)
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .background(
            Rectangle()
                .fill(FamilyUI.panelBackground)
                .overlay(alignment: .top) {
                    Rectangle()
                        .fill(FamilyUI.hairlineStrong)
                        .frame(height: 1)
                }
                .ignoresSafeArea(edges: .bottom)
        )
    }
}
