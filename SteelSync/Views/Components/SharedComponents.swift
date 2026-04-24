import SwiftUI

// MARK: - Screen Header
//
// Unified header used at the top of every top-level destination so the app feels
// coherent. Pass a title, optional subtitle, and a trailing actions ViewBuilder.
//
// Usage:
//   ScreenHeader(title: "Projects", subtitle: "12 active") {
//       Button("Add Project") { ... }.buttonStyle(.appPrimary)
//   }
struct ScreenHeader<Actions: View>: View {
    let title: String
    var subtitle: String? = nil
    var icon: String? = nil
    @ViewBuilder var actions: () -> Actions

    init(
        title: String,
        subtitle: String? = nil,
        icon: String? = nil,
        @ViewBuilder actions: @escaping () -> Actions = { EmptyView() }
    ) {
        self.title = title
        self.subtitle = subtitle
        self.icon = icon
        self.actions = actions
    }

    var body: some View {
        HStack(alignment: .center, spacing: AppTheme.Spacing.md) {
            if let icon = icon {
                Image(systemName: icon)
                    .font(.title2)
                    .foregroundColor(AppTheme.primaryOrange)
                    .frame(width: 28, height: 28)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 22, weight: .bold))
                    .foregroundColor(AppTheme.primaryText)
                    .lineLimit(2)
                    .minimumScaleFactor(0.6)
                    .allowsTightening(true)
                if let subtitle = subtitle {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundColor(AppTheme.secondaryText)
                        .lineLimit(2)
                        .minimumScaleFactor(0.75)
                }
            }
            .layoutPriority(0)
            Spacer(minLength: AppTheme.Spacing.sm)
            actions()
                .layoutPriority(1)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, AppTheme.Spacing.lg)
        .padding(.vertical, AppTheme.Spacing.md)
        .background(AppTheme.background)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Color.gray.opacity(0.15))
                .frame(height: 0.5)
        }
    }
}

// MARK: - Metric Card
struct MetricCard: View {
    let title: String
    let value: String
    let icon: String
    var color: Color = AppTheme.primaryOrange
    var subtitle: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(color.opacity(0.14))
                    .frame(width: 30, height: 30)
                Image(systemName: icon)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(color)
            }

            Text(value)
                .font(.system(size: 22, weight: .bold, design: .rounded))
                .foregroundColor(AppTheme.primaryText)
                .lineLimit(1)
                .minimumScaleFactor(0.6)

            Text(title)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(AppTheme.secondaryText)
                .textCase(.uppercase)
                .tracking(0.3)

            if let subtitle = subtitle {
                Text(subtitle)
                    .font(.caption2)
                    .foregroundColor(AppTheme.tertiaryText)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(AppTheme.cardBackground)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(AppTheme.primaryText.opacity(0.06), lineWidth: 0.5)
        )
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
            HStack(spacing: 6) {
                Text(title)
                    .font(.system(size: 13, weight: isSelected ? .semibold : .medium))
                if let count = count {
                    Text("\(count)")
                        .font(.system(size: 11, weight: .bold))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 1)
                        .background(
                            Capsule().fill(
                                isSelected ? Color.white.opacity(0.25) : AppTheme.primaryText.opacity(0.08)
                            )
                        )
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .foregroundColor(isSelected ? AppTheme.primaryOrange : AppTheme.secondaryText)
            .background(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(isSelected ? AppTheme.primaryOrange.opacity(0.14) : Color.clear)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .strokeBorder(
                        isSelected ? AppTheme.primaryOrange.opacity(0.35) : AppTheme.primaryText.opacity(0.12),
                        lineWidth: isSelected ? 1 : 0.5
                    )
            )
        }
        .buttonStyle(.plain)
        .animation(.easeOut(duration: 0.15), value: isSelected)
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
        HStack(spacing: 6) {
            Text("$")
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(AppTheme.secondaryText)
            TextField(label, text: $value)
                .textFieldStyle(.plain)
                .font(.system(size: 14))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(minHeight: 36)
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

// MARK: - Sheet Chrome
//
// Shared primitives used by every Add/Edit/log sheet so headers, section
// dividers, and currency fields stay consistent app-wide.

/// Sticky top bar for modal sheets. Cancel on the left of the save CTA, a
/// hairline divider, and background that matches the sheet surface.
struct SheetHeader: View {
    let title: String
    let saveTitle: String
    var saveDisabled: Bool = false
    let onCancel: () -> Void
    let onSave: () -> Void

    var body: some View {
        HStack {
            Text(title)
                .font(.system(size: 18, weight: .semibold))
                .foregroundColor(AppTheme.primaryText)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Spacer(minLength: AppTheme.Spacing.sm)
            Button("Cancel") { onCancel() }
                .buttonStyle(.appGhost)
                .keyboardShortcut(.cancelAction)
            Button(saveTitle) { onSave() }
                .buttonStyle(.appPrimary)
                .keyboardShortcut(.defaultAction)
                .disabled(saveDisabled)
        }
        .padding(.horizontal, AppTheme.Spacing.lg)
        .padding(.vertical, AppTheme.Spacing.md)
        .background(AppTheme.background)
        .overlay(alignment: .bottom) {
            Rectangle().fill(AppTheme.primaryText.opacity(0.08)).frame(height: 0.5)
        }
    }
}

/// Small uppercase tracked heading used to group fields inside sheets.
struct SectionTitle: View {
    let text: String
    var body: some View {
        Text(text)
            .font(.system(size: 11, weight: .semibold))
            .foregroundColor(AppTheme.secondaryText)
            .textCase(.uppercase)
            .tracking(0.5)
            .padding(.bottom, 2)
    }
}

/// `.appField`-styled currency input with a `$` prefix. Use inside a
/// `LabeledField` for currency inputs in sheets.
struct CurrencyInput: View {
    let placeholder: String
    @Binding var text: String

    var body: some View {
        HStack(spacing: 6) {
            Text("$")
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(AppTheme.secondaryText)
            TextField(placeholder, text: $text)
                .textFieldStyle(.plain)
                .font(.system(size: 14))
                #if !os(macOS)
                .keyboardType(.decimalPad)
                #endif
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(minHeight: 36)
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

/// Multi-line note editor styled to match `.appField`. Replaces bare
/// `TextEditor` usage inside sheets.
struct NotesField: View {
    @Binding var text: String
    var minHeight: CGFloat = 80

    var body: some View {
        TextEditor(text: $text)
            .font(.system(size: 14))
            .scrollContentBackground(.hidden)
            .padding(8)
            .frame(minHeight: minHeight)
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
