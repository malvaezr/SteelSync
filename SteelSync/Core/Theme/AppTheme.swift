
import SwiftUI

// MARK: - Canonical Icons

/// Canonical SF Symbol names for SteelSync. Use these instead of hard-coded strings
/// so the same concept always gets the same glyph throughout the app.
/// Name by *meaning* (money, location), not by glyph (dollarsign, mappin), so swapping
/// the symbol later is a single-line change.
enum AppIcons {
    // Money / Finance
    static let money = "dollarsign.circle.fill"
    static let invoice = "doc.text.fill"
    static let payment = "creditcard.fill"
    static let cost = "cart.fill"

    // Place / Address
    static let location = "mappin.and.ellipse"
    static let building = "building.2.fill"

    // Documents
    static let document = "doc.text.fill"
    static let pdf = "doc.richtext.fill"
    static let attachment = "paperclip"

    // People
    static let person = "person.fill"
    static let people = "person.2.fill"
    static let crew = "person.3.fill"

    // Time
    static let calendar = "calendar"
    static let clock = "clock.fill"
    static let history = "clock.arrow.circlepath"

    // Status
    static let warning = "exclamationmark.triangle.fill"
    static let success = "checkmark.circle.fill"
    static let pinned = "pin.fill"

    // Equipment
    static let equipment = "shippingbox.fill"
    static let tools = "wrench.and.screwdriver.fill"

    // Actions
    static let add = "plus"
    static let edit = "pencil"
    static let delete = "trash"
    static let save = "square.and.arrow.down"
    static let share = "square.and.arrow.up"
    static let search = "magnifyingglass"
    static let filter = "line.3.horizontal.decrease.circle"

    // Navigation
    static let menu = "ellipsis.circle"
    static let settings = "gearshape.fill"
}

// MARK: - Button Styles
//
// Three semantic button styles used app-wide. Use these instead of mixing
// .borderedProminent / .bordered / .plain so the visual hierarchy stays clear:
//
//   .buttonStyle(.appPrimary)      — main call-to-action, one per screen
//   .buttonStyle(.appSecondary)    — supporting actions (Cancel, alternate paths)
//   .buttonStyle(.appDestructive)  — anything that deletes / removes data

private enum AppButtonMetrics {
    static let radius: CGFloat = 10
    static let hPadding: CGFloat = 16
    static let vPadding: CGFloat = 10
    static let minHeight: CGFloat = 36
    static let font: Font = .system(size: 14, weight: .semibold)
}

/// Applied to every button label so text shrinks (down to 65%) and tightens
/// before breaking across lines — and when it does wrap, it wraps at word
/// boundaries instead of chopping `Biddi-ng`.
private struct FitButtonLabel: ViewModifier {
    func body(content: Content) -> some View {
        content
            .lineLimit(2)
            .minimumScaleFactor(0.65)
            .allowsTightening(true)
            .multilineTextAlignment(.center)
            .truncationMode(.tail)
    }
}

struct AppPrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(AppButtonMetrics.font)
            .modifier(FitButtonLabel())
            .padding(.horizontal, AppButtonMetrics.hPadding)
            .padding(.vertical, AppButtonMetrics.vPadding)
            .frame(minHeight: AppButtonMetrics.minHeight)
            .background(
                RoundedRectangle(cornerRadius: AppButtonMetrics.radius, style: .continuous)
                    .fill(AppTheme.primaryOrange)
                    .brightness(configuration.isPressed ? -0.05 : 0)
            )
            .overlay(
                RoundedRectangle(cornerRadius: AppButtonMetrics.radius, style: .continuous)
                    .strokeBorder(AppTheme.accentForeground.opacity(0.12), lineWidth: 0.5)
            )
            .foregroundColor(AppTheme.accentForeground)
            .shadow(color: AppTheme.primaryOrange.opacity(configuration.isPressed ? 0.0 : 0.22),
                    radius: 6, x: 0, y: 2)
            .scaleEffect(configuration.isPressed ? 0.985 : 1.0)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

struct AppSecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 14, weight: .medium))
            .modifier(FitButtonLabel())
            .padding(.horizontal, AppButtonMetrics.hPadding)
            .padding(.vertical, AppButtonMetrics.vPadding)
            .frame(minHeight: AppButtonMetrics.minHeight)
            .background(
                RoundedRectangle(cornerRadius: AppButtonMetrics.radius, style: .continuous)
                    .fill(AppTheme.primaryText.opacity(configuration.isPressed ? 0.10 : 0.06))
            )
            .overlay(
                RoundedRectangle(cornerRadius: AppButtonMetrics.radius, style: .continuous)
                    .strokeBorder(AppTheme.primaryText.opacity(0.10), lineWidth: 0.5)
            )
            .foregroundColor(AppTheme.primaryText)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

