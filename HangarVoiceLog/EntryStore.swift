import Foundation
import UIKit

/// Keeps entries, recordings and photos in the app's own folder on the phone,
/// and the latest data from the Access database.
@MainActor
final class EntryStore: ObservableObject {
    @Published private(set) var entries: [LogEntry] = []
    @Published private(set) var hangarData: HangarData = .builtIn
    @Published private(set) var dataFileName: String?
    @Published private(set) var dataStatus: String?
    @Published private(set) var isLoadingData = false
    @Published private(set) var folderName: String? = AccessFolder.folderName

    private let fileManager = FileManager.default

    var documentsURL: URL { fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0] }
    var mediaURL: URL { documentsURL.appendingPathComponent("Media", isDirectory: true) }
    private var entriesFileURL: URL { documentsURL.appendingPathComponent("entries-v2.json") }
    private var cachedDataURL: URL { documentsURL.appendingPathComponent("hangar-data-cache.json") }

    init() {
        try? fileManager.createDirectory(at: mediaURL, withIntermediateDirectories: true)
        loadEntries()
        loadCachedData()
    }

    func fileURL(for name: String) -> URL { mediaURL.appendingPathComponent(name) }

    // MARK: Hobbs

    struct HobbsReading: Equatable {
        var value: Double
        var date: Date
        var fromAccess: Bool
    }

    /// The highest Hobbs known: from the Access log, or an entry made in this app.
    var lastHobbs: HobbsReading? {
        Self.lastHobbs(access: hangarData.lastHobbs, entries: entries)
    }

    nonisolated static func lastHobbs(access: HangarData.LastHobbs?, entries: [LogEntry]) -> HobbsReading? {
        var best: HobbsReading?
        if let access, let date = LogbookFormatter.dayDate(access.date) {
            best = HobbsReading(value: access.value, date: date, fromAccess: true)
        }
        for entry in entries {
            guard let value = LogbookFormatter.number(entry.hobbs) else { continue }
            if best == nil || value > best!.value {
                best = HobbsReading(value: value, date: entry.workDate, fromAccess: false)
            }
        }
        return best
    }

    // MARK: Data from Access

    func chooseFolder(_ url: URL) {
        do {
            try AccessFolder.remember(url)
            folderName = AccessFolder.folderName
            refreshData()
        } catch {
            dataStatus = error.localizedDescription
        }
    }

    func forgetFolder() {
        AccessFolder.forget()
        folderName = nil
    }

    /// Reads the newest Hangar Log Data file from Dropbox. Called each time the app opens.
    func refreshData() {
        guard AccessFolder.isChosen, !isLoadingData else { return }
        isLoadingData = true
        dataStatus = nil
        Task.detached {
            let result = Result { try AccessFolder.loadNewestData() }
            await MainActor.run {
                self.isLoadingData = false
                switch result {
                case .success(let found?):
                    self.hangarData = found.data
                    self.dataFileName = found.fileName
                    self.saveCachedData(found.data)
                case .success(nil):
                    self.dataStatus = "No Hangar Log Data file in the folder yet. Using the last copy."
                case .failure(let error):
                    self.dataStatus = error.localizedDescription + " Using the last copy."
                }
            }
        }
    }

    // MARK: Entries

    func upsert(_ entry: LogEntry) {
        var entry = entry
        entry.updated = Date()
        if let index = entries.firstIndex(where: { $0.id == entry.id }) {
            entries[index] = entry
        } else {
            entries.append(entry)
        }
        sortEntries()
        saveEntries()
    }

    func delete(_ entry: LogEntry) {
        var names = entry.photoFileNames
        if let audio = entry.audioFileName { names.append(audio) }
        names.forEach(deleteMedia)
        entries.removeAll { $0.id == entry.id }
        saveEntries()
    }

    /// Adds the entry to Claude Logbook Import.txt and marks it sent.
    func sendToAccess(_ entry: LogEntry) async throws -> LogEntry {
        let line = LogbookFormatter.importLine(for: entry)
        try await Task.detached { try AccessFolder.appendToImportFile([line]) }.value
        var sent = entry
        sent.status = .sent
        sent.sentAt = Date()
        upsert(sent)
        return sent
    }

    // MARK: Media

    func deleteMedia(named name: String) {
        try? fileManager.removeItem(at: fileURL(for: name))
    }

    func newAudioFileName() -> String { "voice-\(UUID().uuidString).m4a" }

    func savePhoto(_ image: UIImage) -> String? {
        let scaled = image.scaledDown(maxDimension: 2000)
        guard let data = scaled.jpegData(compressionQuality: 0.82) else { return nil }
        let name = "photo-\(UUID().uuidString).jpg"
        do {
            try data.write(to: fileURL(for: name), options: .atomic)
            return name
        } catch {
            return nil
        }
    }

    func image(named name: String) -> UIImage? {
        UIImage(contentsOfFile: fileURL(for: name).path)
    }

    // MARK: Persistence

    private func sortEntries() {
        entries.sort { ($0.workDate, $0.updated) > ($1.workDate, $1.updated) }
    }

    private func loadEntries() {
        guard let data = try? Data(contentsOf: entriesFileURL) else { return }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        if let decoded = try? decoder.decode([LogEntry].self, from: data) {
            entries = decoded
            sortEntries()
        }
    }

    private func saveEntries() {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let data = try? encoder.encode(entries) {
            try? data.write(to: entriesFileURL, options: .atomic)
        }
    }

    private func loadCachedData() {
        if let data = try? Data(contentsOf: cachedDataURL),
           let decoded = try? HangarData.decode(data) {
            hangarData = decoded
        }
    }

    private func saveCachedData(_ value: HangarData) {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        if let data = try? encoder.encode(value) {
            try? data.write(to: cachedDataURL, options: .atomic)
        }
    }
}

extension UIImage {
    func scaledDown(maxDimension: CGFloat) -> UIImage {
        let longest = max(size.width, size.height)
        guard longest > maxDimension else { return self }
        let scale = maxDimension / longest
        let newSize = CGSize(width: size.width * scale, height: size.height * scale)
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        return UIGraphicsImageRenderer(size: newSize, format: format).image { _ in
            draw(in: CGRect(origin: .zero, size: newSize))
        }
    }
}
