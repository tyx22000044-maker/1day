import SwiftUI
import SwiftData

struct PlanListView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(AppViewModel.self) private var appViewModel
    @Query(sort: [SortDescriptor(\PlanItem.createdAt, order: .reverse)])
    private var allItems: [PlanItem]
    @Query private var settings: [UserSettings]

    @State private var isShowingCreateSheet = false
    @State private var schedulingItem: PlanItem?
    @State private var pendingTaskDelete: PlanItem?
    @State private var undoTaskSnapshot: PlanItemBackup?
    @State private var undoTaskTitle = ""
    @State private var undoWindowTask: Task<Void, Never>?

    private var selectedDate: Date {
        Calendar.current.startOfDay(for: appViewModel.selectedDate)
    }

    private var language: AppLanguage { settings.first?.language ?? .system }

    private func localized(_ key: AppText.Key) -> String {
        AppText.string(key, language: language)
    }

    private func countLabel(_ count: Int, key: AppText.Key) -> String {
        "\(count) " + localized(key)
    }

    private var groupedItems: [(String, [PlanItem])] {
        let calendar = Calendar.current
        let today = selectedDate
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: today)!
        let endOfWeek = calendar.dateInterval(of: .weekOfYear, for: selectedDate)?.end ?? today

        // Single pass over allItems: every task is assigned directly to exactly
        // one bucket instead of re-scanning the pending list six times.
        var unscheduled: [PlanItem] = []
        var overdue: [PlanItem] = []
        var todayItems: [PlanItem] = []
        var tomorrowItems: [PlanItem] = []
        var thisWeek: [PlanItem] = []
        var later: [PlanItem] = []

        for item in allItems where !item.isCompleted {
            if item.isUnscheduled {
                unscheduled.append(item)
            } else if item.isOverdue(asOf: selectedDate) {
                overdue.append(item)
            } else if item.isDue(on: selectedDate) {
                todayItems.append(item)
            } else if let dueDate = item.dueDate, calendar.isDate(dueDate, inSameDayAs: tomorrow) {
                tomorrowItems.append(item)
            } else if let dueDate = item.dueDate, dueDate < endOfWeek {
                thisWeek.append(item)
            } else {
                later.append(item)
            }
        }

        func sorted(_ items: [PlanItem]) -> [PlanItem] {
            items.sorted { lhs, rhs in
                if let ld = lhs.dueDate, let rd = rhs.dueDate, !Calendar.current.isDate(ld, inSameDayAs: rd) {
                    return ld < rd
                }
                return lhs.priority.sortOrder < rhs.priority.sortOrder
            }
        }

        var groups: [(String, [PlanItem])] = []
        if !unscheduled.isEmpty { groups.append((localized(.groupUnscheduled), sorted(unscheduled))) }
        if !overdue.isEmpty { groups.append((localized(.groupOverdue), sorted(overdue))) }
        if !todayItems.isEmpty { groups.append((localized(.groupToday), sorted(todayItems))) }
        if !tomorrowItems.isEmpty { groups.append((localized(.groupTomorrow), sorted(tomorrowItems))) }
        if !thisWeek.isEmpty { groups.append((localized(.groupThisWeek), sorted(thisWeek))) }
        if !later.isEmpty { groups.append((localized(.groupLater), sorted(later))) }
        return groups
    }

    var body: some View {
        let groups = groupedItems
        return NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: AppSpacing.sectionSpacing) {
                    if groups.isEmpty {
                        AppEmptyStateView(
                            icon: "list.bullet",
                            title: localized(.emptyPlanTitle),
                            subtitle: localized(.emptyPlanSubtitle),
                            buttonTitle: localized(.createTask)
                        ) {
                            isShowingCreateSheet = true
                        }
                        .padding(.top, 24)
                    }

                    ForEach(groups, id: \.0) { group in
                        SystemPanel(title: group.0, detail: countLabel(group.1.count, key: .taskCountSuffix)) {
                            VStack(alignment: .leading, spacing: 0) {
                                ForEach(Array(group.1.enumerated()), id: \.element.id) { index, item in
                                    NavigationLink {
                                        TaskDetailView(item: item)
                                    } label: {
                        PlanItemRow(item: item, asOf: selectedDate, language: language)
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
                                        if item.isUnscheduled {
                                            Button {
                                                schedulingItem = item
                                            } label: {
                                                Label(localized(.rowSetDate), systemImage: "calendar.badge.plus")
                                            }
                                        }
                                        Button(role: .destructive) {
                                            requestTaskDelete(item)
                                        } label: {
                                            Label(localized(.delete), systemImage: "trash")
                                        }
                                    }
                                    if index < group.1.count - 1 {
                                        SystemPanelDivider()
                                    }
                                }
                            }
                        }
                    }
                }
                .padding(.horizontal, AppSpacing.pageHorizontal)
                .padding(.bottom, AppSpacing.pageBottom)
                .padding(.top, 4)
            }
            .scrollIndicators(.hidden)
            .background(FamilyUI.pageBackground.ignoresSafeArea())
            .safeAreaInset(edge: .top) {
                DaySelectorView(selectedDate: Binding(
                    get: { appViewModel.selectedDate },
                    set: { appViewModel.selectedDate = $0 }
                ))
                .padding(.horizontal, AppSpacing.pageHorizontal)
                .padding(.top, 6)
                .background(FamilyUI.pageBackground)
            }
            .navigationTitle(localized(.navPlan))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    FamilyAddButton {
                        isShowingCreateSheet = true
                    }
                }
            }
            .sheet(isPresented: $isShowingCreateSheet) {
                TaskEditorSheet(defaultDueDate: nil)
            }
            .sheet(item: $schedulingItem) { item in
                QuickScheduleSheet(item: item)
            }
            .overlay(alignment: .bottom) {
                if let snapshot = undoTaskSnapshot {
                    UndoDeleteToast(label: "已删除任务", title: undoTaskTitle) {
                        undoTaskDelete(snapshot)
                    }
                    .padding(.bottom, 16)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
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

    /// 长按菜单的删除只负责问一句，真删除在 confirmTaskDelete。
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
}

private struct PlanItemRow: View {
    let item: PlanItem
    let asOf: Date
    let language: AppLanguage

    var body: some View {
        FamilyTaskRow(item: item, asOf: asOf, showsScheduleDetails: true, language: language)
    }
}

private struct QuickScheduleSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Query private var settings: [UserSettings]
    @Bindable var item: PlanItem
    @State private var selectedDate = Date()

    private var language: AppLanguage { settings.first?.language ?? .system }

    private func localized(_ zh: String, _ en: String) -> String {
        AppSettingsLocalization.text(zh, en, language: language)
    }

    private func localized(_ key: AppText.Key) -> String {
        AppText.string(key, language: language)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: AppSpacing.sectionSpacing) {
                    SystemPanel(title: localized("为任务选择日期", "Pick a date"), detail: item.title) {
                        DatePicker("日期", selection: $selectedDate, displayedComponents: .date)
                            .datePickerStyle(.graphical)
                            .tint(FamilyUI.accent)
                            .frame(maxWidth: .infinity)
                    }

                    SystemPanel(title: localized("快捷日期", "Quick dates")) {
                        VStack(alignment: .leading, spacing: 0) {
                            ForEach(Array(quickDates.enumerated()), id: \.offset) { index, entry in
                                let label = entry.0
                                let date = entry.1
                                Button {
                                    selectedDate = date
                                    HapticEngine.tap()
                                } label: {
                                    HStack {
                                        Text(label)
                                        Spacer()
                                        Text(date.formatted(.dateTime.month().day().weekday(.abbreviated)))
                                            .foregroundStyle(.secondary)
                                            .font(.caption)
                                        if Calendar.current.isDate(selectedDate, inSameDayAs: date) {
                                            Image(systemName: "checkmark")
                                                .foregroundStyle(FamilyUI.accent)
                                                .font(.caption.weight(.bold))
                                        }
                                    }
                                    .padding(.vertical, 8)
                                }
                                .foregroundStyle(.primary)
                                .buttonStyle(.plain)
                                if index < quickDates.count - 1 {
                                    SystemPanelDivider()
                                }
                            }
                        }
                    }
                }
                .padding(.horizontal, AppSpacing.pageHorizontal)
                .padding(.vertical, 16)
            }
            .background(FamilyUI.pageBackground.ignoresSafeArea())
            .navigationTitle("设定日期")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(localized(.cancel)) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(localized("确定", "Done")) {
                                                PlanItemService.updateSchedule(for: item, dueDate: selectedDate)
                        HapticEngine.success()
                        dismiss()
                    }
                }
            }
        }
        .presentationDetents([.medium])
    }

    private var quickDates: [(String, Date)] {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        return [
            (localized("今天", "Today"), today),
            (localized("明天", "Tomorrow"), cal.date(byAdding: .day, value: 1, to: today) ?? today.addingTimeInterval(86_400)),
            (localized("后天", "In 2 days"), cal.date(byAdding: .day, value: 2, to: today) ?? today.addingTimeInterval(172_800)),
            (localized("下周一", "Next Monday"), nextWeekday(2, from: today))
        ]
    }

    private func nextWeekday(_ weekday: Int, from start: Date) -> Date {
        let cal = Calendar.current
        let current = cal.component(.weekday, from: start)
        let daysToAdd = ((weekday - current + 7) % 7).nonzero(fallback: 7)
        return cal.date(byAdding: .day, value: daysToAdd, to: start)!
    }
}