struct AppDestructiveButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(AppButtonMetrics.font)
            .modifier(FitButtonLabel())
            .padding(.horizontal, AppButtonMetrics.hPadding)
            .padding(.vertical, AppButtonMetrics.vPadding)
            .frame(minHeight: AppButtonMetrics.minHeight)
            .background(
                RoundedRectangle(cornerRadius: AppButtonMetrics.radius, style: .continuous)
                    .fill(Color.red)
                    .brightness(configuration.isPressed ? -0.05 : 0)
            )
            .foregroundColor(.white)
            .shadow(color: Color.red.opacity(configuration.isPressed ? 0.0 : 0.22),
                    radius: 6, x: 0, y: 2)
            .scaleEffect(configuration.isPressed ? 0.985 : 1.0)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

struct AppOutlineButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 14, weight: .medium))
            .modifier(FitButtonLabel())
            .padding(.horizontal, AppButtonMetrics.hPadding)
            .padding(.vertical, AppButtonMetrics.vPadding)
            .frame(minHeight: AppButtonMetrics.minHeight)
            .background(
                RoundedRectangle(cornerRadius: AppButtonMetrics.radius, style: .continuous)
                    .fill(configuration.isPressed ? AppTheme.primaryOrange.opacity(0.08) : Color.clear)
            )
            .overlay(
                RoundedRectangle(cornerRadius: AppButtonMetrics.radius, style: .continuous)
                    .strokeBorder(AppTheme.primaryOrange.opacity(0.6), lineWidth: 1)
            )
            .foregroundColor(AppTheme.primaryOrange)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

struct AppGhostButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 14, weight: .medium))
            .modifier(FitButtonLabel())
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(AppTheme.primaryText.opacity(configuration.isPressed ? 0.08 : 0))
            )
            .foregroundColor(AppTheme.primaryText.opacity(configuration.isPressed ? 0.6 : 1))
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

extension ButtonStyle where Self == AppPrimaryButtonStyle {
    static var appPrimary: AppPrimaryButtonStyle { AppPrimaryButtonStyle() }
}

extension ButtonStyle where Self == AppSecondaryButtonStyle {
    static var appSecondary: AppSecondaryButtonStyle { AppSecondaryButtonStyle() }
}

extension ButtonStyle where Self == AppDestructiveButtonStyle {
    static var appDestructive: AppDestructiveButtonStyle { AppDestructiveButtonStyle() }
}

extension ButtonStyle where Self == AppOutlineButtonStyle {
    static var appOutline: AppOutlineButtonStyle { AppOutlineButtonStyle() }
}

extension ButtonStyle where Self == AppGhostButtonStyle {
    static var appGhost: AppGhostButtonStyle { AppGhostButtonStyle() }
}

// MARK: - TextField Style
//
// Softer, modern input field: tinted surface, hairline border, accent-tinted
// focus ring. Applied via `.textFieldStyle(.appField)`. Works for TextField
// and SecureField. For `Form` rows, keep the platform default — this style is
// intended for stacked/inline inputs in sheets and detail views.

struct AppFieldStyle: TextFieldStyle {
    var isFocused: Bool = false

    // swiftlint:disable:next identifier_name
    func _body(configuration: TextField<Self._Label>) -> some View {
        configuration
            .textFieldStyle(.plain)
            .font(.system(size: 14))
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .frame(minHeight: 36)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(AppTheme.secondaryBackground)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(
                        isFocused ? AppTheme.primaryOrange.opacity(0.55) : AppTheme.primaryText.opacity(0.08),
                        lineWidth: isFocused ? 1.5 : 0.5
                    )
            )
    }
}

extension TextFieldStyle where Self == AppFieldStyle {
    static var appField: AppFieldStyle { AppFieldStyle() }
}

/// Shared surface for non-TextField inputs (Picker, DatePicker) so they
/// visually match `.textFieldStyle(.appField)`.
struct AppControlSurface: ViewModifier {
    func body(content: Content) -> some View {
        content
            .frame(minHeight: 36)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(AppTheme.secondaryBackground)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(AppTheme.primaryText.opacity(0.08), lineWidth: 0.5)
            )
    }
}

extension View {
    /// Wrap a Picker / DatePicker / custom control so it matches `.appField` TextFields.
    func appControlSurface() -> some View { modifier(AppControlSurface()) }
}

