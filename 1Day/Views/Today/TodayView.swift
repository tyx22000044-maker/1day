import SwiftUI
import SwiftData

struct TodayView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(AppViewModel.self) private var appViewModel
    @Query(sort: [SortDescriptor(\PlanItem.createdAt, order: .reverse)])
    private var allItems: [PlanItem]
    @Query private var settings: [UserSettings]

    @State private var quickInputText = ""
    @State private var isShowingCreateSheet = false
    @State private var isCompletedExpanded = true
    @State private var isProgressExpanded = true
    @State private var scheduleLaterItem: PlanItem?
    @State private var scheduleLaterTitle = ""
    @State private var pendingTaskDelete: PlanItem?
    @State private var undoTaskSnapshot: PlanItemBackup?
    @State private var undoTaskTitle = ""
    @State private var undoWindowTask: Task<Void, Never>?
    @FocusState private var isInputFocused: Bool

    /// Single pass over allItems producing the three today-relevant buckets at once,
    /// instead of overdueItems/todayPending/todayCompleted each independently
    /// re-scanning and re-sorting the full list on every access.
    private struct TodaySnapshot {
        let overdue: [PlanItem]
        let pending: [PlanItem]
        let completed: [PlanItem]

        var completedCount: Int { completed.count }
        var totalCount: Int { pending.count + completed.count }
    }

    private func makeSnapshot(asOf date: Date) -> TodaySnapshot {
        var overdue: [PlanItem] = []
        var pending: [PlanItem] = []
        var completed: [PlanItem] = []

        for item in allItems {
            if item.isOverdue(asOf: date) {
                overdue.append(item)
            } else if item.isDue(on: date) {
                if item.isCompleted {
                    completed.append(item)
                } else {
                    pending.append(item)
                }
            }
        }

        overdue.sort { lhs, rhs in
            if let ld = lhs.dueDate, let rd = rhs.dueDate, !Calendar.current.isDate(ld, inSameDayAs: rd) {
                return ld < rd
            }
            return lhs.priority.sortOrder < rhs.priority.sortOrder
        }

        pending.sort { lhs, rhs in
            let lTime = lhs.reminderTime.map { Calendar.current.dateComponents([.hour, .minute], from: $0) }
            let rTime = rhs.reminderTime.map { Calendar.current.dateComponents([.hour, .minute], from: $0) }
            let lMinutes = lTime.flatMap { c in c.hour.flatMap { h in c.minute.map { h * 60 + $0 } } }
            let rMinutes = rTime.flatMap { c in c.hour.flatMap { h in c.minute.map { h * 60 + $0 } } }
            switch (lMinutes, rMinutes) {
            case let (l?, r?): return l != r ? l < r : lhs.priority.sortOrder < rhs.priority.sortOrder
            case (nil, _?): return false
            case (_?, nil): return true
            case (nil, nil): return lhs.priority.sortOrder < rhs.priority.sortOrder
            }
        }

        return TodaySnapshot(overdue: overdue, pending: pending, completed: completed)
    }

    private var selectedDate: Date { appViewModel.selectedDate }
    private var language: AppLanguage { settings.first?.language ?? .system }
    private var locale: Locale { language.locale }
    private var selectedDateTitle: String {
        if Calendar.current.isDateInToday(selectedDate) { return localized(.navToday) }
        if Calendar.current.isDateInYesterday(selectedDate) { return localized("昨天", "Yesterday") }
        return selectedDate.dayHeading(in: locale)
    }

    private func localized(_ chinese: String, _ english: String) -> String {
        AppSettingsLocalization.text(chinese, english, language: language)
    }

    private func localized(_ key: AppText.Key) -> String {
        AppText.string(key, language: language)
    }

    private func countLabel(_ count: Int, key: AppText.Key) -> String {
        "\(count) " + localized(key)
    }

    var body: some View {
        let snapshot = makeSnapshot(asOf: selectedDate)
        return NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: AppSpacing.sectionSpacing) {
                    DaySelectorView(selectedDate: Binding(
                        get: { appViewModel.selectedDate },
                        set: { appViewModel.selectedDate = min($0, Calendar.current.startOfDay(for: .now)) }
                    ))
                    heroCard(snapshot)

                    quickInputPanel

                    if !snapshot.overdue.isEmpty {
                        overdueSection(snapshot)
                    }
                    if !snapshot.pending.isEmpty {
                        todaySection(snapshot)
                    }
                    if !snapshot.completed.isEmpty {
                        completedSection(snapshot)
                    }
                    if snapshot.overdue.isEmpty && snapshot.pending.isEmpty && snapshot.completed.isEmpty {
                        AppEmptyStateView(
                            icon: "checkmark.circle",
                            title: "\(selectedDateTitle)\(localized(.emptyTodayTitle))",
                            subtitle: localized(.emptyTodaySubtitle),
                            buttonTitle: localized(.createTask)
                        ) {
                            isShowingCreateSheet = true
                        }
                    }
                }
                .padding(.horizontal, AppSpacing.pageHorizontal)
                .padding(.bottom, AppSpacing.pageBottom)
                .padding(.top, 4)
            }
            .scrollIndicators(.hidden)
            .background(FamilyUI.pageBackground.ignoresSafeArea())
            .navigationTitle(selectedDateTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    FamilyAddButton {
                        isShowingCreateSheet = true
                    }
                }
            }
            .sheet(isPresented: $isShowingCreateSheet) {
                TaskEditorSheet(
                    defaultDueDate: selectedDate,
                    defaultReminderTime: settings.first?.defaultReminderTime ?? .fallbackReminder
                )
            }
            .overlay(alignment: .bottom) {
                if let snapshot = undoTaskSnapshot {
                    UndoDeleteToast(label: "已删除任务", title: undoTaskTitle) {
                        undoTaskDelete(snapshot)
                    }
                    .padding(.bottom, 16)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                } else if scheduleLaterItem != nil {
                    ScheduleLaterToast(title: scheduleLaterTitle, language: language) {
                        if let item = scheduleLaterItem {
                            PlanItemService.moveToUnscheduled(item)
                        }
                        scheduleLaterItem = nil
                    }
                    .padding(.bottom, 16)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .animation(.easeInOut(duration: 0.25), value: scheduleLaterItem != nil)
            .animation(.easeInOut(duration: 0.25), value: undoTaskSnapshot != nil)
            .confirmationDialog(
                "删除这条任务？",
                isPresented: Binding(
                    get: { pendingTaskDelete != nil },
                    set: { if !$0 { pendingTaskDelete = nil } }
                ),
                titleVisibility: .visible
            ) {
                Button("删除", role: .destructive) { confirmTaskDelete() }
                Button("取消", role: .cancel) { pendingTaskDelete = nil }
            } message: {
                Text("删除后 5 秒内可以在列表底部撤销，超时后就只能从备份恢复了。")
            }
        }
    }

    // MARK: - Hero Card

    private func heroCard(_ snapshot: TodaySnapshot) -> some View {
        SystemPanel {
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 2) {
                            Text(localized(.sectionCompletedToday))
                            .font(FamilyTypography.text(.caption))
                            .tracking(0.6)
                            .foregroundStyle(.secondary)
                        HStack(alignment: .firstTextBaseline, spacing: 2) {
                            Text("\(snapshot.completedCount)")
                                .font(FamilyTypography.heroNumber)
                                .monospacedDigit()
                                .foregroundStyle(.primary)
                            Text("/\(snapshot.totalCount)")
                                .font(FamilyTypography.text(.headline, .semibold))
                                .monospacedDigit()
                                .foregroundStyle(.secondary)
                        }
                    }

                    Spacer()

                    VStack(alignment: .trailing, spacing: 2) {
                            Text(localized(.sectionCompletedThisWeek))
                            .font(FamilyTypography.text(.caption))
                            .tracking(0.6)
                            .foregroundStyle(.secondary)
                        Text("\(weeklyCompletedCount)")
                            .font(FamilyTypography.text(.title2, .bold))
                            .monospacedDigit()
                            .foregroundStyle(FamilyUI.accent)
                    }
                }

                Button {
                    withAnimation(.easeInOut(duration: 0.22)) { isProgressExpanded.toggle() }
                    HapticEngine.tap()
                } label: {
                    HStack(spacing: 4) {
                        Text(isProgressExpanded ? localized(.trendCollapse) : localized(.trendExpand))
                            .font(FamilyTypography.text(.caption, .semibold))
                        Image(systemName: isProgressExpanded ? "chevron.up" : "chevron.down")
                            .font(.caption2)
                    }
                    .foregroundStyle(FamilyUI.accent)
                }
                .buttonStyle(.plain)

                if isProgressExpanded {
                    weekTrendChart
                }
            }
        }
    }

    /// 近 7 天完成趋势的一格。今天单独标记，而不是靠标签文字比对 ——
    /// 英文里周二的 T 和今天的 T 会撞在一起。
    private struct TrendDay: Identifiable {
        let id: Int
        let label: String
        let count: Int
        let isToday: Bool
    }

    private var weekTrendChart: some View {
        let data = last7DaysCompletions()
        let maxCount = max(data.map(\.count).max() ?? 1, 1)
        return HStack(alignment: .bottom, spacing: 6) {
            ForEach(data) { day in
                VStack(spacing: 3) {
                    if day.count > 0 {
                        Text("\(day.count)")
                            .font(FamilyTypography.fixed(9))
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    } else {
                        Text(" ")
                            .font(FamilyTypography.fixed(9))
                    }
                    Rectangle()
                        .fill(day.isToday ? FamilyUI.accent : FamilyUI.panelMutedBackground)
                        .frame(height: max(CGFloat(day.count) / CGFloat(maxCount) * 56, 4))
                    Text(day.label)
                        .font(FamilyTypography.fixed(10))
                        .foregroundStyle(day.isToday ? FamilyUI.accent : Color.secondary)
                        .fontWeight(day.isToday ? .semibold : .regular)
                }
                .frame(maxWidth: .infinity)
            }
        }
        .frame(height: 84)
        .padding(.horizontal, 4)
        .padding(.top, 4)
    }

    // MARK: - Quick Input

    private var quickInputPanel: some View {
        SystemPanel {
            HStack(spacing: 10) {
                TextField(localized(.quickInputPlaceholder), text: $quickInputText)
                    .focused($isInputFocused)
                    .onSubmit { createQuickTask() }

                if !quickInputText.isEmpty {
                    Menu {
                        Button {
                            createQuickTask()
                        } label: {
                            Label(localized(.groupToday), systemImage: "sun.max")
                        }
                        Button {
                            createQuickTask(dueDate: selectedDate.shiftedDays(1))
                        } label: {
                            Label(localized(.groupTomorrow), systemImage: "sunrise")
                        }
                        Button {
                            createQuickTask(isUnscheduled: true)
                        } label: {
                            Label(localized(.scheduleLater), systemImage: "tray")
                        }
                    } label: {
                        Image(systemName: "arrow.up.circle.fill")
                            .font(.title3)
                            .foregroundStyle(FamilyUI.accent)
                    } primaryAction: {
                        createQuickTask()
                    }
                }
            }
        }
    }

    // MARK: - Sections

    private func overdueSection(_ snapshot: TodaySnapshot) -> some View {
        SystemPanel(title: localized(.groupOverdue), detail: countLabel(snapshot.overdue.count, key: .taskCountSuffix)) {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(snapshot.overdue.enumerated()), id: \.element.id) { index, item in
                    taskRow(item)
                    if index < snapshot.overdue.count - 1 {
                        SystemPanelDivider()
                    }
                }
            }
        }
    }

    private func todaySection(_ snapshot: TodaySnapshot) -> some View {
        SystemPanel(title: localized(.groupToday), detail: countLabel(snapshot.pending.count, key: .taskCountSuffix)) {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(snapshot.pending.enumerated()), id: \.element.id) { index, item in
                    taskRow(item)
                    if index < snapshot.pending.count - 1 {
                        SystemPanelDivider()
                    }
                }
            }
        }
    }

    private func completedSection(_ snapshot: TodaySnapshot) -> some View {
        SystemPanel {
            Button {
                withAnimation(.easeInOut(duration: 0.22)) { isCompletedExpanded.toggle() }
                HapticEngine.tap()
            } label: {
                HStack(spacing: 4) {
                    Text("\(localized(.sectionCompleted)) (\(snapshot.completedCount))")
                        .font(FamilyTypography.text(.subheadline, .semibold))
                        .monospacedDigit()
                    Spacer()
                    Image(systemName: isCompletedExpanded ? "chevron.down" : "chevron.right")
                        .font(.caption2)
                }
                .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)

            if isCompletedExpanded {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(snapshot.completed.enumerated()), id: \.element.id) { index, item in
                        SystemPanelDivider()
                        taskRow(item)
                    }
                }
            }
        }
    }

    private func taskRow(_ item: PlanItem) -> some View {
        NavigationLink {
            TaskDetailView(item: item)
        } label: {
            TaskRow(item: item, asOf: selectedDate, language: language)
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button {
                withAnimation {
                    PlanItemService.toggleCompletion(item)
                }
                HapticEngine.success()
            } label: {
                Label(item.isCompleted ? localized(.rowUncomplete) : localized(.rowComplete),
                      systemImage: item.isCompleted ? "circle" : "checkmark.circle.fill")
            }
            if item.isUnscheduled == false && item.dueDate != nil {
                Button {
                    withAnimation {
                        PlanItemService.moveToUnscheduled(item)
                    }
                } label: {
                    Label(localized(.rowMoveToUnscheduled), systemImage: "tray")
                }
            }
            Button(role: .destructive) {
                requestTaskDelete(item)
            } label: {
                Label(localized(.delete), systemImage: "trash")
            }
        }
    }

    // MARK: - Actions

    /// 长按菜单里的删除只负责「问一句」，真正动手在 confirmTaskDelete。
    private func requestTaskDelete(_ item: PlanItem) {
        pendingTaskDelete = item
        HapticEngine.warning()
    }

    private func confirmTaskDelete() {
        guard let item = pendingTaskDelete else { return }
        pendingTaskDelete = nil
        let snapshot = DeletionCoordinator.snapshot(item)
        guard DeletionCoordinator.delete(item, in: modelContext) else { return }
        undoTaskSnapshot = snapshot
        undoTaskTitle = snapshot.title
        startUndoWindow()
    }

    private func undoTaskDelete(_ snapshot: PlanItemBackup) {
        undoWindowTask?.cancel()
        undoWindowTask = nil
        undoTaskSnapshot = nil
        HapticEngine.tap()
        _ = DeletionCoordinator.restore(snapshot, in: modelContext)
    }

    private func startUndoWindow() {
        undoWindowTask?.cancel()
        undoWindowTask = Task {
            try? await Task.sleep(nanoseconds: 5_000_000_000)
            guard !Task.isCancelled else { return }
            await MainActor.run {
                withAnimation(.easeInOut(duration: 0.25)) { undoTaskSnapshot = nil }
            }
        }
    }

    private func createQuickTask(dueDate: Date? = nil, isUnscheduled: Bool = false) {
        let text = quickInputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        let effectiveDueDate = isUnscheduled ? nil : (dueDate ?? selectedDate)
        let item = PlanItemService.createTask(
            title: text,
            dueDate: effectiveDueDate,
            in: modelContext
        )
        quickInputText = ""
        HapticEngine.success()

        // Show "稍后安排" toast only when a date was assigned (let user move to unscheduled)
        guard effectiveDueDate != nil else { return }
        scheduleLaterItem = item
        scheduleLaterTitle = text
        Task {
            try? await Task.sleep(nanoseconds: 4_000_000_000)
            await MainActor.run {
                withAnimation(.easeInOut(duration: 0.25)) { scheduleLaterItem = nil }
            }
        }
    }

    private var weeklyCompletedCount: Int {
        let calendar = Calendar.current
        let startOfWeek = calendar.dateInterval(of: .weekOfYear, for: .now)?.start ?? .now
        return allItems.filter { $0.isCompleted && ($0.completedAt ?? .distantPast) >= startOfWeek }.count
    }

    /// 星期标签跟着界面语言：中文用单字（日一二三四五六），
    /// 其他语言走 Calendar 的 short 符号，避免切英文还是看到「三」。
    private var calendarWeekdaySymbols: [String] {
        let locale = language.locale
        guard locale.language.languageCode?.identifier == "en" else {
            return ["日", "一", "二", "三", "四", "五", "六"]
        }
        var calendar = Calendar.current
        calendar.locale = locale
        return calendar.shortWeekdaySymbols
    }

    private func last7DaysCompletions() -> [TrendDay] {
        let cal = Calendar.current
        let symbols = calendarWeekdaySymbols
        return (0..<7).reversed().compactMap { offsetFromToday -> TrendDay? in
            let daysAgo = offsetFromToday
            guard let date = cal.date(byAdding: .day, value: -daysAgo, to: .now) else { return nil }
            let start = cal.startOfDay(for: date)
            guard let end = cal.date(byAdding: .day, value: 1, to: start) else { return nil }
            let count = allItems.filter { item in
                guard item.isCompleted, let at = item.completedAt else { return false }
                return at >= start && at < end
            }.count
            let weekday = cal.component(.weekday, from: date)
            let label = symbols.indices.contains(weekday - 1) ? symbols[weekday - 1] : "?"
            return TrendDay(id: daysAgo, label: label, count: count, isToday: daysAgo == 0)
        }
    }
}

// MARK: - Supporting Views

private struct TaskRow: View {
    let item: PlanItem
    let asOf: Date
    let language: AppLanguage

    var body: some View {
        FamilyTaskRow(item: item, asOf: asOf, language: language)
    }
}

private struct ScheduleLaterToast: View {
    let title: String
    let language: AppLanguage
    let onScheduleLater: () -> Void

    private func localized(_ key: AppText.Key) -> String {
        AppText.string(key, language: language)
    }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(FamilyUI.success)
            Text("\(localized(.addedToToday))：\(title)")
                .font(FamilyTypography.text(.subheadline))
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            Button(localized(.scheduleLater)) {
                onScheduleLater()
            }
            .font(FamilyTypography.text(.subheadline, .semibold))
            .foregroundStyle(FamilyUI.accent)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(FamilyUI.panelBackground)
        .overlay(
            RoundedRectangle(cornerRadius: FamilyUI.panelCornerRadius)
                .stroke(FamilyUI.panelBorder, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: FamilyUI.panelCornerRadius))
        .padding(.horizontal, 16)
    }
}
