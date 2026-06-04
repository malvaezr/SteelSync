import Foundation
import Combine

/// App-wide payroll/clock defaults that aren't tied to a single project.
/// Persisted to UserDefaults (device-local). Per-project overrides live on
/// `Project.autoDeductLunch` and ride CloudKit so they stay consistent across
/// devices and the web portal; this holds only the fallback default.
///
/// Singleton accessed via `.shared` (mirrors `NotificationService`), so views
/// can observe it with `@ObservedObject` without any `.environmentObject` wiring.
/// Not main-actor isolated so `shouldDeductLunch`/`defaultLunchMinutes` can be
/// read from the clock-out path; the `@Published` values are only mutated from
/// the Settings UI on the main thread.
final class ProjectSettingsService: ObservableObject {
    static let shared = ProjectSettingsService()

    private enum Keys {
        static let autoDeductLunchDefault = "SteelSync.autoDeductLunchDefault"
        static let defaultLunchMinutes = "SteelSync.defaultLunchMinutes"
    }

    /// Whether a 30-minute lunch is auto-deducted at clock-out by default.
    /// A project may override this via `Project.autoDeductLunch`, and a foreman
    /// may skip it for one shift via the per-shift toggle.
    @Published var autoDeductLunchDefault: Bool {
        didSet { UserDefaults.standard.set(autoDeductLunchDefault, forKey: Keys.autoDeductLunchDefault) }
    }

    /// Minutes of unpaid lunch to deduct (default 30).
    @Published var defaultLunchMinutes: Int {
        didSet { UserDefaults.standard.set(defaultLunchMinutes, forKey: Keys.defaultLunchMinutes) }
    }

    private init() {
        let d = UserDefaults.standard
        // Default ON. `object(forKey:)` lets us distinguish "never set" (→ true)
        // from an explicit false the user chose.
        autoDeductLunchDefault = (d.object(forKey: Keys.autoDeductLunchDefault) as? Bool) ?? true
        let mins = d.integer(forKey: Keys.defaultLunchMinutes)
        defaultLunchMinutes = mins > 0 ? mins : 30
    }

    /// Resolve whether lunch should be deducted for a shift, applying the
    /// precedence: per-shift skip (off) → per-project override → app default.
    /// `projectAutoDeduct` is `Project.autoDeductLunch` (nil = inherit default).
    func shouldDeductLunch(projectAutoDeduct: Bool?, skipThisShift: Bool) -> Bool {
        if skipThisShift { return false }
        return projectAutoDeduct ?? autoDeductLunchDefault
    }
}
