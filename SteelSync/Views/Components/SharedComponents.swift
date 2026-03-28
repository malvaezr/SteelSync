import SwiftUI

// MARK: - Metric Card
struct MetricCard: View {
    let title: String
    let value: String
    let icon: String
    var color: Color = AppTheme.primaryOrange
    var subtitle: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.sm) {
            HStack {
                Image(systemName: icon)
                    .font(.system(size: 14))
                    .foregroundColor(color)
                Spacer()
            }

            Text(value)
                .font(.system(size: 20, weight: .bold, design: .rounded))
                .foregroundColor(AppTheme.primaryText)
                .lineLimit(1)
                .minimumScaleFactor(0.6)

            Text(title)
                .font(AppTheme.Typography.caption)
                .foregroundColor(AppTheme.secondaryText)

            if let subtitle = subtitle {
                Text(subtitle)
                    .font(.caption2)
                    .foregroundColor(AppTheme.tertiaryText)
            }
        }
        .cardStyle()
    }
}

// MARK: - Status Badge
struct StatusBadge: View {
    let text: String
    let color: Color

    var body: some View {
        Text(text)
            .font(.caption)
            .fontWeight(.semibold)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(color.opacity(0.15))
            .foregroundColor(color)
            .clipShape(Capsule())
    }
}

// MARK: - Info Row
struct InfoRow: View {
    let label: String
    let value: String
    var icon: String? = nil

    var body: some View {
        HStack {
            if let icon = icon {
                Image(systemName: icon)
                    .foregroundColor(.secondary)
                    .frame(width: 20)
            }
            Text(label)
                .foregroundColor(AppTheme.secondaryText)
                .layoutPriority(1)
            Spacer(minLength: 8)
            Text(value)
                .fontWeight(.medium)
                .multilineTextAlignment(.trailing)
                .lineLimit(2)
        }
    }
}

// MARK: - Section Header
struct SectionHeaderView: View {
    let title: String
    var action: (() -> Void)? = nil
    var actionLabel: String = "Add"
    var actionIcon: String = "plus"

    var body: some View {
        HStack {
            Text(title)
                .font(AppTheme.Typography.title3)
            Spacer()
            if let action = action {
                Button(action: action) {
                    Label(actionLabel, systemImage: actionIcon)
                        .font(.callout)
                }
                .buttonStyle(.borderless)
            }
        }
        .padding(.bottom, AppTheme.Spacing.xs)
    }
}

// MARK: - Empty State
struct EmptyStateView: View {
    let icon: String
    let title: String
    let message: String
    var buttonTitle: String? = nil
    var action: (() -> Void)? = nil

    var body: some View {
        VStack(spacing: AppTheme.Spacing.md) {
            Image(systemName: icon)
                .font(.system(size: 48))
                .foregroundColor(AppTheme.secondaryText.opacity(0.5))
            Text(title)
                .font(AppTheme.Typography.title3)
                .foregroundColor(AppTheme.secondaryText)
            Text(message)
                .font(AppTheme.Typography.body)
                .foregroundColor(AppTheme.tertiaryText)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 300)
            if let buttonTitle = buttonTitle, let action = action {
                Button(action: action) {
                    Label(buttonTitle, systemImage: "plus")
                }
                .primaryButtonStyle()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Filter Pill
struct FilterPill: View {
    let title: String
    let isSelected: Bool
    let count: Int?
    let action: () -> Void

    init(_ title: String, isSelected: Bool, count: Int? = nil, action: @escaping () -> Void) {
        self.title = title; self.isSelected = isSelected; self.count = count; self.action = action
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Text(title)
                if let count = count {
                    Text("\(count)")
                        .font(.caption2)
                        .fontWeight(.bold)
                }
            }
            .font(.callout)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(isSelected ? AppTheme.primaryOrange : Color.clear)
            .foregroundColor(isSelected ? .white : AppTheme.secondaryText)
            .clipShape(Capsule())
            .overlay(Capsule().stroke(isSelected ? Color.clear : Color.gray.opacity(0.3), lineWidth: 1))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Progress Bar
struct ProgressBar: View {
    let value: Double
    var color: Color = AppTheme.primaryOrange
    var height: CGFloat = 8

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: height / 2)
                    .fill(color.opacity(0.15))
                RoundedRectangle(cornerRadius: height / 2)
                    .fill(color)
                    .frame(width: geo.size.width * min(max(value, 0), 1))
            }
        }
        .frame(height: height)
    }
}

// MARK: - Currency Field Helper
struct CurrencyField: View {
    let label: String
    @Binding var value: String

    var body: some View {
        HStack {
            Text("$")
                .foregroundColor(.secondary)
            TextField(label, text: $value)
                .textFieldStyle(.plain)
        }
    }
}
