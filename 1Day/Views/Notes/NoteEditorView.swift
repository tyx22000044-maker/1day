import SwiftUI
import SwiftData

struct NoteEditorView: View {
    @Environment(\.modelContext) private var modelContext
    @Bindable var note: Note
    @FocusState private var isTitleFocused: Bool
    @FocusState private var isContentFocused: Bool
    @State private var showSavedBadge = false
    @State private var savedBadgeTask: Task<Void, Never>?

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
            if note.isEmpty { isTitleFocused = true }
        }
        .onDisappear {
            if note.isEmpty { modelContext.delete(note) }
        }
    }

    private func touch() {
        note.updatedAt = Date()
        savedBadgeTask?.cancel()
        savedBadgeTask = Task {
            try? await Task.sleep(nanoseconds: 800_000_000)
            guard !Task.isCancelled else { return }
            await MainActor.run {
                withAnimation { showSavedBadge = true }
            }
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            guard !Task.isCancelled else { return }
            await MainActor.run {
                withAnimation { showSavedBadge = false }
            }
        }
    }
}
