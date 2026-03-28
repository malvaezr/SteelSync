import SwiftUI

// MARK: - Widget Theme Colors

/// Color constants for widgets. Mirrors AppTheme but self-contained for the widget extension.
enum WidgetColors {
    static let orange = Color(hex: "FF6B35")
    static let green = Color(hex: "1B4332")
    static let red = Color.red
    static let bidBlue = Color.blue
    static let bidTeal = Color.teal
    static let primaryText = Color.primary
    static let secondaryText = Color.secondary
    static let tertiaryText = Color.secondary.opacity(0.6)
    static let divider = Color.secondary.opacity(0.3)
    static let widgetBackground = Color(hex: "1C1C1E")
}

// MARK: - Color Hex Extension (self-contained for widget target)

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

// MARK: - Formatting Helpers

func formatCurrency(_ value: Double) -> String {
    let formatter = NumberFormatter()
    formatter.numberStyle = .currency
    formatter.currencyCode = "USD"
    formatter.maximumFractionDigits = 0
    return formatter.string(from: NSNumber(value: value)) ?? "$0"
}

func formatCurrencyCompact(_ value: Double) -> String {
    if value >= 1_000_000 {
        return String(format: "$%.1fM", value / 1_000_000)
    } else if value >= 1_000 {
        return String(format: "$%.0fK", value / 1_000)
    } else {
        return formatCurrency(value)
    }
}

func formatRelativeDate(_ date: Date) -> String {
    let calendar = Calendar.current
    let now = Date()

    if calendar.isDateInToday(date) {
        return "Today"
    } else if calendar.isDateInTomorrow(date) {
        return "Tomorrow"
    } else {
        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: now), to: calendar.startOfDay(for: date)).day ?? 0
        if days < 0 {
            return "\(abs(days))d ago"
        } else if days <= 7 {
            return "In \(days)d"
        } else {
            return formatShortDate(date)
        }
    }
}

func formatShortDate(_ date: Date) -> String {
    let formatter = DateFormatter()
    formatter.dateFormat = "MMM d"
    return formatter.string(from: date)
}

func isDueSoon(_ date: Date) -> Bool {
    let threeDays = Calendar.current.date(byAdding: .day, value: 3, to: Date()) ?? Date()
    return date <= threeDays
}

// MARK: - Widget Background Modifier

import WidgetKit

extension View {
    /// Applies containerBackground on iOS 17+ (required for widget rendering).
    /// Deployment target is iOS 17.0, so containerBackground is always available.
    func widgetBackground() -> some View {
        self.containerBackground(for: .widget) {
            Color(UIColor.systemBackground)
        }
    }
}