/// Labeled field wrapper — label above input, optional help text below.
///
/// ```swift
/// LabeledField("Project Name") {
///     TextField("", text: $name).textFieldStyle(.appField)
/// }
/// ```
struct LabeledField<Content: View>: View {
    let label: String
    var helpText: String? = nil
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(AppTheme.secondaryText)
                .textCase(.uppercase)
                .tracking(0.4)
            content()
            if let helpText = helpText {
                Text(helpText)
                    .font(.caption2)
                    .foregroundColor(AppTheme.tertiaryText)
            }
        }
    }
}

// MARK: - Theme Definitions

enum AppColorTheme: String, CaseIterable, Codable {
    case flame = "Flame"
    case steelBlue = "Steel Blue"
    case ironForge = "Iron Forge"
    case rose = "Rose"

    // MARK: - Accent (same in light/dark)
    var accent: Color {
        switch self {
        case .flame: return Color(hex: "#FF6B35")
        case .steelBlue: return Color(hex: "#4A90D9")
        case .ironForge: return Color(hex: "#2ECC71")
        case .rose: return Color(hex: "#DB2777")
        }
    }

    /// Foreground color to use ON the accent (e.g. button text on a primary
    /// button). White on every saturated current accent passes contrast, but
    /// this exists so a future light/pastel accent can opt out without
    /// chasing every button-style call site.
    var accentForeground: Color {
        switch self {
        case .flame, .steelBlue, .ironForge, .rose: return .white
        }
    }

    var secondaryAccent: Color {
        switch self {
        case .flame: return Color(hex: "#1B4332")
        case .steelBlue: return Color(hex: "#1A3A5C")
        case .ironForge: return Color(hex: "#2C3E50")
        case .rose: return Color(hex: "#831843")
        }
    }

    // MARK: - Mode-aware colors

    func background(dark: Bool) -> Color {
        dark ? darkBg : lightBg
    }
    func secondaryBackground(dark: Bool) -> Color {
        dark ? darkSecBg : lightSecBg
    }
    func tertiaryBackground(dark: Bool) -> Color {
        dark ? darkTerBg : lightTerBg
    }
    func cardBackground(dark: Bool) -> Color {
        dark ? darkCardBg : lightCardBg
    }
    func sidebarBackground(dark: Bool) -> Color {
        dark ? darkSidebarBg : lightSidebarBg
    }
    func primaryText(dark: Bool) -> Color {
        dark ? darkPrimaryText : lightPrimaryText
    }
    func secondaryText(dark: Bool) -> Color {
        dark ? darkSecondaryText : lightSecondaryText
    }
    func tertiaryText(dark: Bool) -> Color {
        dark ? darkTertiaryText : lightTertiaryText
    }

    // MARK: - Dark palette

    private var darkBg: Color {
        switch self {
        case .flame: return Color(hex: "#1C1C1E")
        case .steelBlue: return Color(hex: "#0F1923")
        case .ironForge: return Color(hex: "#1A1F16")
        case .rose: return Color(hex: "#1E1015")
        }
    }
    private var darkSecBg: Color {
        switch self {
        case .flame: return Color(hex: "#2C2C2E")
        case .steelBlue: return Color(hex: "#162030")
        case .ironForge: return Color(hex: "#242B1E")
        case .rose: return Color(hex: "#2A1820")
        }
    }
    private var darkTerBg: Color {
        switch self {
        case .flame: return Color(hex: "#3A3A3C")
        case .steelBlue: return Color(hex: "#1E2D42")
        case .ironForge: return Color(hex: "#2E3726")
        case .rose: return Color(hex: "#3A1F2E")
        }
    }
    private var darkCardBg: Color {
        switch self {
        case .flame: return Color(hex: "#2C2C2E")
        case .steelBlue: return Color(hex: "#1A2940")
        case .ironForge: return Color(hex: "#273020")
        case .rose: return Color(hex: "#2E1A24")
        }
    }
    private var darkSidebarBg: Color {
        switch self {
        case .flame: return Color(hex: "#1C1C1E")
        case .steelBlue: return Color(hex: "#0C1520")
        case .ironForge: return Color(hex: "#151A12")
        case .rose: return Color(hex: "#180B11")
        }
    }
    private var darkPrimaryText: Color {
        switch self {
        case .flame: return .white
        case .steelBlue: return Color(hex: "#E8EDF2")
        case .ironForge: return Color(hex: "#E8F0E0")
        case .rose: return Color(hex: "#F5E3EB")
        }
    }
    private var darkSecondaryText: Color {
        switch self {
        case .flame: return Color(hex: "#EBEBF5").opacity(0.6)
        case .steelBlue: return Color(hex: "#8EACC8")
        case .ironForge: return Color(hex: "#9CB088")
        case .rose: return Color(hex: "#C8A0B0")
        }
    }
    private var darkTertiaryText: Color {
        switch self {
        case .flame: return Color(hex: "#EBEBF5").opacity(0.3)
        case .steelBlue: return Color(hex: "#5A7A98")
        case .ironForge: return Color(hex: "#6E8060")
        case .rose: return Color(hex: "#8E6878")
        }
    }

