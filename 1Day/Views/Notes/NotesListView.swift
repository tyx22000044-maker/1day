import SwiftUI
import SwiftData

struct NotesListView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: [SortDescriptor(\Note.updatedAt, order: .reverse)])
    private var notes: [Note]
    @Query private var settings: [UserSettings]

    private var language: AppLanguage { settings.first?.language ?? .system }

    private func localized(_ key: AppText.Key) -> String {
        AppText.string(key, language: language)
    }

    @State private var searchText = ""
    @State private var debouncedSearchText = ""
    @State private var editingNote: Note?
    @State private var pendingNoteDelete: Note?
    @State private var undoNoteSnapshot: NoteBackup?
    @State private var undoNoteTitle = ""
    @State private var undoWindowTask: Task<Void, Never>?

    private var filteredNotes: [Note] {
        guard !debouncedSearchText.isEmpty else { return notes }
        let query = debouncedSearchText.lowercased()
        return notes.filter {
            $0.title.lowercased().contains(query) ||
            $0.content.lowercased().contains(query)
        }
    }

    var body: some View {
        let filtered = filteredNotes
        return NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: AppSpacing.sectionSpacing) {
                    if filtered.isEmpty && notes.isEmpty {
                        AppEmptyStateView(
                            icon: "note.text",
                            title: localized(.emptyNotesTitle),
                            subtitle: localized(.emptyNotesSubtitle),
                            buttonTitle: localized(.createNote)
                        ) {
                            createNote()
                        }
                        .padding(.top, 24)
                    } else if filtered.isEmpty {
                        AppEmptyStateView(
                            icon: "magnifyingglass",
                            title: localized(.emptySearchTitle),
                            subtitle: localized(.emptySearchSubtitle)
                        )
                        .padding(.top, 24)
                    } else {
                        SystemPanel(title: localized(.navNotes), detail: "\(filtered.count) " + localized(.noteCountSuffix)) {
                            VStack(alignment: .leading, spacing: 0) {
                                ForEach(Array(filtered.enumerated()), id: \.element.id) { index, note in
                                    NavigationLink {
                                        NoteEditorView(note: note)
                                    } label: {
                                        NoteRow(note: note)
                                    }
                                    .buttonStyle(.plain)
                                    .contextMenu {
                                        Button(role: .destructive) {
                                            requestNoteDelete(note)
                                        } label: {
                                            Label(localized(.delete), systemImage: "trash")
                                        }
                                    }
                                    if index < filtered.count - 1 {
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
            .navigationTitle(localized(.navNotes))
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $searchText, prompt: AppSettingsLocalization.text("搜索笔记", "Search notes", language: language))
            .task(id: searchText) {
                guard !searchText.isEmpty else {
                    debouncedSearchText = ""
                    return
                }
                try? await Task.sleep(nanoseconds: 250_000_000)
                guard !Task.isCancelled else { return }
                debouncedSearchText = searchText
            }
            .navigationDestination(item: $editingNote) { note in
                NoteEditorView(note: note)
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    FamilyAddButton {
                        createNote()
                    }
                }
            }
            .overlay(alignment: .bottom) {
                if let snapshot = undoNoteSnapshot {
                    UndoDeleteToast(label: "已删除笔记", title: undoNoteTitle) {
                        undoNoteDelete(snapshot)
                    }
                    .padding(.bottom, 16)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .animation(.easeInOut(duration: 0.25), value: undoNoteSnapshot != nil)
            .confirmationDialog(
                "删除这条笔记？",
                isPresented: Binding(
                    get: { pendingNoteDelete != nil },
                    set: { if !$0 { pendingNoteDelete = nil } }
                ),
                titleVisibility: .visible
            ) {
                Button("删除", role: .destructive) { confirmNoteDelete() }
                Button("取消", role: .cancel) { pendingNoteDelete = nil }
            } message: {
                Text("删除后 5 秒内可以在列表底部撤销，超时后就只能从备份恢复了。")
            }
        }
    }

    private func createNote() {
        let note = Note()
        modelContext.insert(note)
        editingNote = note
    }

    /// 长按菜单的删除只负责问一句，真删除在 confirmNoteDelete。
    private func requestNoteDelete(_ note: Note) {
        pendingNoteDelete = note
        HapticEngine.warning()
    }

    private func confirmNoteDelete() {
        guard let note = pendingNoteDelete else { return }
        pendingNoteDelete = nil
        let snapshot = DeletionCoordinator.snapshot(note)
        guard DeletionCoordinator.delete(note, in: modelContext) else { return }
        undoNoteSnapshot = snapshot
        undoNoteTitle = snapshot.title.isEmpty ? String(snapshot.content.prefix(20)) : snapshot.title
        startUndoWindow()
    }

    private func undoNoteDelete(_ snapshot: NoteBackup) {
        undoWindowTask?.cancel()
        undoWindowTask = nil
        undoNoteSnapshot = nil
        HapticEngine.tap()
        _ = DeletionCoordinator.restore(snapshot, in: modelContext)
    }

    private func startUndoWindow() {
        undoWindowTask?.cancel()
        undoWindowTask = Task {
            try? await Task.sleep(nanoseconds: 5_000_000_000)
            guard !Task.isCancelled else { return }
            await MainActor.run {
                withAnimation(.easeInOut(duration: 0.25)) { undoNoteSnapshot = nil }
            }
        }
    }
}

private struct NoteRow: View {
    let note: Note

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(note.displayTitle)
                .font(.subheadline)
                .fontWeight(.medium)
                .lineLimit(1)
            HStack {
                Text(note.updatedAt.formatted(.dateTime.month().day().hour().minute()))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if !note.content.isEmpty && !note.title.isEmpty {
                    Text(String(note.content.prefix(40)))
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
            }
        }
        .padding(.vertical, 2)
    }
}
