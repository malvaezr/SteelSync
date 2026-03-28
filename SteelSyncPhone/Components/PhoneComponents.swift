import SwiftUI

// MARK: - Compact Metric Row

/// Horizontal row of 3 compact metric items for dashboard display
struct CompactMetricRow: View {
    let items: [(icon: String, value: String, label: String)]

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Array(items.prefix(3).enumerated()), id: \.offset) { index, item in
                if index > 0 {
                    Divider()
                        .frame(height: 36)
                        .background(AppTheme.tertiaryText.opacity(0.3))
                }

                VStack(spacing: AppTheme.Spacing.xs) {
                    Image(systemName: item.icon)
                        .font(.system(size: 14))
                        .foregroundColor(AppTheme.primaryOrange)
                    Text(item.value)
                        .font(.system(size: 16, weight: .bold, design: .rounded))
                        
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                    Text(item.label)
                        .font(AppTheme.Typography.caption)
                        .foregroundColor(AppTheme.secondaryText)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity)
            }
        }
        .padding(AppTheme.Spacing.md)
        .background(AppTheme.secondaryBackground)
        .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.md))
    }
}

// MARK: - Clock Button

/// Large circular button for clock in/out with scale animation
struct ClockButton: View {
    let isClockedIn: Bool
    @State private var isPressed = false

    var body: some View {
        ZStack {
            // Outer ring
            Circle()
                .stroke(
                    isClockedIn ? Color.red.opacity(0.3) : AppTheme.primaryOrange.opacity(0.3),
                    lineWidth: 4
                )
                .frame(width: 120, height: 120)

            // Inner filled circle
            Circle()
                .fill(isClockedIn ? Color.red : AppTheme.primaryOrange)
                .frame(width: 100, height: 100)
                .shadow(color: (isClockedIn ? Color.red : AppTheme.primaryOrange).opacity(0.4), radius: 8, x: 0, y: 4)

            // Icon and text
            VStack(spacing: 4) {
                Image(systemName: isClockedIn ? "stop.fill" : "play.fill")
                    .font(.system(size: 28, weight: .bold))
                    .foregroundColor(.white)
                Text(isClockedIn ? "Clock Out" : "Clock In")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.white)
            }
        }
        .scaleEffect(isPressed ? 0.92 : 1.0)
        .animation(.easeInOut(duration: 0.15), value: isPressed)
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in isPressed = true }
                .onEnded { _ in isPressed = false }
        )
    }
}

// MARK: - Time Entry Row

/// Compact row showing time range, project, and hours worked
struct TimeEntryRow: View {
    let projectName: String
    let clockIn: Date
    let clockOut: Date
    let hours: Decimal

    private var timeRange: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm a"
        return "\(formatter.string(from: clockIn)) - \(formatter.string(from: clockOut))"
    }

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(projectName)
                    .font(AppTheme.Typography.subheadline)
                    .fontWeight(.medium)
                    
                Text(timeRange)
                    .font(AppTheme.Typography.caption)
                    .foregroundColor(AppTheme.secondaryText)
            }

            Spacer()

            Text(String(format: "%.2f hrs", NSDecimalNumber(decimal: hours).doubleValue))
                .font(.system(size: 14, weight: .semibold, design: .rounded))
                .foregroundColor(AppTheme.primaryOrange)
        }
        .padding(.vertical, AppTheme.Spacing.xs)
    }
}
