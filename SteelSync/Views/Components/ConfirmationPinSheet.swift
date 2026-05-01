import SwiftUI

/// PIN-gated confirmation sheet for destructive actions.
///
/// Generic enough that any "delete X" flow can hand it a title, a one-line
/// detail string, and a closure to run after the right PIN is typed. The
/// sheet auto-focuses the field, shows an inline error when the PIN is
/// wrong, and links to the Settings page for the reset path.
struct ConfirmationPinSheet: View {
    let title: String
    /// One-line description of what's about to be deleted (e.g. the row label).
    let detail: String
    /// Verb shown on the confirm button — usually "Delete".
    var confirmLabel: String = "Delete"
    /// Tint of the confirm button — defaults to red for delete flows.
    var confirmTint: Color = .red
    /// Called once the user enters the correct PIN and taps confirm.
    let onConfirm: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var pin: String = ""
    @State private var attemptCount: Int = 0
    @State private var showWrongPinFlash: Bool = false
    @FocusState private var pinFieldFocused: Bool

    private var isCorrect: Bool { PinService.verify(pin) }
    private var canSubmit: Bool { pin.count == 4 && pin.allSatisfy(\.isNumber) }

    var body: some View {
        VStack(spacing: 0) {
            SheetHeader(
                title: title,
                saveTitle: confirmLabel,
                saveDisabled: !canSubmit,
                onCancel: { dismiss() },
                onSave: attemptConfirm
            )

            ScrollView {
                VStack(alignment: .leading, spacing: AppTheme.Spacing.lg) {
                    VStack(alignment: .leading, spacing: AppTheme.Spacing.sm) {
                        SectionTitle(text: "Item")
                        Text(detail)
                            .font(.body)
                            .foregroundColor(AppTheme.primaryText)
                            .padding(AppTheme.Spacing.md)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .fill(AppTheme.secondaryBackground)
                            )
                    }

                    VStack(alignment: .leading, spacing: AppTheme.Spacing.sm) {
                        SectionTitle(text: "Confirmation PIN")
                        Text("Enter the 4-digit PIN to confirm. The default is \(PinService.defaultPin) — you can change it in Settings.")
                            .font(.caption)
                            .foregroundColor(AppTheme.secondaryText)

                        HStack {
                            SecureField("• • • •", text: $pin)
                                .textFieldStyle(.appField)
                                .focused($pinFieldFocused)
                                .multilineTextAlignment(.center)
                                .font(.system(size: 22, weight: .semibold, design: .monospaced))
                                #if !os(macOS)
                                .keyboardType(.numberPad)
                                #endif
                                .onChange(of: pin) { _, newValue in
                                    // Strip non-digits, cap at 4 chars
                                    let cleaned = String(newValue.filter(\.isNumber).prefix(4))
                                    if cleaned != newValue { pin = cleaned }
                                    showWrongPinFlash = false
                                }
                                .onSubmit { attemptConfirm() }
                        }

                        if showWrongPinFlash {
                            Label("Incorrect PIN. Try again or reset it in Settings.",
                                  systemImage: "exclamationmark.triangle.fill")
                                .font(.caption)
                                .foregroundColor(.red)
                        }
                    }

                    DisclosureGroup("Forgot your PIN?") {
                        Text("Open Settings → Confirmation PIN and tap **Reset to Default**. The PIN goes back to \(PinService.defaultPin) and you can set a new one.")
                            .font(.caption)
                            .foregroundColor(AppTheme.secondaryText)
                            .padding(.top, 4)
                    }
                    .font(.caption)
                    .foregroundColor(AppTheme.secondaryText)
                }
                .padding(AppTheme.Spacing.lg)
            }
            .background(AppTheme.background)
        }
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                pinFieldFocused = true
            }
        }
        #if os(macOS)
        .frame(width: 460, height: 460)
        #endif
    }

    private func attemptConfirm() {
        guard canSubmit else { return }
        if isCorrect {
            onConfirm()
            dismiss()
        } else {
            attemptCount += 1
            showWrongPinFlash = true
            pin = ""
            pinFieldFocused = true
        }
    }
}
