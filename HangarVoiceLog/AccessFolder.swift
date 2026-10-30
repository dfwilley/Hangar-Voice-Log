import Foundation

/// The Dropbox "Maintenance Software" folder, opened through the iPhone Files app.
/// The app reads the newest "Hangar Log Data" file there and adds finished entries
/// to "Claude Logbook Import.txt". It never touches the .accdb files.
enum AccessFolder {

    enum FolderError: LocalizedError {
        case notChosen
        case noAccess
        case wrongFolder
        case unreadable(String)

        var errorDescription: String? {
            switch self {
            case .notChosen:
                return "Choose your Maintenance Software folder in Dropbox first."
            case .noAccess:
                return "The app lost access to the Dropbox folder. Choose it again."
            case .wrongFolder:
                return "That folder doesn't have your Maintenance Record database in it. Choose the Maintenance Software folder."
            case .unreadable(let detail):
                return "Couldn't read the Dropbox folder (\(detail))."
            }
        }
    }

    static let dataFilePrefix = "Hangar Log Data"
    private static let bookmarkKey = "accessFolderBookmark"
    private static let folderNameKey = "accessFolderName"

    static var folderName: String? {
        UserDefaults.standard.string(forKey: folderNameKey)
    }

    static var isChosen: Bool {
        UserDefaults.standard.data(forKey: bookmarkKey) != nil
    }

    /// Remembers the folder the user picked so it can be opened on later launches.
    static func remember(_ url: URL) throws {
        let accessing = url.startAccessingSecurityScopedResource()
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }
        let names = (try? FileManager.default.contentsOfDirectory(atPath: url.path)) ?? []
        guard names.contains(where: { $0.lowercased().hasSuffix(".accdb") || $0.hasPrefix(dataFilePrefix) }) else {
            throw FolderError.wrongFolder
        }
        let bookmark = try url.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil)
        UserDefaults.standard.set(bookmark, forKey: bookmarkKey)
        UserDefaults.standard.set(url.lastPathComponent, forKey: folderNameKey)
    }

    static func forget() {
        UserDefaults.standard.removeObject(forKey: bookmarkKey)
        UserDefaults.standard.removeObject(forKey: folderNameKey)
    }

    /// Runs `work` with permission to use the folder.
    private static func withFolder<T>(_ work: (URL) throws -> T) throws -> T {
        guard let bookmark = UserDefaults.standard.data(forKey: bookmarkKey) else {
            throw FolderError.notChosen
        }
        var stale = false
        let url: URL
        do {
            url = try URL(resolvingBookmarkData: bookmark, options: [], relativeTo: nil, bookmarkDataIsStale: &stale)
        } catch {
            throw FolderError.noAccess
        }
        guard url.startAccessingSecurityScopedResource() else { throw FolderError.noAccess }
        defer { url.stopAccessingSecurityScopedResource() }
        if stale, let fresh = try? url.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil) {
            UserDefaults.standard.set(fresh, forKey: bookmarkKey)
        }
        return try work(url)
    }

    /// Reads the newest "Hangar Log Data … .json" file in the folder.
    /// Returns nil when the folder has none yet.
    static func loadNewestData() throws -> (data: HangarData, fileName: String)? {
        try withFolder { (folder: URL) -> (data: HangarData, fileName: String)? in
            var listError: NSError?
            var names: [String] = []
            NSFileCoordinator().coordinate(readingItemAt: folder, options: [], error: &listError) { url in
                names = (try? FileManager.default.contentsOfDirectory(atPath: url.path)) ?? []
            }
            if let listError { throw FolderError.unreadable(listError.localizedDescription) }

            let candidates = names
                .filter { $0.hasPrefix(dataFilePrefix) && $0.lowercased().hasSuffix(".json") }
                .sorted()   // names carry the date and time, so the last one is newest
            guard let newest = candidates.last else { return nil }

            var readError: NSError?
            var result: Result<HangarData, Error> = .failure(FolderError.unreadable("no data"))
            NSFileCoordinator().coordinate(readingItemAt: folder.appendingPathComponent(newest), options: [], error: &readError) { url in
                result = Result { try HangarData.decode(Data(contentsOf: url)) }
            }
            if let readError { throw FolderError.unreadable(readError.localizedDescription) }
            return (try result.get(), newest)
        }
    }

    /// Adds lines to Claude Logbook Import.txt, creating it with its header if needed.
    static func appendToImportFile(_ lines: [String]) throws {
        try withFolder { (folder: URL) -> Void in
            let fileURL = folder.appendingPathComponent(LogbookFormatter.importFileName)
            var coordinationError: NSError?
            var writeError: Error?
            NSFileCoordinator().coordinate(writingItemAt: fileURL, options: .forMerging, error: &coordinationError) { url in
                do {
                    let existing: String?
                    if FileManager.default.fileExists(atPath: url.path) {
                        existing = try String(contentsOf: url, encoding: .utf8)
                    } else {
                        existing = nil
                    }
                    let updated = LogbookFormatter.appendingImportLines(lines, to: existing)
                    try updated.write(to: url, atomically: false, encoding: .utf8)
                } catch {
                    writeError = error
                }
            }
            if let coordinationError { throw FolderError.unreadable(coordinationError.localizedDescription) }
            if let writeError { throw writeError }
        }
    }
}
