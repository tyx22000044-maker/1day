import SwiftUI
import SwiftData

struct NotesListView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: [SortDescriptor(\Note.updatedAt, order: .reverse)])
    private var notes: [Note]

    @State private var searchText = ""
    @State private var debouncedSearchText = ""
    @State private var editingNote: Note?

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
                            title: "随手记下你的想法",
                            subtitle: "点击 + 创建一条笔记",
                            buttonTitle: "创建笔记"
                        ) {
                            createNote()
                        }
                        .padding(.top, 24)
                    } else if filtered.isEmpty {
                        AppEmptyStateView(
                            icon: "magnifyingglass",
                            title: "没有匹配的笔记",
                            subtitle: "试试搜索标题中的关键词，或正文中的片段"
                        )
                        .padding(.top, 24)
                    } else {
                        SystemPanel(title: "笔记", detail: "\(filtered.count) 条") {
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
                                            deleteNote(note)
                                        } label: {
                                            Label("删除", systemImage: "trash")
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
            .navigationTitle("笔记")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $searchText, prompt: "搜索笔记")
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
        }
    }

    private func createNote() {
        let note = Note()
        modelContext.insert(note)
        editingNote = note
    }

    private func deleteNote(_ note: Note) {
        HapticEngine.warning()
        modelContext.delete(note)
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
