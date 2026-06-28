import SwiftUI
import AppKit

/// An AppKit-backed search field for the Jetty Menu.
///
/// A SwiftUI `TextField` inside this borderless, non-activating `NSPanel` did not
/// reliably write each keystroke back to its binding on macOS 26: the field *showed*
/// the typed text while `model.query` stayed empty, so the results silently fell back
/// to the empty-query recents list (typing a full app name like "IntelliJ" surfaced
/// only a recent app such as System Settings). An `NSTextField` whose delegate pushes
/// `controlTextDidChange` straight into the binding tracks every keystroke reliably,
/// independent of SwiftUI's text-binding behaviour in a panel.
struct MenuSearchField: NSViewRepresentable {
    @Binding var text: String
    var placeholder: String
    /// Bumped by the controller each time the menu opens, to (re)focus the field and
    /// move the caret to the end — the view is created once and the panel is reused, so
    /// `onAppear`-style focus wouldn't fire on later opens.
    var focusToken: Int

    func makeCoordinator() -> Coordinator { Coordinator(text: $text) }

    func makeNSView(context: Context) -> NSTextField {
        let field = NSTextField(string: text)
        field.delegate = context.coordinator
        field.isBordered = false
        field.isBezeled = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.placeholderString = placeholder
        field.font = .preferredFont(forTextStyle: .title3)
        field.lineBreakMode = .byTruncatingTail
        field.usesSingleLineMode = true
        field.cell?.usesSingleLineMode = true
        field.cell?.wraps = false
        field.cell?.isScrollable = true
        field.setContentHuggingPriority(.defaultLow, for: .horizontal)
        field.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return field
    }

    func updateNSView(_ field: NSTextField, context: Context) {
        // Keep the field in sync when the model clears/changes the query programmatically
        // (e.g. reset on open). Skip when equal so we never fight the user mid-edit.
        if field.stringValue != text { field.stringValue = text }

        if context.coordinator.lastFocusToken != focusToken {
            context.coordinator.lastFocusToken = focusToken
            DispatchQueue.main.async { [weak field] in
                guard let field, let window = field.window else { return }
                window.makeFirstResponder(field)
                // UTF-16 length (NSRange is UTF-16-based) so the caret lands at the end
                // even for any prefilled non-ASCII text.
                field.currentEditor()?.selectedRange = NSRange(location: (field.stringValue as NSString).length, length: 0)
            }
        }
    }

    final class Coordinator: NSObject, NSTextFieldDelegate {
        private let text: Binding<String>
        var lastFocusToken = Int.min
        init(text: Binding<String>) { self.text = text }

        func controlTextDidChange(_ notification: Notification) {
            guard let field = notification.object as? NSTextField else { return }
            text.wrappedValue = field.stringValue
        }
    }
}
