import SwiftUI

struct SettingsView: View {
    @ObservedObject private var themeManager = ThemeManager.shared

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AppTheme.Spacing.lg) {
                // Theme Section
                GroupBox {
                    VStack(alignment: .leading, spacing: AppTheme.Spacing.md) {
                        Text("Color Theme")
                            .font(AppTheme.Typography.headline)

                        Text("Choose an accent color for the app. All buttons, highlights, and badges will update.")
                            .font(.caption)
                            .foregroundColor(.secondary)

                        HStack(spacing: AppTheme.Spacing.md) {
                            ForEach(AppColorTheme.allCases, id: \.self) { theme in
                                ThemeCard(theme: theme, isSelected: themeManager.current == theme, isDark: themeManager.isDarkMode) {
                                    withAnimation(.easeInOut(duration: 0.3)) {
                                        themeManager.current = theme
                                    }
                                }
                            }
                        }
                    }
                    .padding(.vertical, AppTheme.Spacing.sm)
                }

                // Appearance Mode
                GroupBox {
                    VStack(alignment: .leading, spacing: AppTheme.Spacing.md) {
                        Text("Appearance")
                            .font(AppTheme.Typography.headline)

                        HStack(spacing: AppTheme.Spacing.md) {
                            modeButton(label: "Dark", icon: "moon.fill", isDark: true)
                            modeButton(label: "Light", icon: "sun.max.fill", isDark: false)
                        }
                    }
                    .padding(.vertical, AppTheme.Spacing.sm)
                }

                // App Info Section
                GroupBox {
                    VStack(alignment: .leading, spacing: AppTheme.Spacing.sm) {
                        Text("About")
                            .font(AppTheme.Typography.headline)

                        InfoRow(label: "App", value: "SteelSync")
                        InfoRow(label: "Version", value: "1.0")
                        InfoRow(label: "Company", value: "J&R Steel & Welding LLC")
                    }
                    .padding(.vertical, AppTheme.Spacing.sm)
                }
            }
            .padding(AppTheme.Spacing.lg)
        }
        .navigationTitle("Settings")
    }

    private func modeButton(label: String, icon: String, isDark: Bool) -> some View {
        let isSelected = themeManager.isDarkMode == isDark
        return Button {
            withAnimation(.easeInOut(duration: 0.3)) {
                themeManager.isDarkMode = isDark
            }
        } label: {
            VStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.title2)
                    .foregroundColor(isSelected ? AppTheme.primaryOrange : .secondary)
                Text(label)
                    .font(.caption)
                    .fontWeight(isSelected ? .bold : .regular)
                    .foregroundColor(isSelected ? AppTheme.primaryOrange : .secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(AppTheme.Spacing.md)
            .background(
                RoundedRectangle(cornerRadius: AppTheme.Radius.md)
                    .fill(isSelected ? AppTheme.primaryOrange.opacity(0.1) : Color.gray.opacity(0.05))
            )
            .overlay(
                RoundedRectangle(cornerRadius: AppTheme.Radius.md)
                    .stroke(isSelected ? AppTheme.primaryOrange : Color.clear, lineWidth: 2)
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Theme Card

private struct ThemeCard: View {
    let theme: AppColorTheme
    let isSelected: Bool
    let isDark: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 10) {
                // Mini preview of the full theme
                VStack(spacing: 0) {
                    // Fake sidebar + content preview
                    HStack(spacing: 0) {
                        // Mini sidebar
                        VStack(alignment: .leading, spacing: 3) {
                            RoundedRectangle(cornerRadius: 2)
                                .fill(theme.accent)
                                .frame(width: 28, height: 5)
                            RoundedRectangle(cornerRadius: 2)
                                .fill(theme.secondaryText(dark: isDark))
                                .frame(width: 22, height: 4)
                            RoundedRectangle(cornerRadius: 2)
                                .fill(theme.secondaryText(dark: isDark))
                                .frame(width: 24, height: 4)
                        }
                        .padding(6)
                        .frame(width: 44)
                        .background(theme.sidebarBackground(dark: isDark))

                        // Mini content area
                        VStack(alignment: .leading, spacing: 4) {
                            HStack(spacing: 4) {
                                RoundedRectangle(cornerRadius: 2)
                                    .fill(theme.accent.opacity(0.3))
                                    .frame(width: 20, height: 14)
                                RoundedRectangle(cornerRadius: 2)
                                    .fill(theme.accent.opacity(0.3))
                                    .frame(width: 20, height: 14)
                            }
                            RoundedRectangle(cornerRadius: 2)
                                .fill(theme.primaryText(dark: isDark).opacity(0.4))
                                .frame(width: 50, height: 4)
                            RoundedRectangle(cornerRadius: 2)
                                .fill(theme.secondaryText(dark: isDark).opacity(0.3))
                                .frame(width: 36, height: 3)
                        }
                        .padding(6)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(theme.background(dark: isDark))
                    }
                }
                .frame(height: 50)
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.gray.opacity(0.3), lineWidth: 0.5))

                // Color dots
                HStack(spacing: 4) {
                    Circle().fill(theme.accent).frame(width: 12, height: 12)
                    Circle().fill(theme.background(dark: isDark)).frame(width: 12, height: 12)
                        .overlay(Circle().stroke(Color.gray.opacity(0.3), lineWidth: 0.5))
                    Circle().fill(theme.cardBackground(dark: isDark)).frame(width: 12, height: 12)
                        .overlay(Circle().stroke(Color.gray.opacity(0.3), lineWidth: 0.5))
                    Circle().fill(theme.secondaryText(dark: isDark)).frame(width: 12, height: 12)
                }

                Image(systemName: theme.icon)
                    .font(.caption)
                    .foregroundColor(theme.accent)

                Text(theme.rawValue)
                    .font(.caption)
                    .fontWeight(isSelected ? .bold : .regular)
                    .foregroundColor(isSelected ? theme.accent : .secondary)

                Text(theme.description)
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(height: 30)

                if isSelected {
                    Label("Active", systemImage: "checkmark.circle.fill")
                        .font(.caption2)
                        .foregroundColor(theme.accent)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(AppTheme.Spacing.md)
            .background(
                RoundedRectangle(cornerRadius: AppTheme.Radius.md)
                    .fill(isSelected ? theme.accent.opacity(0.08) : Color.gray.opacity(0.05))
            )
            .overlay(
                RoundedRectangle(cornerRadius: AppTheme.Radius.md)
                    .stroke(isSelected ? theme.accent : Color.clear, lineWidth: 2)
            )
        }
        .buttonStyle(.plain)
    }
}
