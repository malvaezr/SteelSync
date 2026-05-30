import Foundation

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
}
