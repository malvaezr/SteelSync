import Foundation

/// A single break/lunch window taken during a crew shift. Subtracted from the
/// raw clocked-in duration when the shift is closed so the materialized
/// TimesheetEntries reflect worked (paid) hours, not wall-clock time.
struct BreakInterval: Codable, Equatable {
    var start: Date
    var end: Date

    var seconds: TimeInterval { max(0, end.timeIntervalSince(start)) }
}

/// An in-progress crew clock-in session — the foreman, the project, and the
/// crew members who are currently on the clock together. Persisted to
/// UserDefaults so the session survives app relaunches; cleared when the
/// foreman clocks out (which produces TimesheetEntries for everyone listed).
///
/// One active session per phone — the foreman either has their crew on the
/// clock or doesn't. Multiple concurrent sessions aren't supported by design
/// (a single device = a single foreman managing a single crew at a time).
struct ClockInSession: Codable, Equatable {
    /// `Employee.id.uuidString` for the foreman who started the session
    /// (the device's user). The roster picker uses this to identify them.
    var foremanID: String
    /// `Project.id.recordName` for the active project.
    var projectID: String
    /// `Employee.id.uuidString` for every crew member currently clocked in
    /// (typically includes the foreman themselves if they're working too).
    var crewMemberIDs: [String]
    var clockInTime: Date

    /// Display name cache so the Live Activity / banner don't have to look
    /// the project back up if the project is renamed mid-shift.
    var projectName: String
    /// Foreman's display name cache for the same reason.
    var foremanName: String

    /// Completed break windows taken during this shift.
    var breaks: [BreakInterval]
    /// Start of an in-progress break, if the crew is currently paused.
    /// `nil` means the crew is actively working.
    var currentBreakStart: Date?

    init(
        foremanID: String,
        projectID: String,
        crewMemberIDs: [String],
        clockInTime: Date,
        projectName: String,
        foremanName: String,
        breaks: [BreakInterval] = [],
        currentBreakStart: Date? = nil
    ) {
        self.foremanID = foremanID
        self.projectID = projectID
        self.crewMemberIDs = crewMemberIDs
        self.clockInTime = clockInTime
        self.projectName = projectName
        self.foremanName = foremanName
        self.breaks = breaks
        self.currentBreakStart = currentBreakStart
    }

    /// `true` while the crew is on a break.
    var isOnBreak: Bool { currentBreakStart != nil }

    /// Total break time taken so far, including any in-progress break measured
    /// up to `asOf` (defaults to now).
    func totalBreakSeconds(asOf reference: Date = Date()) -> TimeInterval {
        var total = breaks.reduce(0.0) { $0 + $1.seconds }
        if let open = currentBreakStart {
            total += max(0, reference.timeIntervalSince(open))
        }
        return total
    }
}

extension ClockInSession {
    /// Custom decoder so sessions persisted before break-tracking shipped still
    /// load — the two break fields are tolerated as absent. Placed in an
    /// extension to keep the synthesized memberwise initializer available.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        foremanID = try c.decode(String.self, forKey: .foremanID)
        projectID = try c.decode(String.self, forKey: .projectID)
        crewMemberIDs = try c.decode([String].self, forKey: .crewMemberIDs)
        clockInTime = try c.decode(Date.self, forKey: .clockInTime)
        projectName = try c.decode(String.self, forKey: .projectName)
        foremanName = try c.decode(String.self, forKey: .foremanName)
        breaks = try c.decodeIfPresent([BreakInterval].self, forKey: .breaks) ?? []
        currentBreakStart = try c.decodeIfPresent(Date.self, forKey: .currentBreakStart)
    }
}
