import Foundation
import CloudKit

/// Per-project daily site log entry.
///
/// Captures what happened on the job each day — weather, crew on site, work
/// completed, issues encountered, and photos. Used both for end-of-week
/// reporting to the GC and as substantiation for change-order requests
/// when scope creep shows up later.
///
/// Lives as a child of `Project` (per-project array on DataStore, mirrors
/// the ChangeOrder / RFI / Cost pattern).
struct DailyLog: Identifiable, Codable, Hashable {
    let id: UUID
    var date: Date
    /// Free-text weather. PMs jot "Sunny 78°F" or "Rain 9–11am". Not a
    /// structured field because the inputs vary too much.
    var weather: String
    /// Narrative of what got done that day.
    var workCompleted: String
    /// Problems / blockers / scope creep observed. Kept separate from
    /// `workCompleted` so it's easy to surface for CO substantiation.
    var issuesEncountered: String
    /// Employee UUID strings (Employee.id.uuidString) of who was on site.
    /// We store the UUID rather than the CKRecord name because Employee uses
    /// a UUID identity and `recordID` is optional.
    var crewOnSiteIDs: [String]
    /// Explicit total hours the PM enters. Independent from timesheets so
    /// site logs can still be filed for days nobody clocked in (subs only,
    /// foreman-only, etc.).
    var totalCrewHours: Decimal
    /// Empty when nothing happened. Free-text description otherwise.
    var safetyIncidentsNote: String
    /// Catch-all internal notes.
    var notes: String
    /// Photo + document attachments. Stored locally under the per-log
    /// folder; CKAssets round-trip the bytes across devices.
    var photos: [Attachment]
    var recordID: CKRecord.ID?
    var projectRef: CKRecord.Reference?

    enum CodingKeys: String, CodingKey {
        case id, date, weather, workCompleted, issuesEncountered
        case crewOnSiteIDs, totalCrewHours, safetyIncidentsNote, notes, photos
    }

    init(
        id: UUID = UUID(),
        date: Date = Date(),
        weather: String = "",
        workCompleted: String = "",
        issuesEncountered: String = "",
        crewOnSiteIDs: [String] = [],
        totalCrewHours: Decimal = 0,
        safetyIncidentsNote: String = "",
        notes: String = "",
        photos: [Attachment] = [],
        recordID: CKRecord.ID? = nil,
        projectRef: CKRecord.Reference? = nil
    ) {
        self.id = id
        self.date = date
        self.weather = weather
        self.workCompleted = workCompleted
        self.issuesEncountered = issuesEncountered
        self.crewOnSiteIDs = crewOnSiteIDs
        self.totalCrewHours = totalCrewHours
        self.safetyIncidentsNote = safetyIncidentsNote
        self.notes = notes
        self.photos = photos
        self.recordID = recordID
        self.projectRef = projectRef
    }

    /// Resolves crew employee IDs to live `Employee` objects (in the order
    /// they were entered). Caller filters out missing IDs (deleted employees).
    func crew(in employees: [Employee]) -> [Employee] {
        let ids = Set(crewOnSiteIDs)
        return employees.filter { ids.contains($0.id.uuidString) }
    }

    /// True when at least one of the substantive narrative fields has content.
    /// A log with only a date isn't really a log.
    var hasContent: Bool {
        !workCompleted.isEmpty
            || !issuesEncountered.isEmpty
            || !notes.isEmpty
            || !crewOnSiteIDs.isEmpty
            || !photos.isEmpty
    }
}
