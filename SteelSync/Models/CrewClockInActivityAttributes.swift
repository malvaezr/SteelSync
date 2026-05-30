import Foundation
#if os(iOS)
import ActivityKit

// MARK: - Crew Clocked-In Live Activity (Glass spec §6.6)
//
// ActivityKit attributes shared between the main app (starts/updates/ends)
// and the widget extension (renders Lock Screen + Dynamic Island). Whole
// file is `#if os(iOS)` because ActivityKit is iOS-only.

/// Static properties of the clocked-in session — set when the foreman
/// clocks the crew in, never change while the session is active.
public struct CrewClockInActivityAttributes: ActivityAttributes {

    /// Dynamic portion — published every time the foreman adjusts the crew
    /// roster mid-shift OR on routine timer ticks if we ever want a live
    /// elapsed counter. Today the elapsed counter is computed by the widget
    /// from `clockInTime` so we don't have to push frequent updates.
    public struct ContentState: Codable, Hashable {
        public var crewCount: Int
        public var notes: String  // free-form, e.g. "On break since 12:15"
        public init(crewCount: Int, notes: String = "") {
            self.crewCount = crewCount
            self.notes = notes
        }
    }

    public var projectName: String
    public var foremanName: String
    public var clockInTime: Date

    public init(projectName: String, foremanName: String, clockInTime: Date) {
        self.projectName = projectName
        self.foremanName = foremanName
        self.clockInTime = clockInTime
    }
}

#endif
