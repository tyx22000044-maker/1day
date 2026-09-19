import SwiftUI
import SwiftData
import PhotosUI
import UIKit

struct AIChatView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(AppViewModel.self) private var appViewModel
    @Query private var settings: [UserSettings]
    @Query(sort: [SortDescriptor(\AIChatMessage.createdAt)]) private var messages: [AIChatMessage]
    @Query private var appSettings: [UserSettings]
    // AI context only ever looks at scheduled tasks (today/upcoming week), so the
    // query excludes the unscheduled backlog instead of loading every PlanItem.
    @Query(filter: #Predicate<PlanItem> { $0.dueDate != nil })
    private var allPlanItems: [PlanItem]

    @State private var viewModel = AIChatViewModel()
    @State private var speechController = SpeechInputController()
    @State private var isShowingClearConfirmation = false
    @State private var isShowingImageSourceDialog = false
    @State private var isShowingImagePicker = false
    @State private var isShowingPhotosPicker = false
    @State private var imagePickerSourceType: UIImagePickerController.SourceType = .photoLibrary
    @State private var selectedImageDataList: [Data] = []
    @State private var selectedPhotoItems: [PhotosPickerItem] = []
    @FocusState private var isInputFocused: Bool

    private var currentSettings: UserSettings? { settings.first }
    private var imageLanguage: AppLanguage { appSettings.first?.language ?? .system }
    private var currentProvider: AIProvider { currentSettings?.selectedAIProvider ?? .claude }
    private var isConfigured: Bool { currentSettings?.isAIConfigured == true }
    private var canUseVision: Bool {
        guard let settings = currentSettings else { return false }
        return isConfigured && settings.selectedAIProvider.supportsVision(model: settings.selectedAIModel)
    }

    private let configService = LocalAIConfigurationService()

    private var configStatus: AIConfigurationStatus? {
        guard let s = currentSettings else { return nil }
        return try? configService.status(for: s)
    }

    private func defaultModel(for provider: AIProvider) -> String {
        configService.providerOptions.first { $0.provider == provider }?.defaultModel ?? ""
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                AIConfigurationHeader(
                    status: configStatus,
                    isConfigured: isConfigured,
                    errorMessage: nil,
                    providerOptions: configService.providerOptions,
                    selectedProvider: currentProvider,
                    selectedModel: currentSettings?.selectedAIModel ?? defaultModel(for: currentProvider),
                    onSelectProvider: { provider in
                        guard let s = currentSettings else { return }
                        AIConfigurationCoordinator.switchProvider(to: provider, on: s, using: configService)
                        try? modelContext.save()
                        HapticEngine.tap()
                    },
                    onSelectModel: { model in
                        guard let s = currentSettings else { return }
                        AIConfigurationCoordinator.selectModel(model, on: s, using: configService)
                        try? modelContext.save()
                        HapticEngine.tap()
                    },
                    onOpenSettings: { appViewModel.selectedTab = .settings }
                )

                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 12) {
                            if messages.isEmpty && !viewModel.isLoading {
                                AIEmptyState(isConfigured: isConfigured) {
                                    appViewModel.selectedTab = .settings
                                }
                            } else {
                                ForEach(messages) { message in
                                    AIMessageBubble(message: message)
                                        .id(message.id)
                                }
                            }
                        }
                        .padding(16)
                        Color.clear.frame(height: 1).id("bottom")
                    }
                    .background(FamilyUI.pageBackground)
                    .scrollDismissesKeyboard(.interactively)
                    .simultaneousGesture(TapGesture().onEnded { isInputFocused = false })
                    .onChange(of: messages.count) { _, _ in
                        withAnimation(.easeOut(duration: 0.2)) { proxy.scrollTo("bottom") }
                    }
                    .onChange(of: viewModel.isLoading) { _, loading in
                        if loading {
                            withAnimation { proxy.scrollTo("bottom") }
                        }
                    }
                }

                inputSection
            }
            .background(FamilyUI.pageBackground)
            .navigationTitle("AI")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        isInputFocused = false
                        isShowingClearConfirmation = true
                    } label: {
                        Image(systemName: "trash")
                    }
                    .disabled(messages.isEmpty)
                }
            }
            .sheet(isPresented: $viewModel.isShowingConfirmation) {
                if let pendingTask = viewModel.pendingTask {
                    TaskDraftConfirmationView(
                        draft: pendingTask,
                        defaultReminderTime: currentSettings?.defaultReminderTime ?? DateComponents(hour: 9, minute: 0)
                    ) { task in
                        viewModel.save(task, settings: currentSettings, modelContext: modelContext)
                    }
                }
            }
            .alert("清空 AI 对话", isPresented: $isShowingClearConfirmation) {
                Button("取消", role: .cancel) {}
                Button("清空", role: .destructive) {
                    HapticEngine.warning()
                    for m in messages { modelContext.delete(m) }
                }
            } message: {
                Text("这只会删除聊天历史，不会删除已创建的任务。")
            }
            .confirmationDialog("添加图片", isPresented: $isShowingImageSourceDialog, titleVisibility: .visible) {
                if UIImagePickerController.isSourceTypeAvailable(.camera) {
                    Button("拍照") {
                        imagePickerSourceType = .camera
                        isShowingImagePicker = true
                    }
                }
                Button("从相册选择") {
                    isShowingPhotosPicker = true
                }
                Button("取消", role: .cancel) {}
            }
            .sheet(isPresented: $isShowingImagePicker) {
                AIImagePicker(sourceType: imagePickerSourceType) { data in
                    appendImageData(data)
                }
            }
            .photosPicker(
                isPresented: $isShowingPhotosPicker,
                selection: $selectedPhotoItems,
                maxSelectionCount: max(1, AIVisionRequest.maximumImageCount - selectedImageDataList.count),
                matching: .images
            )
            .onChange(of: selectedPhotoItems) { _, items in
                Task { await appendPhotoItems(items) }
            }
            .overlay(alignment: .bottom) {
                if viewModel.undoItem != nil {
                    UndoCratedToast(title: viewModel.undoTaskTitle) {
                        viewModel.undoTaskCreation(modelContext: modelContext)
                    }
                    .padding(.bottom, 72)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .animation(.easeInOut(duration: 0.25), value: viewModel.undoItem != nil)
        }
        .onChange(of: speechController.errorMessage) { _, message in
            guard let message else { return }
            GlobalBannerCenter.shared.show(title: "语音输入异常", message: message, tone: .warning)
        }
    }

    private var inputSection: some View {
        VStack(spacing: 10) {
            if viewModel.isLoading {
                AIRequestProgressView(elapsedSeconds: viewModel.loadingSeconds, hasImages: viewModel.isLoadingImages)
                    .padding(.horizontal, 16)
            }

            if !selectedImageDataList.isEmpty {
                selectedImagesSection
            }

            suggestionChips
            inputBar
        }
        .padding(.vertical, 12)
        .background(
            FamilyUI.pageBackground
                .overlay(alignment: .top) {
                    Rectangle()
                        .fill(FamilyUI.panelBorder)
                        .frame(height: 1)
                }
        )
    }

    // MARK: - Suggestion Chips

    private var suggestionChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(suggestions, id: \.self) { text in
                    Button {
                        viewModel.inputText = text
                        isInputFocused = true
                    } label: {
                        Text(text)
                            .font(.caption.weight(.medium))
                            .lineLimit(1)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 7)
                            .background(FamilyUI.panelMutedBackground)
                            .overlay(
                                RoundedRectangle(cornerRadius: FamilyUI.badgeCornerRadius)
                                    .stroke(FamilyUI.panelBorder, lineWidth: 1)
                            )
                            .clipShape(RoundedRectangle(cornerRadius: FamilyUI.badgeCornerRadius))
                    }
                    .foregroundStyle(.primary)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
        }
    }

    private let suggestions = [
        "明天下午整理 PRD，高优先级",
        "周五开会讨论 Q3 计划",
        "今天完成周报",
        "下周一约客户，重要"
    ]

    // MARK: - Input Bar

    private var inputBar: some View {
        VStack(spacing: 0) {
            if viewModel.failedRequestText != nil {
                HStack(spacing: 10) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(FamilyUI.warning)
                    Text("上次 AI 请求失败")
                        .font(.caption.weight(.semibold))
                    Spacer()
                    Button("重试", action: retryLastRequest)
                        .font(.caption.weight(.bold))
                        .foregroundStyle(FamilyUI.accent)
                }
                .padding(.horizontal, 16)
                .padding(.top, 10)
            }

            HStack(alignment: .bottom, spacing: 10) {
                Button {
                    HapticEngine.tap()
                    if canUseVision {
                        isInputFocused = false
                        isShowingImageSourceDialog = true
                    } else {
                        GlobalBannerCenter.shared.show(
                            title: "图片输入不可用",
                            message: isConfigured ? "当前模型不支持图片识别，请切换到支持视觉输入的模型。" : "请先配置 AI。",
                            tone: .warning
                        )
                    }
                } label: {
                    Image(systemName: "camera.fill")
                        .fontWeight(.semibold)
                        .frame(width: 44, height: 44)
                        .background(FamilyUI.panelMutedBackground)
                        .foregroundStyle(canUseVision ? FamilyUI.accent : FamilyUI.subtleText)
                        .overlay(
                            RoundedRectangle(cornerRadius: FamilyUI.controlCornerRadius)
                                .stroke(FamilyUI.panelBorder, lineWidth: 1)
                        )
                        .clipShape(RoundedRectangle(cornerRadius: FamilyUI.controlCornerRadius))
                }
                .disabled(viewModel.isLoading)
                .accessibilityLabel("拍照或上传图片")

                Button {
                    speechController.toggleRecording { transcript in
                        viewModel.inputText = transcript
                    }
                } label: {
                    Image(systemName: speechController.isRecording ? "mic.fill" : "mic")
                        .fontWeight(.semibold)
                        .frame(width: 44, height: 44)
                        .background(speechController.isRecording ? FamilyUI.danger : FamilyUI.panelMutedBackground)
                        .foregroundStyle(speechController.isRecording ? FamilyUI.paper : FamilyUI.ink)
                        .overlay(
                            RoundedRectangle(cornerRadius: FamilyUI.controlCornerRadius)
                                .stroke(FamilyUI.panelBorder, lineWidth: 1)
                        )
                        .clipShape(RoundedRectangle(cornerRadius: FamilyUI.controlCornerRadius))
                }
                .disabled(viewModel.isLoading)

                TextField("让 AI 帮你整理一件事...", text: $viewModel.inputText, axis: .vertical)
                    .lineLimit(1...4)
                    .textFieldStyle(.plain)
                    .font(.subheadline)
                    .focused($isInputFocused)
                    .onSubmit(send)
                    .onChange(of: viewModel.inputText) { _, _ in
                        if speechController.isRecording && !viewModel.inputText.isEmpty {
                            // text is live transcript, don't interfere
                        }
                    }
                    .padding(.horizontal, 14)
                    .frame(minHeight: 38, alignment: .center)
                    .background(FamilyUI.panelMutedBackground)
                    .overlay(
                        RoundedRectangle(cornerRadius: FamilyUI.controlCornerRadius)
                            .stroke(FamilyUI.panelBorder, lineWidth: 1)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: FamilyUI.controlCornerRadius))

                Button(action: send) {
                    Image(systemName: viewModel.isLoading ? "stop.fill" : "arrow.up")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(FamilyUI.paper)
                        .frame(width: 44, height: 44)
                        .background(FamilyUI.ink)
                        .clipShape(RoundedRectangle(cornerRadius: FamilyUI.controlCornerRadius))
                }
                .buttonStyle(.plain)
                .disabled(!viewModel.isLoading && viewModel.inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && selectedImageDataList.isEmpty)
            }
            .padding()
        }
    }

    private var selectedImagesSection: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(Array(selectedImageDataList.enumerated()), id: \.offset) { index, data in
                    if let image = UIImage(data: data) {
                        ZStack(alignment: .topTrailing) {
                            Image(uiImage: image)
                                .resizable()
                                .scaledToFill()
                                .frame(width: 58, height: 58)
                                .clipShape(RoundedRectangle(cornerRadius: FamilyUI.controlCornerRadius))
                                .overlay(
                                    RoundedRectangle(cornerRadius: FamilyUI.controlCornerRadius)
                                        .stroke(FamilyUI.panelBorder, lineWidth: 1)
                                )
                                .clipped()

                            Button {
                                selectedImageDataList.remove(at: index)
                                HapticEngine.tap()
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .font(.caption)
                                    .foregroundStyle(.white, .black.opacity(0.45))
                            }
                            // 只有一张 × 图标的话，读屏说不出「移除的是第几张」。
                            .accessibilityLabel(
                                AppSettingsLocalization.text(
                                    "移除第 \(index + 1) 张图片",
                                    "Remove image \(index + 1)",
                                    language: imageLanguage
                                )
                            )
                            .offset(x: 5, y: -5)
                        }
                    }
                }

                Text("已附加 \(selectedImageDataList.count)/\(AIVisionRequest.maximumImageCount)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 10)
    }

    // MARK: - Actions

    private func send() {
        if viewModel.isLoading {
            viewModel.stopLoading()
            return
        }

        let text = viewModel.inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        let imageDataList = selectedImageDataList
        guard !text.isEmpty || !imageDataList.isEmpty else { return }

        selectedImageDataList = []
        viewModel.send(
            imageDataList: imageDataList,
            messages: messages,
            settings: currentSettings,
            planItems: allPlanItems,
            selectedDate: appViewModel.selectedDate,
            modelContext: modelContext
        )
    }

    private func retryLastRequest() {
        viewModel.retryLastRequest(
            settings: currentSettings,
            planItems: allPlanItems,
            selectedDate: appViewModel.selectedDate,
            modelContext: modelContext
        )
    }

    private func appendImageData(_ data: Data) {
        guard selectedImageDataList.count < AIVisionRequest.maximumImageCount else { return }
        // 压不进上限的图不要静默塞进列表：发出去只会变成一句笼统的网络错误。
        guard let compressed = ImageService.compress(data) else {
            GlobalBannerCenter.shared.show(
                title: "这张图片用不了",
                message: "压缩后仍然过大或无法读取，请换一张，或减少图片张数。",
                tone: .warning
            )
            return
        }
        selectedImageDataList.append(compressed)
    }

    @MainActor
    private func appendPhotoItems(_ items: [PhotosPickerItem]) async {
        defer { selectedPhotoItems = [] }
        for item in items where selectedImageDataList.count < AIVisionRequest.maximumImageCount {
            if let data = try? await item.loadTransferable(type: Data.self) {
                appendImageData(data)
            }
        }
    }
}

