import SwiftUI
import SwiftData

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var settings: [UserSettings]

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
        .onAppear {
            bootstrapIfNeeded()
            applyFeedbackPreferences()
            if let s = settings.first {
                NotificationService.syncDefaultReminderTime(
                    hour: s.defaultReminderHour,
                    minute: s.defaultReminderMinute
                )
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
                AppErrorBanner(title: banner.title, message: banner.message, tone: banner.tone) {
                    bannerCenter.dismiss()
                }
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

            AppTabBar(selectedTab: Bindable(appViewModel).selectedTab)
        }
        .background(FamilyUI.pageBackground)
        .environment(appViewModel)
    }

    private func bootstrapIfNeeded() {
        guard settings.isEmpty, bootstrapSettings == nil else { return }
        let newSettings = UserSettings()
        modelContext.insert(newSettings)
        bootstrapSettings = newSettings
    }

    private func applyFeedbackPreferences() {
        guard let currentSettings else { return }
        FeedbackPreferences.shared.apply(settings: currentSettings)
    }
}

struct DaySelectorView: View {
    @Binding var selectedDate: Date
    @State private var isShowingDatePicker = false

    private var isToday: Bool { Calendar.current.isDateInToday(selectedDate) }

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
                    Text(selectedDate.formatted(.dateTime.month().day().weekday(.wide)))
                        .font(.subheadline.weight(.bold))
                    Text(isToday ? "TODAY" : "ARCHIVE")
                        .font(.system(size: 10, weight: .semibold, design: .rounded))
                        .tracking(1)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.plain)
            .sheet(isPresented: $isShowingDatePicker) {
                NavigationStack {
                    DatePicker("选择日期", selection: $selectedDate, in: ...Date.now, displayedComponents: .date)
                        .datePickerStyle(.graphical)
                        .padding()
                        .navigationTitle("选择日期")
                        .navigationBarTitleDisplayMode(.inline)
                        .toolbar {
                            ToolbarItem(placement: .confirmationAction) {
                                Button("完成") { isShowingDatePicker = false }
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
            .overlay(Image(systemName: name).font(.body.weight(.semibold)).foregroundStyle(disabled ? Color(.systemGray3) : .primary))
    }
}

private struct AppTabBar: View {
    @Binding var selectedTab: AppTab

    var body: some View {
        HStack(spacing: 6) {
            ForEach(AppTab.allCases) { tab in
                Button {
                    HapticEngine.tap()
                    withAnimation(.snappy(duration: 0.22)) {
                        selectedTab = tab
                    }
                } label: {
                    VStack(spacing: 4) {
                        Image(systemName: tab.systemImage)
                            .font(.system(size: 16, weight: .bold, design: .rounded))
                            .frame(height: 17)
                        Text(tab.title)
                            .font(.system(size: 10, weight: .bold, design: .rounded))
                    }
                    .foregroundStyle(selectedTab == tab ? .white : .secondary)
                    .frame(maxWidth: .infinity)
                    .frame(height: 46)
                    .background(selectedTab == tab ? FamilyUI.accent : FamilyUI.panelMutedBackground)
                    .overlay(
                        RoundedRectangle(cornerRadius: FamilyUI.controlCornerRadius)
                            .stroke(selectedTab == tab ? Color.black.opacity(0.18) : FamilyUI.panelBorder, lineWidth: 1)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: FamilyUI.controlCornerRadius))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 10)
        .padding(.top, 8)
        .padding(.bottom, 6)
        .background(
            Rectangle()
                .fill(FamilyUI.panelBackground)
                .overlay(alignment: .top) {
                    Rectangle()
                        .fill(FamilyUI.panelBorder)
                        .frame(height: 1)
                }
                .ignoresSafeArea(edges: .bottom)
        )
    }
}
