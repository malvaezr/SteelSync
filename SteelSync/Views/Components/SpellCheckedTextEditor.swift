import SwiftUI
#if os(macOS)
import AppKit
#else
import UIKit
#endif

/// A multi-line text editor with **spell + grammar checking and automatic
/// language identification** (English + Spanish, on-device, free). SwiftUI's
/// `TextEditor` enables spell-check by default but exposes no grammar-check or
/// language controls, so this wraps the platform text view directly.
///
/// Bilingual checking relies on the OS having both dictionaries available:
/// add Spanish in System Settings → Language & Region (macOS) / a Spanish
/// keyboard (iOS). `NSSpellChecker.automaticallyIdentifiesLanguages` /
/// per-keyboard detection then check each phrase in the right language.
struct SpellCheckedTextEditor: View {
    @Binding var text: String
    var minHeight: CGFloat = 80

    var body: some View {
        _SpellCheckedTextView(text: $text)
            .frame(minHeight: minHeight)
    }
}

#if os(macOS)
private struct _SpellCheckedTextView: NSViewRepresentable {
    @Binding var text: String

    func makeNSView(context: Context) -> NSScrollView {
        NSSpellChecker.shared.automaticallyIdentifiesLanguages = true

        let scroll = NSTextView.scrollableTextView()
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = true

        guard let tv = scroll.documentView as? NSTextView else { return scroll }
        tv.delegate = context.coordinator
        tv.isRichText = false
        tv.font = .systemFont(ofSize: 14)
        tv.drawsBackground = false
        tv.textContainerInset = NSSize(width: 5, height: 8)
        tv.allowsUndo = true
        // The whole point: live spell + grammar underlines, auto language.
        tv.isContinuousSpellCheckingEnabled = true
        tv.isGrammarCheckingEnabled = true
        // Underline, don't silently rewrite the user's text.
        tv.isAutomaticSpellingCorrectionEnabled = false
        tv.isAutomaticTextReplacementEnabled = false
        tv.isAutomaticQuoteSubstitutionEnabled = false
        tv.isAutomaticDashSubstitutionEnabled = false
        tv.textColor = NSColor(AppTheme.primaryText)
        tv.insertionPointColor = NSColor(AppTheme.primaryText)
        tv.string = text
        return scroll
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        guard let tv = nsView.documentView as? NSTextView else { return }
        if tv.string != text { tv.string = text }
        tv.textColor = NSColor(AppTheme.primaryText)   // track theme changes
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, NSTextViewDelegate {
        let parent: _SpellCheckedTextView
        init(_ parent: _SpellCheckedTextView) { self.parent = parent }
        func textDidChange(_ notification: Notification) {
            guard let tv = notification.object as? NSTextView else { return }
            parent.text = tv.string
        }
    }
}
#else
private struct _SpellCheckedTextView: UIViewRepresentable {
    @Binding var text: String

    func makeUIView(context: Context) -> UITextView {
        let tv = UITextView()
        tv.delegate = context.coordinator
        tv.font = .systemFont(ofSize: 16)
        tv.backgroundColor = .clear
        tv.textContainerInset = UIEdgeInsets(top: 8, left: 5, bottom: 8, right: 5)
        // Spell-check underlines + autocorrect; language follows enabled keyboards.
        tv.spellCheckingType = .yes
        tv.autocorrectionType = .yes
        tv.smartQuotesType = .no
        tv.smartDashesType = .no
        tv.textColor = UIColor(AppTheme.primaryText)

        // Apple Pencil Scribble — UIKit installs a system text interaction on
        // every editable UITextView/UITextField on iPadOS 14+, which renders
        // the Scribble overlay and converts handwriting → text automatically.
        // We set the relevant properties explicitly here so nothing in the
        // SwiftUI wrapping accidentally disables Pencil hit-testing. (Standard
        // SwiftUI `TextField` already inherits this from its underlying
        // UITextField — no app code needed there.)
        tv.isEditable = true
        tv.isSelectable = true
        tv.isUserInteractionEnabled = true

        tv.text = text
        return tv
    }

    func updateUIView(_ tv: UITextView, context: Context) {
        if tv.text != text { tv.text = text }
        tv.textColor = UIColor(AppTheme.primaryText)
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, UITextViewDelegate {
        let parent: _SpellCheckedTextView
        init(_ parent: _SpellCheckedTextView) { self.parent = parent }
        func textViewDidChange(_ tv: UITextView) { parent.text = tv.text }
    }
}
#endif