    // MARK: - Light palette

    private var lightBg: Color {
        switch self {
        case .flame: return Color(hex: "#F5F5F7")
        case .steelBlue: return Color(hex: "#EFF4F9")
        case .ironForge: return Color(hex: "#F0F5EC")
        case .rose: return Color(hex: "#FBF5F8")
        }
    }
    private var lightSecBg: Color {
        switch self {
        case .flame: return Color(hex: "#ECECEE")
        case .steelBlue: return Color(hex: "#E0EAF3")
        case .ironForge: return Color(hex: "#E2EBD8")
        case .rose: return Color(hex: "#F4E5EC")
        }
    }
    private var lightTerBg: Color {
        switch self {
        case .flame: return Color(hex: "#E0E0E2")
        case .steelBlue: return Color(hex: "#D0DFEE")
        case .ironForge: return Color(hex: "#D4E0C8")
        case .rose: return Color(hex: "#EAD2DD")
        }
    }
    private var lightCardBg: Color {
        switch self {
        case .flame: return .white
        case .steelBlue: return Color(hex: "#F5F8FC")
        case .ironForge: return Color(hex: "#F5FAF0")
        case .rose: return Color(hex: "#FFF7FA")
        }
    }
    private var lightSidebarBg: Color {
        switch self {
        case .flame: return Color(hex: "#ECECEE")
        case .steelBlue: return Color(hex: "#DDE8F2")
        case .ironForge: return Color(hex: "#DCE8D2")
        case .rose: return Color(hex: "#F0DCE5")
        }
    }
    private var lightPrimaryText: Color {
        switch self {
        case .flame: return Color(hex: "#1C1C1E")
        case .steelBlue: return Color(hex: "#0F1923")
        case .ironForge: return Color(hex: "#1A1F16")
        case .rose: return Color(hex: "#2A0F1A")
        }
    }
    private var lightSecondaryText: Color {
        switch self {
        case .flame: return Color(hex: "#636366")
        case .steelBlue: return Color(hex: "#4A6A88")
        case .ironForge: return Color(hex: "#5A7048")
        case .rose: return Color(hex: "#8B4A65")
        }
    }
    private var lightTertiaryText: Color {
        switch self {
        case .flame: return Color(hex: "#AEAEB2")
        case .steelBlue: return Color(hex: "#8AA0B8")
        case .ironForge: return Color(hex: "#8CA078")
        case .rose: return Color(hex: "#B888A0")
        }
    }

    // MARK: - Status
    var statusActive: Color {
        switch self {
        case .flame: return .green
        case .steelBlue: return Color(hex: "#4ADE80")
        case .ironForge: return Color(hex: "#2ECC71")
        case .rose: return Color(hex: "#10B981")
        }
    }

    // MARK: - Metadata
    var icon: String {
        switch self {
        case .flame: return "flame.fill"
        case .steelBlue: return "drop.fill"
        case .ironForge: return "hammer.fill"
        case .rose: return "heart.fill"
        }
    }

    var description: String {
        switch self {
        case .flame: return "Bold orange — the original"
        case .steelBlue: return "Cool blue — professional & clean"
        case .ironForge: return "Green — industrial & grounded"
        case .rose: return "Hot pink — bold & distinctive"
        }
    }
}

// MARK: - Theme Manager

class ThemeManager: ObservableObject {
    static let shared = ThemeManager()

    @Published var current: AppColorTheme {
        didSet { UserDefaults.standard.set(current.rawValue, forKey: "selectedTheme") }
    }

    @Published var isDarkMode: Bool {
        didSet { UserDefaults.standard.set(isDarkMode, forKey: "isDarkMode") }
    }

    var colorScheme: ColorScheme { isDarkMode ? .dark : .light }

    init() {
        let saved = UserDefaults.standard.string(forKey: "selectedTheme") ?? ""
        current = AppColorTheme(rawValue: saved) ?? .flame
        isDarkMode = UserDefaults.standard.object(forKey: "isDarkMode") as? Bool ?? true
    }
}

