import Foundation

// MARK: - Data from the Access database

/// The "Hangar Log Data" file that Claude writes to Dropbox from
/// Maintenance Record_be.accdb (read-only). The app reads the newest one.
struct HangarData: Codable, Equatable {
    struct LastHobbs: Codable, Equatable {
        var value: Double
        /// yyyy-MM-dd
        var date: String
        var logId: Int?
    }

    struct Maintainer: Codable, Equatable, Identifiable, Hashable {
        var id: Int
        var name: String
        var ap: Bool?
    }

    /// One row of the Recurring Maintenance table.
    struct Job: Codable, Equatable, Identifiable, Hashable {
        var recurringId: Int
        var name: String
        var entry: String
        var laborHours: Double?
        var equipmentIds: [Int]?
        var id: Int { recurringId }
    }

    var schema: Int
    var generatedAt: Date
    var source: String?
    var lastHobbs: LastHobbs?
    var maintainers: [Maintainer]
    var jobs: [Job]
}

extension HangarData {
    static let ownerId = 1
    static let ownerName = "Dale Willey, Owner"

    /// Shorter button names for the jobs you use most, like the web Hangar Log.
    static let friendlyNames: [Int: String] = [
        3: "Oil change",
        5: "Prop lube",
        6: "Condition inspection",
        14: "Transponder check",
        15: "ELT check",
        16: "Propeller overhaul",
        18: "Spark plug rotation",
        20: "Pitot-static check"
    ]

    /// Jobs without standard wording, always offered.
    static let extraJobs = ["Squawk repair", "Modification", "Other"]

    static func chipName(for job: Job) -> String {
        friendlyNames[job.recurringId] ?? job.name
    }

    /// Built-in copy used until the first data file is found. Wording from the
    /// Recurring Maintenance table as read on October 28, 2026.
    static let builtIn = HangarData(
        schema: 1,
        generatedAt: ISO8601DateFormatter().date(from: "2026-10-28T12:00:00Z") ?? Date(),
        source: "Built-in copy (October 28, 2026)",
        lastHobbs: LastHobbs(value: 13.3, date: "2026-08-25", logId: 769),
        maintainers: [Maintainer(id: ownerId, name: ownerName, ap: false)],
        jobs: [
            Job(recurringId: 3, name: "Oil Change",
                entry: "Oil and filter change. Removed and inspected oil sump filter element, appears normal with no debris. Inspected oil filter element, appears normal. Filled with 6 qts Phillips 20W-50. Ground run / leak check - no anomalies noted.",
                laborHours: 1.0, equipmentIds: nil),
            Job(recurringId: 5, name: "Lubricate Propeller",
                entry: "Lubed propeller with 1 oz Aeroshell #6 in accordance with the Hartzell Propeller Manual. Test flown with no issues.",
                laborHours: 0.5, equipmentIds: nil),
            Job(recurringId: 6, name: "Annual Condition Inspection",
                entry: "Annual condition inspection. Compression checks #1 [ ]/80, #2 [ ]/80, #3 [ ]/80, #4 [ ]/80. Inspected spark plugs, no deposits noted, engine timing right magneto 25° BTDC, left magneto 25° BTDC. Inspected horizontal stabilator forward spar crack as required by Vans Aircraft Service Bulletin 14-03-01. Found no cracks. Inspected the elevator spar web near the elevator attach points for cracks as required by Vans Aircraft Service Bulletin 14-02-03. Found no cracks.",
                laborHours: 8.0, equipmentIds: nil),
            Job(recurringId: 14, name: "Transponder Certification",
                entry: "Tested transponnder IAW 14 CFR 91.414 and found to comply with Part 43, App F.",
                laborHours: 0.7, equipmentIds: nil),
            Job(recurringId: 15, name: "ELT",
                entry: "Performed ELT Inspection and test",
                laborHours: 1.0, equipmentIds: nil),
            Job(recurringId: 16, name: "Propeller Overhaul",
                entry: "Performed propeller overhaul IAW applicable Hartzell  directives",
                laborHours: 12.0, equipmentIds: nil),
            Job(recurringId: 18, name: "Rotate Sparkplugs",
                entry: "Removed and inspected spark plugs, all look clean. Rotated sparks plug (bottom to top, top to bottom of next cylinder in firing order). Torqued to 35 ft-lbs.",
                laborHours: 0.5, equipmentIds: nil),
            Job(recurringId: 20, name: "Pitot Static Certification",
                entry: "Tested pitot static system IAW 14 CFR 91.411 to 20,000 ft and found to comply with Part 43, App E.",
                laborHours: 4.0, equipmentIds: nil)
        ]
    )

    static func decode(_ data: Data) throws -> HangarData {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(HangarData.self, from: data)
    }
}

// MARK: - Entries made on the phone

enum EntryStatus: String, Codable {
    case draft
    case sent      // added to Claude Logbook Import.txt
}

struct LogEntry: Identifiable, Codable, Hashable {
    var id = UUID()
    var created = Date()
    var updated = Date()
    var workDate = Date()
    var hobbs = ""
    var laborHours = ""
    var performedById: Int = HangarData.ownerId
    var performedByName: String = HangarData.ownerName
    /// The job button picked: a Recurring Maintenance name, or Squawk repair / Modification / Other.
    var job = ""
    var recurringId: Int = 0
    var equipmentIds: [Int] = []
    /// The logbook entry text (body only; the label prints date, time and signature).
    var text = ""
    var audioFileName: String?
    var photoFileNames: [String] = []
    var status: EntryStatus = .draft
    var sentAt: Date?

    var title: String { job.isEmpty ? "Entry" : job }

    var summaryLine: String {
        let first = text.split(whereSeparator: \.isNewline).first.map(String.init)?
            .trimmingCharacters(in: .whitespaces) ?? ""
        return first.isEmpty ? "(no entry text yet)" : first
    }
}
