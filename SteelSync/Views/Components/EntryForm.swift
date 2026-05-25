import SwiftUI

// MARK: - Entry-form presentation system
//
// SteelSync presents data-entry forms two ways (see the app-wide entry-menu
// design):
//
//   • **Inline** (`.inlineForm`) — the form fills the current content pane as
//     an opaque overlay; the app sidebar stays put. Used for ALL *new* entries
//     and always for Pay Apps, Change Orders, and Timesheets (even edits).
//
//   • **Polished sheet** (`.sheet`, sized) — a floating card over a dimmed
//     pane. Used for quick *edits* of everything else.
//
// Both modes render the SAME form struct inside `EntryFormScaffold`, so a form
// is written once and presented either way. The only wrinkle is dismissal:
// `\.dismiss` does nothing for an overlay (it isn't a sheet), so inline
// presentation injects `\.inlineDismiss`. Forms close via the `closeForm()`
// pattern (prefer `inlineDismiss`, fall back to `dismiss`).

// MARK: Inline dismissal

private struct InlineDismissKey: EnvironmentKey {
    static let defaultValue: (() -> Void)? = nil
}

extension EnvironmentValues {
    /// Non-nil only while a form is presented **inline** (a pane overlay rather
    /// than a sheet). Forms prefer this over `\.dismiss` so the same struct
    /// works in both presentations.
    var inlineDismiss: (() -> Void)? {
        get { self[InlineDismissKey.self] }
        set { self[InlineDismissKey.self] = newValue }
    }
}

// MARK: - EntrySection
//
// Accent-tinted section header used inside entry forms. Fixes the "monotone"
// look: a colored icon chip + uppercase tracked title, then the fields.

struct EntrySection<Content: View>: View {
    let title: String
    var systemImage: String?
    var spacing: CGFloat
    @ViewBuilder var content: () -> Content

    init(_ title: String,
         systemImage: String? = nil,
         spacing: CGFloat = 12,
         @ViewBuilder content: @escaping () -> Content) {
        self.title = title
        self.systemImage = systemImage
        self.spacing = spacing
        self.content = content
    }

    var body: some View {
        VStack(alignment: .leading, spacing: spacing) {
            HStack(spacing: 8) {
                if let systemImage {
                    Image(systemName: systemImage)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(AppTheme.primaryOrange)
                        .frame(width: 24, height: 24)
                        .background(
                            RoundedRectangle(cornerRadius: 7, style: .continuous)
                                .fill(AppTheme.primaryOrange.opacity(0.14))
                        )
                }
                Text(title)
                    .font(.system(size: 12, weight: .semibold))
                    .tracking(0.5)
                    .textCase(.uppercase)
                    .foregroundColor(AppTheme.secondaryText)
            }
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - EntryFormScaffold
//
// Standard chrome for every entry form: a sticky header (icon/badge + title +
// Cancel/Save), a scrollable centered content column, and an optional sticky
// footer (totals, validation). Fills whatever it's placed in — a pane overlay
// when inline, or the sheet's frame when presented as a sheet.

struct EntryFormScaffold<Content: View, Footer: View>: View {
    let title: String
    var icon: String?
    var badge: String?
    var saveTitle: String
    var saveDisabled: Bool
    var maxContentWidth: CGFloat
    let onCancel: () -> Void
    let onSave: () -> Void
    @ViewBuilder var content: () -> Content
    @ViewBuilder var footer: () -> Footer

    init(title: String,
         icon: String? = nil,
         badge: String? = nil,
         saveTitle: String = "Save",
         saveDisabled: Bool = false,
         // Fills the pane on normal windows, but caps line length on very wide
         // (external/6K) displays so a single field doesn't stretch edge-to-edge.
         maxContentWidth: CGFloat = 1040,
         onCancel: @escaping () -> Void,
         onSave: @escaping () -> Void,
         @ViewBuilder content: @escaping () -> Content,
         @ViewBuilder footer: @escaping () -> Footer = { EmptyView() }) {
        self.title = title
        self.icon = icon
        self.badge = badge
        self.saveTitle = saveTitle
        self.saveDisabled = saveDisabled
        self.maxContentWidth = maxContentWidth
        self.onCancel = onCancel
        self.onSave = onSave
        self.content = content
        self.footer = footer
    }

    private var hasFooter: Bool { Footer.self != EmptyView.self }

    var body: some View {
        VStack(spacing: 0) {
            header
            ScrollView {
                VStack(alignment: .leading, spacing: AppTheme.Spacing.lg) {
                    content()
                }
                .frame(maxWidth: maxContentWidth, alignment: .leading)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, AppTheme.Spacing.lg)
                .padding(.vertical, AppTheme.Spacing.lg)
            }
            if hasFooter {
                VStack(spacing: 0) {
                    Rectangle().fill(AppTheme.primaryText.opacity(0.08)).frame(height: 0.5)
                    footer()
                        .frame(maxWidth: maxContentWidth)
                        .frame(maxWidth: .infinity)
                        .padding(.horizontal, AppTheme.Spacing.lg)
                        .padding(.vertical, AppTheme.Spacing.md)
                }
                .background(AppTheme.background)
            }
        }
        .background(AppTheme.background)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var header: some View {
        HStack(spacing: 10) {
            if let badge {
                Text(badge)
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(AppTheme.accentForeground)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(AppTheme.primaryOrange)
                    )
            } else if let icon {
                Image(systemName: icon)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(AppTheme.primaryOrange)
            }
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

// MARK: - Inline presentation modifiers

extension View {
    /// Present `form` inline — an opaque overlay filling this view's bounds.
    /// Attach to a content-pane root so the form covers the pane while the app
    /// sidebar stays visible. The form closes via `\.inlineDismiss`.
    func inlineForm<Form: View>(
        isPresented: Binding<Bool>,
        @ViewBuilder form: @escaping () -> Form
    ) -> some View {
        modifier(InlineFormBoolModifier(isPresented: isPresented, form: form))
    }

    /// Item-driven variant, mirroring `.sheet(item:)`.
    func inlineForm<Item: Identifiable, Form: View>(
        item: Binding<Item?>,
        @ViewBuilder form: @escaping (Item) -> Form
    ) -> some View {
        modifier(InlineFormItemModifier(item: item, form: form))
    }
}

private struct InlineFormBoolModifier<Form: View>: ViewModifier {
    @Binding var isPresented: Bool
    @ViewBuilder var form: () -> Form

    func body(content: Content) -> some View {
        content.overlay {
            ZStack {
                if isPresented {
                    form()
                        .environment(\.inlineDismiss) {
                            withAnimation(.easeInOut(duration: 0.22)) { isPresented = false }
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(AppTheme.background)
                        .contentShape(Rectangle())
                        .transition(.opacity)
                        .zIndex(1)
                }
            }
            .animation(.easeInOut(duration: 0.22), value: isPresented)
        }
    }
}

private struct InlineFormItemModifier<Item: Identifiable, Form: View>: ViewModifier {
    @Binding var item: Item?
    @ViewBuilder var form: (Item) -> Form

    func body(content: Content) -> some View {
        content.overlay {
            ZStack {
                if let item {
                    form(item)
                        .environment(\.inlineDismiss) {
                            withAnimation(.easeInOut(duration: 0.22)) { self.item = nil }
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(AppTheme.background)
                        .contentShape(Rectangle())
                        .transition(.opacity)
                        .zIndex(1)
                }
            }
            .animation(.easeInOut(duration: 0.22), value: item != nil)
        }
    }
}
