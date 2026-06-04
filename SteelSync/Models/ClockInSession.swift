import Foundation

/// An in-progress crew clock-in session — the foreman, the project, and the
/// crew members who are currently on the clock together. Persisted to
/// UserDefaults so the session survives app relaunches; cleared when the
/// foreman clocks out (which produces TimesheetEntries for everyone listed).
///
/// One active session per phone — the foreman either has their crew on the
/// clock or doesn't. Multiple concurrent sessions aren't supported by design
/// (a single device = a single foreman managing a single crew at a time).
///
/// Each crew member carries their OWN clock-in time (for late arrivals) and an
/// optional clock-out time (for early departures), so a single shift can hold
/// people who worked different windows. Worked hours are computed per member at
/// clock-out, then a 30-minute lunch is auto-deducted (see DataStore.endCrewClockIn).
struct ClockInSession: Codable, Equatable {
    /// `Employee.id.uuidString` for the foreman who started the session
    /// (the device's user). The roster picker uses this to identify them.
    var foremanID: String
    /// `Project.id.recordName` for the active project.
    var projectID: String
    /// `Employee.id.uuidString` for every crew member on this shift (including
    /// any who clocked out early — they stay listed so they still materialize
    /// a TimesheetEntry; their frozen end time lives in `memberClockOutTimes`).
    var crewMemberIDs: [String]
    /// The shift's opening time (the foreman's clock-in). Used for the banner
    /// timer and as the default per-member start for anyone present at the open.
    var clockInTime: Date

    /// Display name cache so the Live Activity / banner don't have to look
    /// the project back up if the project is renamed mid-shift.
    var projectName: String
    /// Foreman's display name cache for the same reason.
    var foremanName: String

    /// Per-member clock-in times (`Employee.id.uuidString` → Date). Members
    /// present at the shift open map to `clockInTime`; late arrivals carry their
    /// own later time.
    var memberClockInTimes: [String: Date]
    /// Per-member early clock-out times. Absent = still on the clock (their end
    /// time is resolved to the final clock-out moment).
    var memberClockOutTimes: [String: Date]

    /// Minutes of unpaid lunch to auto-deduct at clock-out (default 30). The
    /// deduction only applies when the member's worked span is long enough and
    /// the project/app settings allow it — see DataStore.endCrewClockIn.
    var lunchMinutes: Int
    /// Per-shift override: when `true`, skip the lunch deduction for everyone on
    /// this shift regardless of project/app defaults ("don't deduct today").
    var skipLunchDeduction: Bool

    init(
        foremanID: String,
        projectID: String,
        crewMemberIDs: [String],
        clockInTime: Date,
        projectName: String,
        foremanName: String,
        memberClockInTimes: [String: Date] = [:],
        memberClockOutTimes: [String: Date] = [:],
        lunchMinutes: Int = 30,
        skipLunchDeduction: Bool = false
    ) {
        self.foremanID = foremanID
        self.projectID = projectID
        self.crewMemberIDs = crewMemberIDs
        self.clockInTime = clockInTime
        self.projectName = projectName
        self.foremanName = foremanName
        self.memberClockInTimes = memberClockInTimes
        self.memberClockOutTimes = memberClockOutTimes
        self.lunchMinutes = lunchMinutes
        self.skipLunchDeduction = skipLunchDeduction
    }

    // MARK: - Per-member helpers

    /// A member's start time — their own clock-in, or the shift open if they
    /// were present from the start (or pre-dates the per-member tracking).
    func startTime(for memberID: String) -> Date {
        memberClockInTimes[memberID] ?? clockInTime
    }

    /// A member's end time — their early clock-out if they have one, else the
    /// passed `fallback` (the final clock-out moment).
    func endTime(for memberID: String, fallback: Date) -> Date {
        memberClockOutTimes[memberID] ?? fallback
    }

    /// `true` while a member is still on the clock (no early-out recorded).
    func isStillOnClock(_ memberID: String) -> Bool {
        memberClockOutTimes[memberID] == nil
    }

    /// Members who haven't clocked out early — still actively on the clock.
    var stillOnClockIDs: [String] {
        crewMemberIDs.filter { isStillOnClock($0) }
    }
}

extension ClockInSession {
    /// Custom decoder so sessions persisted by older builds still load: the
    /// per-member and lunch fields are tolerated as absent (and any legacy
    /// `breaks`/`currentBreakStart` keys are simply ignored). Placed in an
    /// extension to keep the synthesized memberwise initializer available.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        foremanID = try c.decode(String.self, forKey: .foremanID)
        projectID = try c.decode(String.self, forKey: .projectID)
        crewMemberIDs = try c.decode([String].self, forKey: .crewMemberIDs)
        clockInTime = try c.decode(Date.self, forKey: .clockInTime)
        projectName = try c.decode(String.self, forKey: .projectName)
        foremanName = try c.decode(String.self, forKey: .foremanName)
        memberClockInTimes = try c.decodeIfPresent([String: Date].self, forKey: .memberClockInTimes) ?? [:]
        memberClockOutTimes = try c.decodeIfPresent([String: Date].self, forKey: .memberClockOutTimes) ?? [:]
        lunchMinutes = try c.decodeIfPresent(Int.self, forKey: .lunchMinutes) ?? 30
        skipLunchDeduction = try c.decodeIfPresent(Bool.self, forKey: .skipLunchDeduction) ?? false
    }
}
