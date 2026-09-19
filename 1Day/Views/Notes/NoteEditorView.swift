import SwiftUI
import SwiftData

struct NoteEditorView: View {
    @Environment(\.modelContext) private var modelContext
    @Bindable var note: Note
    @FocusState private var isTitleFocused: Bool
    @FocusState private var isContentFocused: Bool

    /// 进入本页时这条笔记是不是空的——只有「刚点 + 建出来、一直没写字」才允许静默清理。
    @State private var openedEmpty = true
    @State private var showSavedBadge = false
    @State private var saveTask: Task<Void, Never>?
    @State private var badgeTask: Task<Void, Never>?

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: AppSpacing.sectionSpacing) {
                SystemPanel(title: "笔记", detail: "记录想法、会议内容或待办线索") {
                    VStack(alignment: .leading, spacing: 12) {
                        TextField("笔记标题", text: $note.title)
                            .font(.title3.weight(.bold))
                            .focused($isTitleFocused)
                            .textFieldStyle(.plain)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 10)
                            .background(FamilyUI.panelMutedBackground)
                            .overlay(RoundedRectangle(cornerRadius: FamilyUI.controlCornerRadius).stroke(FamilyUI.panelBorder, lineWidth: 1))
                            .clipShape(RoundedRectangle(cornerRadius: FamilyUI.controlCornerRadius))

                        TextEditor(text: $note.content)
                            .focused($isContentFocused)
                            .frame(minHeight: 360)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 6)
                            .scrollContentBackground(.hidden)
                            .background(FamilyUI.panelMutedBackground)
                            .overlay(RoundedRectangle(cornerRadius: FamilyUI.controlCornerRadius).stroke(FamilyUI.panelBorder, lineWidth: 1))
                            .clipShape(RoundedRectangle(cornerRadius: FamilyUI.controlCornerRadius))
                    }
                }
            }
            .padding(.horizontal, AppSpacing.pageHorizontal)
            .padding(.vertical, 16)
        }
        .background(FamilyUI.pageBackground.ignoresSafeArea())
        .scrollDismissesKeyboard(.interactively)
        .navigationTitle(note.title.isEmpty ? "新建笔记" : "笔记")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                if showSavedBadge {
                    Label("已保存", systemImage: "checkmark.circle.fill")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .transition(.opacity)
                }
            }
        }
        .onChange(of: note.title) { _, _ in touch() }
        .onChange(of: note.content) { _, _ in touch() }
        .onAppear {
            openedEmpty = note.isEmpty
            if note.isEmpty { isTitleFocused = true }
        }
        .onDisappear {
            saveTask?.cancel()
            saveTask = nil
            finishDeparture()
        }
    }

    /// 打字停顿后再落盘，避免每个字符都写一次库。
    private func touch() {
        note.updatedAt = Date()
        saveTask?.cancel()
        saveTask = Task {
            try? await Task.sleep(nanoseconds: 600_000_000)
            guard !Task.isCancelled else { return }
            await MainActor.run { commit() }
        }
    }

    /// 「已保存」标记只在 `save()` 真的成功之后出现；
    /// 之前是按时间亮的，autosave 失败时也会显示已保存。
    private func commit() {
        do {
            try modelContext.save()
            showSavedBadge = true
            badgeTask?.cancel()
            badgeTask = Task {
                try? await Task.sleep(nanoseconds: 1_500_000_000)
                guard !Task.isCancelled else { return }
                await MainActor.run { withAnimation { showSavedBadge = false } }
            }
        } catch {
            AppLogger.dataError("保存笔记失败: \(error.localizedDescription)")
            GlobalBannerCenter.shared.show(
                title: "笔记没能保存",
                message: "存储空间可能不可用。先别退出 App，到「设置 → 数据管理」导出备份。",
                tone: .error
            )
        }
    }

    private func finishDeparture() {
        // 曾经有内容的笔记被清空：留着它，让用户在列表里显式删除（那里有确认和撤销）。
        // 只有「点 + 建出来、一个字没写就返回」才静默清理草稿。
        if NoteEditorPolicy.discardEmptyDraftOnDeparture(openedEmpty: openedEmpty, isNowEmpty: note.isEmpty) {
            modelContext.delete(note)
            try? modelContext.save()
        } else {
            // 把还没落盘的编辑冲刷进库，别指望 autosave。
            commit()
        }
    }
}

enum NoteEditorPolicy {
    /// 返回 true 才允许在离开页面时删掉这条笔记。
    static func discardEmptyDraftOnDeparture(openedEmpty: Bool, isNowEmpty: Bool) -> Bool {
        openedEmpty && isNowEmpty
    }
}