// MARK: - Undo Toast

private struct UndoCratedToast: View {
    let title: String
    let onUndo: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(FamilyUI.success)
            Text("已创建：\(title)")
                .font(.subheadline)
                .lineLimit(1)
            Spacer(minLength: 0)
            Button("撤销", action: onUndo)
                .font(.subheadline.weight(.semibold))
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

// MARK: - Task Draft Confirmation

private struct TaskDraftConfirmationView: View {
    @Environment(\.dismiss) private var dismiss

    @State private var title: String
    @State private var notes: String
    @State private var hasDueDate: Bool
    @State private var dueDate: Date
    @State private var priority: Priority
    @State private var hasReminder: Bool
    @State private var reminderTime: Date

    let onConfirm: (AIParsedTask) -> Void

    init(draft: AIParsedTask, defaultReminderTime: DateComponents, onConfirm: @escaping (AIParsedTask) -> Void) {
        _title = State(initialValue: draft.title)
        _notes = State(initialValue: draft.notes ?? "")
        _hasDueDate = State(initialValue: draft.dueDate != nil)
        _dueDate = State(initialValue: draft.dueDate ?? Date())
        _priority = State(initialValue: draft.priority ?? .none)
        // AI 给了提醒时间就带上；没给则以用户在设置里定的默认提醒时间起算。
        let fallback = Calendar.current.date(
            bySettingHour: defaultReminderTime.hour ?? 9,
            minute: defaultReminderTime.minute ?? 0,
            second: 0,
            of: draft.dueDate ?? Date()
        ) ?? Date()
        _reminderTime = State(initialValue: draft.reminderTime ?? fallback)
        _hasReminder = State(initialValue: draft.reminderTime != nil)
        self.onConfirm = onConfirm
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: AppSpacing.sectionSpacing) {
                    SystemPanel(title: "任务草稿", detail: "确认后会加入计划") {
                        VStack(alignment: .leading, spacing: 12) {
                            TextField("任务标题", text: $title)
                                .textFieldStyle(.plain)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 10)
                                .background(FamilyUI.panelMutedBackground)
                                .overlay(RoundedRectangle(cornerRadius: FamilyUI.controlCornerRadius).stroke(FamilyUI.panelBorder, lineWidth: 1))
                                .clipShape(RoundedRectangle(cornerRadius: FamilyUI.controlCornerRadius))

                            TextEditor(text: $notes)
                                .frame(minHeight: 100)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 6)
                                .scrollContentBackground(.hidden)
                                .background(FamilyUI.panelMutedBackground)
                                .overlay(RoundedRectangle(cornerRadius: FamilyUI.controlCornerRadius).stroke(FamilyUI.panelBorder, lineWidth: 1))
                                .clipShape(RoundedRectangle(cornerRadius: FamilyUI.controlCornerRadius))
                        }
                    }

                    SystemPanel(title: "安排") {
                        VStack(alignment: .leading, spacing: 0) {
                            Toggle(isOn: $hasDueDate) {
                                AppSettingsRow(icon: "calendar", title: "设置日期", subtitle: "为任务安排具体日期")
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
                            Picker("优先级", selection: $priority) {
                                ForEach(Priority.allCases) { priority in
                                    Text(priority.displayName).tag(priority)
                                }
                            }
                            .padding(.vertical, 6)
                        }
                    }
                }
                .padding(.horizontal, AppSpacing.pageHorizontal)
                .padding(.vertical, 16)
            }
            .background(FamilyUI.pageBackground.ignoresSafeArea())
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle("确认创建")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("创建") {
                        let task = AIParsedTask(
                            title: title.trimmingCharacters(in: .whitespacesAndNewlines),
                            notes: notes.trimmingCharacters(in: .whitespacesAndNewlines),
                            dueDate: hasDueDate ? Calendar.current.startOfDay(for: dueDate) : nil,
                            dueDateText: nil,
                            priority: priority,
                            reminderTime: hasDueDate && hasReminder ? reminderTime : nil
                        )
                        onConfirm(task)
                        dismiss()
                    }
                    .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }
}