private extension Int {
    func nonzero(fallback: Int) -> Int { self == 0 ? fallback : self }
}

struct TaskEditorSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query private var settings: [UserSettings]

    private var language: AppLanguage { settings.first?.language ?? .system }

    private func localized(_ key: AppText.Key) -> String {
        AppText.string(key, language: language)
    }

    let defaultDueDate: Date?

    @State private var title = ""
    @State private var notes = ""
    @State private var hasDueDate: Bool
    @State private var dueDate: Date
    @State private var hasReminder = false
    @State private var reminderTime: Date
    @State private var priority: Priority = .none
    @FocusState private var isTitleFocused: Bool

    private var trimmedTitle: String {
        title.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    init(defaultDueDate: Date?) {
        self.defaultDueDate = defaultDueDate
        _hasDueDate = State(initialValue: defaultDueDate != nil)
        _dueDate = State(initialValue: defaultDueDate ?? Date())
        _reminderTime = State(initialValue: Calendar.current.date(bySettingHour: 9, minute: 0, second: 0, of: Date()) ?? Date())
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: AppSpacing.sectionSpacing) {
                    SystemPanel(title: AppSettingsLocalization.text("任务", "Task", language: language), detail: AppSettingsLocalization.text("先写下要完成的事情", "Start with what needs doing", language: language)) {
                        VStack(alignment: .leading, spacing: 12) {
                            TextField(AppSettingsLocalization.text("任务标题", "Task title", language: language), text: $title)
                                .focused($isTitleFocused)
                                .textFieldStyle(.plain)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 10)
                                .background(FamilyUI.panelMutedBackground)
                                .overlay(RoundedRectangle(cornerRadius: FamilyUI.controlCornerRadius).stroke(FamilyUI.panelBorder, lineWidth: 1))
                                .clipShape(RoundedRectangle(cornerRadius: FamilyUI.controlCornerRadius))

                            ZStack(alignment: .topLeading) {
                                TextEditor(text: $notes)
                                    .frame(minHeight: 112)
                                    .scrollContentBackground(.hidden)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 6)
                                if notes.isEmpty {
                                    Text(AppSettingsLocalization.text("添加备注…", "Add notes…", language: language))
                                        .foregroundStyle(.tertiary)
                                        .padding(.horizontal, 13)
                                        .padding(.vertical, 13)
                                        .allowsHitTesting(false)
                                }
                            }
                            .background(FamilyUI.panelMutedBackground)
                            .overlay(RoundedRectangle(cornerRadius: FamilyUI.controlCornerRadius).stroke(FamilyUI.panelBorder, lineWidth: 1))
                            .clipShape(RoundedRectangle(cornerRadius: FamilyUI.controlCornerRadius))
                        }
                    }

                    SystemPanel(title: AppSettingsLocalization.text("安排", "Schedule", language: language)) {
                        VStack(alignment: .leading, spacing: 0) {
                            Toggle(isOn: $hasDueDate) {
                                AppSettingsRow(icon: "calendar", title: AppSettingsLocalization.text("设置日期", "Set a date", language: language), subtitle: AppSettingsLocalization.text("为任务安排具体日期", "Give this task a day", language: language))
                            }
                            .tint(FamilyUI.accent)

                            if hasDueDate {
                                SystemPanelDivider()
                                DatePicker("日期", selection: $dueDate, displayedComponents: .date)
                                    .padding(.vertical, 6)

                                SystemPanelDivider()
                                Toggle(isOn: $hasReminder) {
                                    AppSettingsRow(icon: "bell.fill", title: "设置提醒", subtitle: "到时间提醒我")
                                }
                                .tint(FamilyUI.accent)

                                if hasReminder {
                                    SystemPanelDivider()
                                    DatePicker("提醒时间", selection: $reminderTime, displayedComponents: .hourAndMinute)
                                        .padding(.vertical, 6)
                                }
                            }

                            SystemPanelDivider()
                            Picker(localized(.priorityLabel), selection: $priority) {
                                ForEach(Priority.allCases) { priority in
                                    Text(priority.displayName(for: language)).tag(priority)
                                }
                            }
                            .padding(.vertical, 6)
                        }
                    }
                }
                .padding(.horizontal, AppSpacing.pageHorizontal)
                .padding(.top, 16)
                .padding(.bottom, 12)
            }
            .background(FamilyUI.pageBackground.ignoresSafeArea())
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle(localized(.createTask))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(localized(.cancel)) { dismiss() }
                }
            }
            .safeAreaInset(edge: .bottom) {
                PrimaryButton(title: localized(.save), isEnabled: !trimmedTitle.isEmpty) {
                    save()
                }
                .padding(.horizontal, AppSpacing.pageHorizontal)
                .padding(.top, 10)
                .padding(.bottom, 16)
                .background(.bar)
            }
            .onAppear {
                isTitleFocused = true
            }
        }
    }

    private func save() {
        _ = PlanItemService.createTask(
            PlanItemDraft(
                title: trimmedTitle,
                notes: notes.trimmingCharacters(in: .whitespacesAndNewlines),
                dueDate: hasDueDate ? Calendar.current.startOfDay(for: dueDate) : nil,
                reminderTime: hasDueDate && hasReminder ? reminderTime : nil,
                priority: priority
            ),
            in: modelContext
        )
        HapticEngine.success()
        dismiss()
    }
}

