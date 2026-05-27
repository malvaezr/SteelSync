import SwiftUI

// MARK: - Glass Design System (Liquid-Glass revamp · Mac + iPad)
//
// Presentation-only token layer per `SteelSync-Glass-Design-System-Mac-iPad.md`
// + `steelsync-glass-reference.html` (reference wins on exact values). Tokens
// are skin- + theme-aware via `ThemeManager` (graphite/forge × dark/light).
// `AppTheme`'s global colors route here when `ThemeManager.glassEnabled`.

enum GlassSkin: String, CaseIterable, Codable, Identifiable {
    case graphite, forge
    var id: String { rawValue }
    var displayName: String { self == .graphite ? "Graphite" : "Forge" }
}

enum GlassDensity: String, CaseIterable, Codable, Identifiable {
    case comfortable, compact
    var id: String { rawValue }
    var displayName: String { self == .comfortable ? "Comfortable" : "Compact" }
    var rowHeight: CGFloat { self == .comfortable ? 42 : 30 }
    var barHeight: CGFloat { self == .comfortable ? 22 : 16 }
    var rowPad: CGFloat { self == .comfortable ? 11 : 7 }
}

enum Glass {
    // Layout constants (reference)
    static let sidebarWidth: CGFloat = 240
    static let topBarHeight: CGFloat = 60

    private static var dark: Bool { ThemeManager.shared.isDarkMode }
    private static var forgeDark: Bool { dark && ThemeManager.shared.glassSkin == .forge }

    // MARK: Text
    static var textPrimary: Color {
        guard dark else { return Color(hex: "#1c1c1e") }
        return forgeDark ? Color(hex: "#fbefe2") : Color.white.opacity(0.95)
    }
    static var textSecondary: Color {
        guard dark else { return Color(hex: "#6b6b70") }
        return forgeDark ? Color(hex: "#fbefe2").opacity(0.60) : Color.white.opacity(0.62)
    }
    static var textTertiary: Color {
        guard dark else { return Color(hex: "#9a9aa0") }
        return forgeDark ? Color(hex: "#fbefe2").opacity(0.40) : Color.white.opacity(0.42)
    }

    // MARK: Surfaces
    /// Solid base behind content (AppTheme.background fallback).
    static var windowBase: Color { dark ? Color(hex: "#0a0b0f") : Color(hex: "#e9e9ec") }
    /// Chrome fill used as the reduce-transparency / solid fallback for blur surfaces.
    static var chrome: Color { dark ? Color(hex: "#101218").opacity(0.92) : Color.white.opacity(0.80) }
    static var panel: Color {
        guard dark else { return Color.white.opacity(0.60) }
        return forgeDark ? Color(hex: "#ffd2aa").opacity(0.07) : Color.white.opacity(0.06)
    }
    static var panelStrong: Color {
        guard dark else { return Color.white.opacity(0.85) }
        return forgeDark ? Color(hex: "#ffd2aa").opacity(0.11) : Color.white.opacity(0.10)
    }
    static var row: Color {
        guard dark else { return Color.white.opacity(0.50) }
        return forgeDark ? Color(hex: "#ffd2aa").opacity(0.05) : Color.white.opacity(0.04)
    }
    static var rowHover: Color {
        guard dark else { return Color.white.opacity(0.78) }
        return forgeDark ? Color(hex: "#ffd2aa").opacity(0.08) : Color.white.opacity(0.07)
    }

    // MARK: Lines
    static var hairline: Color {
        guard dark else { return Color.black.opacity(0.10) }
        return forgeDark ? Color(hex: "#ffcda0").opacity(0.12) : Color.white.opacity(0.10)
    }
    static var hairlineStrong: Color {
        guard dark else { return Color.black.opacity(0.16) }
        return forgeDark ? Color(hex: "#ffcda0").opacity(0.20) : Color.white.opacity(0.16)
    }
    static var divider: Color { dark ? Color.white.opacity(0.07) : Color.black.opacity(0.08) }
    static var specularColor: Color {
        guard dark else { return Color.white.opacity(0.70) }
        return forgeDark ? Color(hex: "#ffd7af").opacity(0.14) : Color.white.opacity(0.12)
    }

    // MARK: Accent (one accent — safety orange)
    static var accent: Color { dark ? Color(hex: "#ff7a1a") : Color(hex: "#e0590c") }
    static var accentBright: Color { dark ? Color(hex: "#ff9554") : Color(hex: "#d8540b") }
    static var accentSoft: Color { accent.opacity(0.18) }
    static var accentRing: Color { accent.opacity(0.50) }
    static var textOnAccent: Color { dark ? Color(hex: "#1a0e04") : .white }

