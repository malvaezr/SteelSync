import Foundation

/// Soft confirmation gate for destructive actions (delete payment, delete
/// project, etc.). Stored in `UserDefaults` per device — this isn't real
/// security, just a guard against accidental clicks. The PIN is shared by
/// all destructive actions that opt in.
///
/// Default value is `"1234"`. Users can change it in Settings, and there's
/// always a "Reset to default" option that doesn't require knowing the
/// current PIN — the recovery path the user asked for, since this isn't
/// auth-grade and a forgotten PIN shouldn't lock them out of their own data.
enum PinService {
    static let defaultPin = "1234"
    private static let key = "SteelSync.confirmationPin"

    /// The PIN currently in effect. Falls back to `defaultPin` when nothing
    /// is stored, so brand-new installs already work with `1234`.
    static var currentPin: String {
        UserDefaults.standard.string(forKey: key) ?? defaultPin
    }

    /// True when the user is still on the factory default. Surfaced in
    /// Settings so they know to change it if they care.
    static var isUsingDefault: Bool {
        currentPin == defaultPin
    }

    /// Replace the stored PIN. Caller is expected to validate that
    /// `newPin` is exactly 4 digits before calling this.
    static func setPin(_ newPin: String) {
        UserDefaults.standard.set(newPin, forKey: key)
    }

    /// Reset to the factory default. Does NOT require knowing the previous
    /// PIN — that's the recovery path for users who forgot it.
    static func resetToDefault() {
        UserDefaults.standard.set(defaultPin, forKey: key)
    }

    /// Verify an entered PIN against the stored one. Comparison is exact.
    static func verify(_ entered: String) -> Bool {
        entered == currentPin
    }

    /// Validation helper for input fields.
    static func isValidPinFormat(_ candidate: String) -> Bool {
        candidate.count == 4 && candidate.allSatisfy(\.isNumber)
    }
}
