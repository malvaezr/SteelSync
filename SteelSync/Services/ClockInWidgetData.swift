import Foundation

/// Writes the "who's clocked in right now" snapshot to the shared App Group so
/// the CrewClockedInWidget can render it. Called by BOTH `WidgetBridge`
/// (Mac/iPad) and `WidgetDataPublisher` (phone) with one shared keyset, so the
/// two writers can never drift. On a device with no active session (e.g. the
/// Mac, where no one clocks in) it writes empties so the widget clears.
///
/// Read side: `WidgetDataStore.load()` in the widget target uses these exact
/// key strings — keep them in sync if you rename anything here.
enum ClockInWidgetData {
    enum Keys {
        static let count = "clockedInCount"
        static let project = "clockedInProject"
        static let foreman = "clockedInForeman"
        static let since = "clockedInSince"            // shift open, epoch seconds (0 = none)
        static let names = "clockedInNames"            // [String], still-on-clock members
        static let memberSince = "clockedInMemberSince" // [Double] epoch, per member
    }

    static func write(to defaults: UserDefaults, session: ClockInSession?, employees: [Employee]) {
        guard let s = session else {
            defaults.set(0, forKey: Keys.count)
            defaults.set("", forKey: Keys.project)
            defaults.set("", forKey: Keys.foreman)
            defaults.set(0.0, forKey: Keys.since)
            defaults.set([String](), forKey: Keys.names)
            defaults.set([Double](), forKey: Keys.memberSince)
            return
        }
        // Only members still on the clock (early-departed members drop off the
        // live widget, matching the in-app view).
        let onClock = s.stillOnClockIDs
        let names: [String] = onClock.map { id in
            employees.first { $0.id.uuidString == id }?.fullName ?? "Crew"
        }
        let sinces: [Double] = onClock.map { s.startTime(for: $0).timeIntervalSince1970 }

        defaults.set(onClock.count, forKey: Keys.count)
        defaults.set(s.projectName, forKey: Keys.project)
        defaults.set(s.foremanName, forKey: Keys.foreman)
        defaults.set(s.clockInTime.timeIntervalSince1970, forKey: Keys.since)
        defaults.set(names, forKey: Keys.names)
        defaults.set(sinces, forKey: Keys.memberSince)
    }
}