    // MARK: Semantic
    static let info = Color(hex: "#4d9bff"); static let infoBright = Color(hex: "#7fb8ff")
    static let success = Color(hex: "#34c759"); static let successBright = Color(hex: "#5bd178")
    static let warning = Color(hex: "#ffb340"); static let warningBright = Color(hex: "#ffc56b")
    static let danger = Color(hex: "#ff453a"); static let dangerBright = Color(hex: "#ff6b61")
    static let sub = Color(hex: "#b39cff")
    static func soft(_ c: Color) -> Color { c.opacity(0.18) }

    // MARK: Category (Gantt / chips)
    static let catFabrication = Color(hex: "#b39cff")
    static let catDelivery = Color(hex: "#4d9bff")
    static let catErection = Color(hex: "#ff7a1a")
    static let catInspection = Color(hex: "#34c759")
    static let catLead = Color(hex: "#8a93a3")
    static let catRFI = Color(hex: "#5dd0c0")
    static let catDeadline = Color(hex: "#ff453a")
    static let catMeeting = Color(hex: "#c98fe0")
    static let catPayApp = Color(hex: "#ffb340")
}

// MARK: - Wallpaper

/// The graphite/forge "wallpaper" behind the whole app (§2.1–2.3). Place once
/// at the window root, `.ignoresSafeArea()`. Glass chrome blurs over this.
struct GlassWallpaper: View {
    @ObservedObject private var tm = ThemeManager.shared

    var body: some View {
        let dark = tm.isDarkMode
        let forge = tm.glassSkin == .forge
        ZStack {
            if !dark {
                // Light field-use
                LinearGradient(colors: [Color(hex: "#f4f4f6"), Color(hex: "#e9e9ec")],
                               startPoint: .topLeading, endPoint: .bottomTrailing)
                RadialGradient(colors: [Glass.accent.opacity(0.10), .clear],
                               center: UnitPoint(x: 0.85, y: -0.10), startRadius: 0, endRadius: 900)
            } else if forge {
                LinearGradient(colors: [Color(hex: "#261d14"), Color(hex: "#15110c")],
                               startPoint: .topLeading, endPoint: .bottomTrailing)
                RadialGradient(colors: [Color(hex: "#ff7828").opacity(0.34), .clear],
                               center: UnitPoint(x: 0.82, y: -0.05), startRadius: 0, endRadius: 1100)
            } else {
                // Graphite (default)
                Color(hex: "#0a0b0f")
                RadialGradient(colors: [Color(hex: "#2b2e3c"), Color(hex: "#14151b"), Color(hex: "#0a0b0f")],
                               center: UnitPoint(x: 0.82, y: -0.10), startRadius: 0, endRadius: 1500)
                RadialGradient(colors: [Color(hex: "#ff6e28").opacity(0.16), .clear],
                               center: UnitPoint(x: 0.12, y: 1.15), startRadius: 0, endRadius: 800)
            }
        }
        .ignoresSafeArea()
    }
}

// MARK: - Glass surface modifiers

