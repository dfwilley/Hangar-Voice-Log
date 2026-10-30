import SwiftUI
import UniformTypeIdentifiers

/// One scrolling page like the web Hangar Log: entry card, logbook queue, Access data.
struct ContentView: View {
    @EnvironmentObject private var store: EntryStore
    @Environment(\.scenePhase) private var scenePhase

    @State private var composing = ComposerRequest(entry: nil)
    @State private var queueTab: QueueTab = .open
    @State private var choosingFolder = false
    @State private var banner: String?

    struct ComposerRequest: Equatable {
        let id = UUID()
        let entry: LogEntry?
    }

    enum QueueTab: String, CaseIterable, Identifiable {
        case open = "In progress"
        case sent = "Sent to Access"
        var id: String { rawValue }
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(spacing: 18) {
                        if let banner {
                            Text(banner)
                                .font(Theme.body(15))
                                .foregroundStyle(Theme.accentInk)
                                .padding(12)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(Theme.accentSoft, in: RoundedRectangle(cornerRadius: 10))
                        }
                        ComposerView(existing: composing.entry) { message in
                            banner = message.isEmpty ? nil : message
                            composing = ComposerRequest(entry: nil)
                            withAnimation { proxy.scrollTo("top", anchor: .top) }
                        }
                        .id(composing.id)

                        queueCard { entry in
                            banner = nil
                            composing = ComposerRequest(entry: entry)
                            withAnimation { proxy.scrollTo("top", anchor: .top) }
                        }
                        accessCard
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 18)
                    .padding(.bottom, 48)
                    .id("top")
                }
                .scrollDismissesKeyboard(.interactively)
            }
            .background(Theme.bg)
        }
        .background(Theme.bg)
        .fileImporter(isPresented: $choosingFolder, allowedContentTypes: [.folder]) { result in
            if case .success(let url) = result { store.chooseFolder(url) }
        }
        .onAppear { store.refreshData() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { store.refreshData() }
        }
    }

    // MARK: Header

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            (Text("HANGAR ").foregroundStyle(Theme.onSteel) + Text("LOG").foregroundStyle(Theme.accent))
                .font(Theme.display(28))
                .tracking(1)
            Spacer()
            Text("N721NE · RV-14")
                .font(Theme.data(13, relativeTo: .caption))
                .tracking(1.3)
                .foregroundStyle(Theme.onSteel.opacity(0.85))
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(Theme.steel.ignoresSafeArea(edges: .top))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Hangar Log, N721NE, RV-14")
    }

    // MARK: Queue

    private func queueCard(open: @escaping (LogEntry) -> Void) -> some View {
        let list = store.entries.filter { queueTab == .sent ? $0.status == .sent : $0.status != .sent }
        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                CardTitle(text: "Logbook queue")
                Spacer()
            }
            HStack(spacing: 6) {
                ForEach(QueueTab.allCases) { tab in
                    Chip(title: tab.rawValue, selected: queueTab == tab) { queueTab = tab }
                }
            }
            if list.isEmpty {
                VStack(spacing: 6) {
                    Text(queueTab == .sent ? "Nothing sent yet" : (store.entries.isEmpty ? "No entries yet" : "All caught up"))
                        .font(Theme.bodySemibold(18))
                        .foregroundStyle(Theme.ink)
                    Text(queueTab == .sent
                         ? "Entries move here once they're added to your Access import file."
                         : "Pick a job above, add the details and photos, and tap Send to Access.")
                        .font(Theme.body(15))
                        .foregroundStyle(Theme.muted)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(list.enumerated()), id: \.element.id) { index, entry in
                        if index > 0 { Divider().overlay(Theme.line) }
                        Button { open(entry) } label: { QueueRow(entry: entry) }
                            .buttonStyle(.plain)
                    }
                }
            }
        }
        .card()
    }

    // MARK: Access data

    private var accessCard: some View {
        let data = store.hangarData
        return VStack(alignment: .leading, spacing: 12) {
            CardTitle(text: "From Access")
            Group {
                if let file = store.dataFileName {
                    Text("Standard entries and Hobbs from your Maintenance Record database, refreshed \(LogbookFormatter.longDate(data.generatedAt)) (\(file)).")
                } else {
                    Text("Using the \(data.source ?? "built-in copy") of your standard entries and Hobbs. Choose your Dropbox folder to get daily updates.")
                }
            }
            .font(Theme.body(15))
            .foregroundStyle(Theme.muted)

            if let status = store.dataStatus {
                Text(status)
                    .font(Theme.body(15))
                    .foregroundStyle(Theme.ink)
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Theme.warnSoft, in: RoundedRectangle(cornerRadius: 10))
            }

            if let folder = store.folderName {
                Text("Folder: \(folder)")
                    .font(Theme.data(13, relativeTo: .caption))
                    .foregroundStyle(Theme.muted)
            }

            HStack(spacing: 10) {
                if store.folderName == nil {
                    Button("Choose Dropbox Folder") { choosingFolder = true }
                        .buttonStyle(HangarButtonStyle(kind: .primary))
                } else {
                    Button(store.isLoadingData ? "Reading…" : "Reload") { store.refreshData() }
                        .buttonStyle(HangarButtonStyle(kind: .primary))
                        .disabled(store.isLoadingData)
                    Button("Change Folder") { choosingFolder = true }
                        .buttonStyle(HangarButtonStyle())
                }
            }

            Text("Pick Dropbox › Dropbox Documents › N721NE › Maintenance Software. Finished entries go into Claude Logbook Import.txt there; then run ImportClaudeLogbookEntries in Access.")
                .font(Theme.body(13, relativeTo: .footnote))
                .foregroundStyle(Theme.muted)
        }
        .card()
    }
}

private struct QueueRow: View {
    let entry: LogEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline) {
                Text(entry.title)
                    .font(Theme.bodySemibold(17))
                    .foregroundStyle(Theme.ink)
                Spacer()
                Text(entry.status == .sent ? "SENT" : "DRAFT")
                    .font(Theme.bodySemibold(12, relativeTo: .caption))
                    .tracking(1)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 2)
                    .foregroundStyle(entry.status == .sent ? Theme.onSteel : Theme.muted)
                    .background(entry.status == .sent ? Theme.steel : Theme.field, in: Capsule())
                    .overlay(Capsule().stroke(entry.status == .sent ? Color.clear : Theme.line, lineWidth: 1))
            }
            Text(meta)
                .font(Theme.data(13, relativeTo: .caption))
                .foregroundStyle(Theme.muted)
            Text(entry.summaryLine)
                .font(Theme.body(15))
                .foregroundStyle(Theme.muted)
                .lineLimit(1)
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 4)
        .contentShape(Rectangle())
    }

    private var meta: String {
        var parts = [LogbookFormatter.longDate(entry.workDate)]
        if !entry.hobbs.isEmpty { parts.append("Hobbs \(entry.hobbs)") }
        if !entry.photoFileNames.isEmpty {
            parts.append("\(entry.photoFileNames.count) photo\(entry.photoFileNames.count == 1 ? "" : "s")")
        }
        return parts.joined(separator: " · ")
    }
}
