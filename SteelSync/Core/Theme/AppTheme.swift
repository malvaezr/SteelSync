
import SwiftUI

// MARK: - Theme Definitions

enum AppColorTheme: String, CaseIterable, Codable {
    case flame = "Flame"
    case steelBlue = "Steel Blue"
    case ironForge = "Iron Forge"

    // MARK: - Accent (same in light/dark)
    var accent: Color {
        switch self {
        case .flame: return Color(hex: "#FF6B35")
        case .steelBlue: return Color(hex: "#4A90D9")
        case .ironForge: return Color(hex: "#2ECC71")
        }
    }

    var secondaryAccent: Color {
        switch self {
        case .flame: return Color(hex: "#1B4332")
        case .steelBlue: return Color(hex: "#1A3A5C")
        case .ironForge: return Color(hex: "#2C3E50")
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
        }
    }
    private var darkSecBg: Color {
        switch self {
        case .flame: return Color(hex: "#2C2C2E")
        case .steelBlue: return Color(hex: "#162030")
        case .ironForge: return Color(hex: "#242B1E")
        }
    }
    private var darkTerBg: Color {
        switch self {
        case .flame: return Color(hex: "#3A3A3C")
        case .steelBlue: return Color(hex: "#1E2D42")
        case .ironForge: return Color(hex: "#2E3726")
        }
    }
    private var darkCardBg: Color {
        switch self {
        case .flame: return Color(hex: "#2C2C2E")
        case .steelBlue: return Color(hex: "#1A2940")
        case .ironForge: return Color(hex: "#273020")
        }
    }
    private var darkSidebarBg: Color {
        switch self {
        case .flame: return Color(hex: "#1C1C1E")
        case .steelBlue: return Color(hex: "#0C1520")
        case .ironForge: return Color(hex: "#151A12")
        }
    }
    private var darkPrimaryText: Color {
        switch self {
        case .flame: return .white
        case .steelBlue: return Color(hex: "#E8EDF2")
        case .ironForge: return Color(hex: "#E8F0E0")
        }
    }
    private var darkSecondaryText: Color {
        switch self {
        case .flame: return Color(hex: "#EBEBF5").opacity(0.6)
        case .steelBlue: return Color(hex: "#8EACC8")
        case .ironForge: return Color(hex: "#9CB088")
        }
    }
    private var darkTertiaryText: Color {
        switch self {
        case .flame: return Color(hex: "#EBEBF5").opacity(0.3)
        case .steelBlue: return Color(hex: "#5A7A98")
        case .ironForge: return Color(hex: "#6E8060")
        }
    }

    // MARK: - Light palette

    private var lightBg: Color {
        switch self {
        case .flame: return Color(hex: "#F5F5F7")
        case .steelBlue: return Color(hex: "#EFF4F9")
        case .ironForge: return Color(hex: "#F0F5EC")
        }
    }
    private var lightSecBg: Color {
        switch self {
        case .flame: return Color(hex: "#ECECEE")
        case .steelBlue: return Color(hex: "#E0EAF3")
        case .ironForge: return Color(hex: "#E2EBD8")
        }
    }
    private var lightTerBg: Color {
        switch self {
        case .flame: return Color(hex: "#E0E0E2")
        case .steelBlue: return Color(hex: "#D0DFEE")
        case .ironForge: return Color(hex: "#D4E0C8")
        }
    }
    private var lightCardBg: Color {
        switch self {
        case .flame: return .white
        case .steelBlue: return Color(hex: "#F5F8FC")
        case .ironForge: return Color(hex: "#F5FAF0")
        }
    }
    private var lightSidebarBg: Color {
        switch self {
        case .flame: return Color(hex: "#ECECEE")
        case .steelBlue: return Color(hex: "#DDE8F2")
        case .ironForge: return Color(hex: "#DCE8D2")
        }
    }
    private var lightPrimaryText: Color {
        switch self {
        case .flame: return Color(hex: "#1C1C1E")
        case .steelBlue: return Color(hex: "#0F1923")
        case .ironForge: return Color(hex: "#1A1F16")
        }
    }
    private var lightSecondaryText: Color {
        switch self {
        case .flame: return Color(hex: "#636366")
        case .steelBlue: return Color(hex: "#4A6A88")
        case .ironForge: return Color(hex: "#5A7048")
        }
    }
    private var lightTertiaryText: Color {
        switch self {
        case .flame: return Color(hex: "#AEAEB2")
        case .steelBlue: return Color(hex: "#8AA0B8")
        case .ironForge: return Color(hex: "#8CA078")
        }
    }

    // MARK: - Status
    var statusActive: Color {
        switch self {
        case .flame: return .green
        case .steelBlue: return Color(hex: "#4ADE80")
        case .ironForge: return Color(hex: "#2ECC71")
        }
    }

    // MARK: - Metadata
    var icon: String {
        switch self {
        case .flame: return "flame.fill"
        case .steelBlue: return "drop.fill"
        case .ironForge: return "hammer.fill"
        }
    }

    var description: String {
        switch self {
        case .flame: return "Bold orange — the original"
        case .steelBlue: return "Cool blue — professional & clean"
        case .ironForge: return "Green — industrial & grounded"
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