extension View {
    /// Frosted chrome surface (sidebar, top/nav bar, modals): material blur +
    /// hairline border + specular top highlight. Honors reduce-transparency.
    func glassChrome(cornerRadius: CGFloat = 0) -> some View {
        modifier(GlassChromeModifier(cornerRadius: cornerRadius))
    }
    /// Solid translucent panel (cards, KPI tiles) — NO blur — + hairline + specular.
    func glassPanel(cornerRadius: CGFloat = 12, strong: Bool = false) -> some View {
        self
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(strong ? Glass.panelStrong : Glass.panel)
            )
            .specularTop(cornerRadius: cornerRadius)
            .hairlineBorder(cornerRadius: cornerRadius)
    }
    /// List-row fill — NO blur.
    func glassRow(cornerRadius: CGFloat = 12, hover: Bool = false) -> some View {
        self.background(
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(hover ? Glass.rowHover : Glass.row)
        )
    }
    /// 1pt top inset highlight (specular).
    func specularTop(cornerRadius: CGFloat) -> some View {
        overlay(
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .stroke(
                    LinearGradient(colors: [Glass.specularColor, .clear],
                                   startPoint: .top, endPoint: .center),
                    lineWidth: 1
                )
                .allowsHitTesting(false)
        )
    }
    func hairlineBorder(cornerRadius: CGFloat, strong: Bool = false) -> some View {
        overlay(
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .strokeBorder(strong ? Glass.hairlineStrong : Glass.hairline, lineWidth: 1)
                .allowsHitTesting(false)
        )
    }
    /// Tabular monospaced digits — the app's signature for any figure.
    func monoDigits() -> some View { monospacedDigit() }

    // MARK: Toggle-aware surfaces
    //
    // These bridge Phase 1 tokens to the Phase 2 "form": when the glass design
    // is on they apply the translucent panel/row treatment (fill + specular +
    // hairline); when off they fall back to the legacy `AppTheme` card/row fill
    // so the original themes render unchanged. Use these in screens instead of
    // the raw `glassPanel`/`glassRow` so the Settings toggle is honored.

    /// Card / KPI-tile / section surface (honors the glass toggle).
    @ViewBuilder
    func appPanel(cornerRadius: CGFloat = 12, strong: Bool = false) -> some View {
        if ThemeManager.shared.glassEnabled {
            glassPanel(cornerRadius: cornerRadius, strong: strong)
        } else {
            background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(AppTheme.cardBackground)
            )
        }
    }

    /// Screen-root background under the "hybrid" wallpaper policy: overview
    /// screens (Today, dashboards) pass `wallpaper: true` to let the graphite
    /// gradient glow through behind their translucent panels; dense data
    /// screens leave it false and sit on flat graphite for legibility. Legacy
    /// themes always get their flat `AppTheme.background`.
    @ViewBuilder
    func glassScreenBackground(_ wallpaper: Bool = true) -> some View {
        if ThemeManager.shared.glassEnabled && wallpaper {
            background { GlassWallpaper() }
        } else {
            background(AppTheme.background)
        }
    }

    /// List-row surface (honors the glass toggle). No blur either way.
    @ViewBuilder
    func appRow(cornerRadius: CGFloat = 12, hover: Bool = false) -> some View {
        if ThemeManager.shared.glassEnabled {
            glassRow(cornerRadius: cornerRadius, hover: hover)
        } else {
            background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(AppTheme.secondaryBackground)
            )
        }
    }
}

// MARK: - Category chip (leading 28pt tinted square — list rows & KPI tiles)

/// The leading icon "chip" used on glass rows and KPI tiles (§4): a 28pt rounded
/// square tinted with a soft semantic color and a brighter glyph.
struct GlassChip: View {
    let systemImage: String
    let color: Color
    var brightText: Color? = nil
    var size: CGFloat = 28

    var body: some View {
        RoundedRectangle(cornerRadius: 8, style: .continuous)
            .fill(color.opacity(0.18))
            .frame(width: size, height: size)
            .overlay(
                Image(systemName: systemImage)
                    .font(.system(size: size * 0.46, weight: .semibold))
                    .foregroundColor(brightText ?? color)
            )
    }
}

private struct GlassChromeModifier: ViewModifier {
    let cornerRadius: CGFloat
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    func body(content: Content) -> some View {
        Group {
            if reduceTransparency {
                content.background(
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous).fill(Glass.chrome)
                )
            } else {
                content.background(.regularMaterial, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            }
        }
        .specularTop(cornerRadius: cornerRadius)
        .hairlineBorder(cornerRadius: cornerRadius)
    }
}

// MARK: - Status pill (soft fill + bright text, mono numerals, always labeled)

struct GlassPill: View {
    let text: String
    let color: Color
    var brightText: Color? = nil
    var critical: Bool = false

    var body: some View {
        Text(text)
            .font(.system(size: 11, weight: .medium))
            .monospacedDigit()
            .foregroundColor(brightText ?? color)
            .padding(.horizontal, 9)
            .padding(.vertical, 3)
            .background(Capsule().fill(color.opacity(0.18)))
            .overlay(critical ? Capsule().strokeBorder(Glass.danger, lineWidth: 1.5) : nil)
    }
}

// MARK: - GroupBox style
//
// Turns every `GroupBox` in the app into a glass panel: a styled label header
// (when one is given) over a translucent panel + specular + hairline. Applied
// app-wide via `.glassGroupBoxes()` so the many data screens (Reports,
// Equipment, Overhead, Clients, Settings, detail views) pick it up at once.

struct GlassGroupBoxStyle: GroupBoxStyle {
    func makeBody(configuration: Configuration) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            // Empty for `GroupBox { … }` (self-titled content) — contributes no
            // row, so no stray gap; styled header for `GroupBox("Title") { … }`.
            configuration.label
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(AppTheme.secondaryText)
            configuration.content
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .appPanel(cornerRadius: 14)
    }
}

extension View {
    /// Apply the glass panel look to every GroupBox in the subtree while the
    /// glass design is on; leave the system GroupBox intact otherwise.
    @ViewBuilder
    func glassGroupBoxes() -> some View {
        if ThemeManager.shared.glassEnabled {
            groupBoxStyle(GlassGroupBoxStyle())
        } else {
            self
        }
    }
}