struct TaskDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query private var settings: [UserSettings]

    private var language: AppLanguage { settings.first?.language ?? .system }

    private func localized(_ zh: String, _ en: String) -> String {
        AppSettingsLocalization.text(zh, en, language: language)
    }

    @Bindable var item: PlanItem

    @State private var hasDueDate: Bool
    @State private var dueDate: Date
    @State private var hasCustomReminder: Bool
    @State private var reminderTime: Date
    @State private var isShowingDeleteConfirmation = false

    init(item: PlanItem) {
        self.item = item
        _hasDueDate = State(initialValue: item.dueDate != nil)
        _dueDate = State(initialValue: item.dueDate ?? Date())
        _hasCustomReminder = State(initialValue: item.reminderTime != nil)
        _reminderTime = State(initialValue: item.reminderTime ?? Calendar.current.date(bySettingHour: 9, minute: 0, second: 0, of: Date()) ?? Date())
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: AppSpacing.sectionSpacing) {
                SystemPanel(title: localized("任务", "Task")) {
                    VStack(alignment: .leading, spacing: 12) {
                        TextField(localized("任务标题", "Task title"), text: $item.title)
                            .textFieldStyle(.plain)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 10)
                            .background(FamilyUI.panelMutedBackground)
                            .overlay(RoundedRectangle(cornerRadius: FamilyUI.controlCornerRadius).stroke(FamilyUI.panelBorder, lineWidth: 1))
                            .clipShape(RoundedRectangle(cornerRadius: FamilyUI.controlCornerRadius))
                            .onChange(of: item.title) { _, _ in touch() }

                        TextEditor(text: $item.notes)
                            .frame(minHeight: 120)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 6)
                            .scrollContentBackground(.hidden)
                            .background(FamilyUI.panelMutedBackground)
                            .overlay(RoundedRectangle(cornerRadius: FamilyUI.controlCornerRadius).stroke(FamilyUI.panelBorder, lineWidth: 1))
                            .clipShape(RoundedRectangle(cornerRadius: FamilyUI.controlCornerRadius))
                            .onChange(of: item.notes) { _, _ in touch() }
                    }
                }

                SystemPanel(title: localized("安排", "Schedule")) {
                    VStack(alignment: .leading, spacing: 0) {
                        Toggle(isOn: $hasDueDate) {
                            AppSettingsRow(icon: "calendar", title: localized("设置日期", "Set a date"), subtitle: localized("为任务安排具体日期", "Give this task a day"))
                        }
                        .tint(FamilyUI.accent)
                        .onChange(of: hasDueDate) { _, enabled in
                            PlanItemService.updateSchedule(for: item, dueDate: enabled ? dueDate : nil, reminderTime: enabled && hasCustomReminder ? reminderTime : nil)
                        }

                        if hasDueDate {
                            SystemPanelDivider()
                            DatePicker("日期", selection: $dueDate, displayedComponents: .date)
                                .padding(.vertical, 6)
                                .onChange(of: dueDate) { _, newDate in
                                    PlanItemService.updateSchedule(for: item, dueDate: newDate, reminderTime: hasCustomReminder ? reminderTime : nil)
                                }

                            SystemPanelDivider()
                            Toggle(isOn: $hasCustomReminder) {
                                AppSettingsRow(icon: "bell.fill", title: localized("自定义提醒时间", "Custom reminder"), subtitle: localized("为这条任务设置提醒", "Remind me about this task"))
                            }
                            .tint(FamilyUI.accent)
                            .onChange(of: hasCustomReminder) { _, enabled in
                                PlanItemService.updateSchedule(for: item, dueDate: dueDate, reminderTime: enabled ? reminderTime : nil)
                            }

                            if hasCustomReminder {
                                SystemPanelDivider()
                                DatePicker("提醒时间", selection: $reminderTime, displayedComponents: .hourAndMinute)
                                    .padding(.vertical, 6)
                                    .onChange(of: reminderTime) { _, newTime in
                                        PlanItemService.updateSchedule(for: item, dueDate: dueDate, reminderTime: newTime)
                                    }
                            }
                        }

                        SystemPanelDivider()
                        Picker(localized("优先级", "Priority"), selection: priorityBinding) {
                            ForEach(Priority.allCases) { priority in
                                Text(priority.displayName(for: language)).tag(priority)
                            }
                        }
                        .padding(.vertical, 6)
                    }
                }

                SystemPanel {
                    VStack(spacing: 0) {
                        Button {
                            withAnimation { PlanItemService.toggleCompletion(item) }
                            HapticEngine.success()
                        } label: {
                            AppSettingsRow(
                                icon: item.isCompleted ? "circle" : "checkmark.circle.fill",
                                title: item.isCompleted ? localized("标记未完成", "Mark not done") : localized("标记完成", "Mark done"),
                                iconColor: item.isCompleted ? .secondary : FamilyUI.success,
                                showsChevron: false
                            )
                        }
                        .buttonStyle(.plain)

                        SystemPanelDivider()

                        Button(role: .destructive) {
                            isShowingDeleteConfirmation = true
                        } label: {
                            AppSettingsRow(icon: "trash", title: localized("删除任务", "Delete task"), iconColor: FamilyUI.danger)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(.horizontal, AppSpacing.pageHorizontal)
            .padding(.vertical, 16)
        }
        .background(FamilyUI.pageBackground.ignoresSafeArea())
        .scrollDismissesKeyboard(.interactively)
        .navigationTitle(localized("任务详情", "Task details"))
        .navigationBarTitleDisplayMode(.inline)
        .onDisappear {
            PlanItemService.refreshReminder(for: item)
        }
        .confirmationDialog(localized("删除这条任务？", "Delete this task?"), isPresented: $isShowingDeleteConfirmation, titleVisibility: .visible) {
            Button(localized("删除", "Delete"), role: .destructive) {
                HapticEngine.warning()
                PlanItemService.delete(item, in: modelContext)
                dismiss()
            }
            Button(localized("取消", "Cancel"), role: .cancel) {}
        } message: {
            Text(localized("删除后无法恢复。", "This cannot be undone."))
        }
    }

    private func touch() {
        item.updatedAt = Date()
    }

    private var priorityBinding: Binding<Priority> {
        Binding {
            item.priority
        } set: { priority in
            item.priority = priority
            touch()
        }
    }
}
