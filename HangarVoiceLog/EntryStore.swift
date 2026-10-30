import Foundation
import UIKit

/// Saves entries, recordings and photos in the app's own folder on the phone.
/// Nothing is sent anywhere.
@MainActor
final class EntryStore: ObservableObject {
    @Published private(set) var entries: [LogEntry] = []

    private let fileManager = FileManager.default

    var documentsURL: URL {
        fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }

    var mediaURL: URL {
        documentsURL.appendingPathComponent("Media", isDirectory: true)
    }

    private var entriesFileURL: URL {
        documentsURL.appendingPathComponent("entries.json")
    }

    init() {
        try? fileManager.createDirectory(at: mediaURL, withIntermediateDirectories: true)
        load()
    }

    func fileURL(for name: String) -> URL {
        mediaURL.appendingPathComponent(name)
    }

    // MARK: Entries

    func upsert(_ entry: LogEntry) {
        if let index = entries.firstIndex(where: { $0.id == entry.id }) {
            entries[index] = entry
        } else {
            entries.append(entry)
        }
        sort()
        save()
    }

    func delete(_ entry: LogEntry) {
        deleteFiles(for: entry)
        entries.removeAll { $0.id == entry.id }
        save()
    }

    func deleteFiles(for entry: LogEntry) {
        var names = entry.photoFileNames
        if let audio = entry.audioFileName { names.append(audio) }
        names.forEach(deleteMedia)
    }

    func deleteMedia(named name: String) {
        try? fileManager.removeItem(at: fileURL(for: name))
    }

    // MARK: Media

    func newAudioFileName() -> String {
        "voice-\(UUID().uuidString).m4a"
    }

    /// Saves a photo as a JPEG and returns its file name.
    func savePhoto(_ image: UIImage) -> String? {
        guard let data = image.jpegData(compressionQuality: 0.8) else { return nil }
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

    // MARK: Export

    func exportCSV(tail: String) -> URL? {
        let url = fileManager.temporaryDirectory.appendingPathComponent("Hangar Log Export.csv")
        let text = LogbookFormatter.csv(for: entries, tail: tail)
        do {
            try text.write(to: url, atomically: true, encoding: .utf8)
            return url
        } catch {
            return nil
        }
    }

    // MARK: Persistence

    private func sort() {
        entries.sort { ($0.workDate, $0.created) > ($1.workDate, $1.created) }
    }

    private func load() {
        guard let data = try? Data(contentsOf: entriesFileURL) else { return }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        if let decoded = try? decoder.decode([LogEntry].self, from: data) {
            entries = decoded
            sort()
        }
    }

    private func save() {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let data = try? encoder.encode(entries) {
            try? data.write(to: entriesFileURL, options: .atomic)
        }
    }
}
