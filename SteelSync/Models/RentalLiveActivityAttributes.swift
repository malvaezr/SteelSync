import Foundation
#if os(iOS)
import ActivityKit

// MARK: - Equipment Rental Live Activity Attributes
//
// ActivityKit attributes shared between the main app (which starts/updates/
// ends the activity) and the widget extension (which renders the lock-screen
// + Dynamic Island views). Gated on `canImport(ActivityKit)` because the
// framework is iOS-only; Mac targets that include this file in their source
// tree just see an empty translation unit.

/// Static (immutable) properties of a rental Live Activity — set once when
/// the activity starts and never change. Use `ContentState` for the dynamic
/// numbers (day count, cutoff countdown).
public struct RentalActivityAttributes: ActivityAttributes {

    /// Mutable portion of the activity — pushed/updated to drive the visible
    /// content. Lives in `Activity<RentalActivityAttributes>.contentState`.
    public struct ContentState: Codable, Hashable {
        /// Days since `startDate` at the time the state was published.
        public var daysOnRent: Int

        /// Days until the next 28-day rate-tier cutoff. Negative means the
        /// rental has already crossed into the new cycle.
        public var nextCutoffDays: Int

        /// Free-form status string — "On Rent", "Pickup Requested", etc.
        public var status: String

        public init(daysOnRent: Int, nextCutoffDays: Int, status: String) {
            self.daysOnRent = daysOnRent
            self.nextCutoffDays = nextCutoffDays
            self.status = status
        }
    }

    /// Equipment display name (e.g. "10k Telehandler").
    public var equipmentName: String

    /// Project this rental is charged to.
    public var projectName: String

    /// When the rental began — drives the day-count math and is shown as a
    /// "since" date on the lock screen.
    public var startDate: Date

    public init(equipmentName: String, projectName: String, startDate: Date) {
        self.equipmentName = equipmentName
        self.projectName = projectName
        self.startDate = startDate
    }
}

#endif