struct AppTheme {
    private static var theme: AppColorTheme { ThemeManager.shared.current }
    private static var dark: Bool { ThemeManager.shared.isDarkMode }

    // MARK: - Brand Colors (dynamic)
    static var primaryOrange: Color { theme.accent }
    static var primaryGreen: Color { theme.secondaryAccent }
    /// Foreground color that contrasts cleanly against `primaryOrange`
    /// (the theme accent). Used by primary / destructive button styles
    /// instead of a hardcoded `.white` so future themes with light
    /// accents can override.
    static var accentForeground: Color { theme.accentForeground }

    // MARK: - Full Palette (dynamic per theme + mode)
    static var background: Color { theme.background(dark: dark) }
    static var secondaryBackground: Color { theme.secondaryBackground(dark: dark) }
    static var tertiaryBackground: Color { theme.tertiaryBackground(dark: dark) }
    static var cardBackground: Color { theme.cardBackground(dark: dark) }
    static var primaryText: Color { theme.primaryText(dark: dark) }
    static var secondaryText: Color { theme.secondaryText(dark: dark) }
    static var tertiaryText: Color { theme.tertiaryText(dark: dark) }
    static var sidebarBackground: Color { theme.sidebarBackground(dark: dark) }

    // MARK: - Semantic Colors
    static let success = Color.green
    static let warning = Color.orange
    static let error = Color.red
    static let info = Color.blue

    // MARK: - Status Colors
    struct BidStatus {
        static let open = Color.blue
        static let workingOn = Color.yellow
        static let ready = Color.cyan
        static let submitted = Color.purple
        static let won = Color.green
        static let lost = Color.red
        static let pastDue = Color.orange
    }

    struct ProjectStatus {
        static var active: Color { ThemeManager.shared.current.statusActive }
        static let upcoming = Color.blue
        static let completed = Color.purple
        static let onHold = Color.orange
    }

    // MARK: - Typography
    struct Typography {
        static let largeTitle = Font.largeTitle.weight(.bold)
        static let title = Font.title.weight(.bold)
        static let title2 = Font.title2.weight(.semibold)
        static let title3 = Font.title3.weight(.semibold)
        static let headline = Font.headline
        static let body = Font.body
        static let callout = Font.callout
        static let subheadline = Font.subheadline
        static let footnote = Font.footnote
        static let caption = Font.caption
    }

    // MARK: - Spacing
    struct Spacing {
        static let xs: CGFloat = 4
        static let sm: CGFloat = 8
        static let md: CGFloat = 16
        static let lg: CGFloat = 24
        static let xl: CGFloat = 32
        static let xxl: CGFloat = 48
    }

    // MARK: - Corner Radius
    struct Radius {
        static let xs: CGFloat = 4
        static let sm: CGFloat = 8
        static let md: CGFloat = 12
        static let lg: CGFloat = 16
        static let xl: CGFloat = 20
    }

    // MARK: - Icon Size
    struct IconSize {
        static let small: CGFloat = 16
        static let medium: CGFloat = 20
        static let large: CGFloat = 24
        static let xlarge: CGFloat = 32
    }
}

// MARK: - Color Hex Extension
extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3:
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6:
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8:
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (255, 0, 0, 0)
        }
        self.init(.sRGB, red: Double(r) / 255, green: Double(g) / 255, blue: Double(b) / 255, opacity: Double(a) / 255)
    }
}

// MARK: - View Modifiers
extension View {
    func cardStyle() -> some View {
        self.padding(AppTheme.Spacing.md)
            .background(AppTheme.cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.md))
            .shadow(color: .black.opacity(0.05), radius: 2, x: 0, y: 1)
    }

    func primaryButtonStyle() -> some View {
        self.padding(.horizontal, AppTheme.Spacing.lg)
            .padding(.vertical, AppTheme.Spacing.sm)
            .background(AppTheme.primaryOrange)
            .foregroundColor(.white)
            .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.sm))
    }

    func secondaryButtonStyle() -> some View {
        self.padding(.horizontal, AppTheme.Spacing.lg)
            .padding(.vertical, AppTheme.Spacing.sm)
            .background(Color.clear)
            .foregroundColor(AppTheme.primaryOrange)
            .overlay(RoundedRectangle(cornerRadius: AppTheme.Radius.sm).stroke(AppTheme.primaryOrange, lineWidth: 1))
    }

    func sectionContainer() -> some View {
        self.padding(AppTheme.Spacing.md)
            .background(AppTheme.secondaryBackground)
            .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.md))
    }
}
