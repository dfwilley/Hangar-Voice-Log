import SwiftUI

struct EntryListView: View {
    @EnvironmentObject private var store: EntryStore
    @AppStorage(AppSettings.tailKey) private var tail = AppSettings.defaultTail

    @State private var editing: EditorRequest?
    @State private var shareItems: ShareItems?
    @State private var showingSettings = false
    @State private var pendingDelete: LogEntry?

    struct EditorRequest: Identifiable {
        let id = UUID()
        let entry: LogEntry
        let isNew: Bool
    }

    var body: some View {
        NavigationStack {
            Group {
                if store.entries.isEmpty {
                    ContentUnavailableView {
                        Label("No entries yet", systemImage: "mic.badge.plus")
                    } description: {
                        Text("Tap New Entry, then describe the work out loud.")
                    }
                } else {
                    List {
                        ForEach(store.entries) { entry in
                            Button {
                                editing = EditorRequest(entry: entry, isNew: false)
                            } label: {
                                EntryRow(entry: entry)
                            }
                            .foregroundStyle(.primary)
                            .swipeActions {
                                Button(role: .destructive) {
                                    pendingDelete = entry
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle(tail)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Menu {
                        Button {
                            if let url = store.exportCSV(tail: tail) {
                                shareItems = ShareItems(items: [url])
                            }
                        } label: {
                            Label("Export All as Spreadsheet", systemImage: "tablecells")
                        }
                        .disabled(store.entries.isEmpty)
                        Button {
                            showingSettings = true
                        } label: {
                            Label("Tail Number", systemImage: "airplane")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                            .accessibilityLabel("More")
                    }
                }
            }
            .safeAreaInset(edge: .bottom) {
                Button {
                    editing = EditorRequest(entry: LogEntry(), isNew: true)
                } label: {
                    Label("New Entry", systemImage: "mic.fill")
                        .font(.title3.bold())
                        .frame(maxWidth: .infinity, minHeight: 50)
                }
                .buttonStyle(.borderedProminent)
                .padding()
                .background(.bar)
            }
            .sheet(item: $editing) { request in
                EntryEditorView(entry: request.entry, isNew: request.isNew)
                    .environmentObject(store)
            }
            .sheet(item: $shareItems) { share in
                ShareSheet(items: share.items)
            }
            .alert("Tail Number", isPresented: $showingSettings) {
                TextField("Tail number", text: $tail)
                    .textInputAutocapitalization(.characters)
                Button("Done") {
                    let trimmed = tail.trimmingCharacters(in: .whitespaces).uppercased()
                    tail = trimmed.isEmpty ? AppSettings.defaultTail : trimmed
                }
            }
            .confirmationDialog(
                "Delete this entry, its recording and photos?",
                isPresented: Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } }),
                titleVisibility: .visible
            ) {
                Button("Delete", role: .destructive) {
                    if let entry = pendingDelete { store.delete(entry) }
                    pendingDelete = nil
                }
                Button("Cancel", role: .cancel) { pendingDelete = nil }
            }
        }
    }
}

private struct EntryRow: View {
    let entry: LogEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(LogbookFormatter.longDate(entry.workDate))
                    .font(.headline)
                Spacer()
                Text(entry.category.label)
                    .font(.caption.bold())
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                    .background(Color.accentColor.opacity(0.15), in: Capsule())
            }
            Text(entry.summaryLine)
                .lineLimit(2)
                .foregroundStyle(.secondary)
            HStack(spacing: 12) {
                if !entry.tach.isEmpty {
                    Label("Tach \(entry.tach)", systemImage: "gauge.with.needle")
                }
                if entry.audioFileName != nil {
                    Label("Voice", systemImage: "waveform")
                }
                if !entry.photoFileNames.isEmpty {
                    Label("\(entry.photoFileNames.count)", systemImage: "photo")
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
    }
}
