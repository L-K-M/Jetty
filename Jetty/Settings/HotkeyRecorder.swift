import SwiftUI
import AppKit

/// A SwiftUI control that records a global shortcut. Click it, press the desired
/// modifier+key combination, and it reports a new `HotkeyBinding`. Escape cancels;
/// a combination with no modifier is rejected (a bare key would be captured
/// system-wide). Backs MF-6's customizable hotkeys.
struct HotkeyRecorder: NSViewRepresentable {
    @Binding var binding: HotkeyBinding

    func makeNSView(context: Context) -> RecorderButton {
        let button = RecorderButton()
        button.onChange = { binding = $0 }
        button.binding = binding
        return button
    }

    func updateNSView(_ nsView: RecorderButton, context: Context) {
        nsView.binding = binding
        nsView.onChange = { binding = $0 }
        nsView.refreshTitle()
    }
}

/// An `NSButton` that, while first responder, intercepts the next key event and
/// turns it into a `HotkeyBinding`.
final class RecorderButton: NSButton {
    var binding = HotkeyBinding.defaultToggle
    var onChange: ((HotkeyBinding) -> Void)?

    private var recording = false { didSet { refreshTitle() } }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        bezelStyle = .rounded
        setButtonType(.momentaryPushIn)
        target = self
        action = #selector(beginRecording)
        refreshTitle()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override var acceptsFirstResponder: Bool { true }

    @objc private func beginRecording() {
        window?.makeFirstResponder(self)
    }

    override func becomeFirstResponder() -> Bool {
        recording = true
        return super.becomeFirstResponder()
    }

    override func resignFirstResponder() -> Bool {
        recording = false
        return super.resignFirstResponder()
    }

    override func keyDown(with event: NSEvent) {
        guard recording else { super.keyDown(with: event); return }

        // Bare Escape cancels without changing the binding.
        if event.keyCode == 53 && HotkeyBinding.carbonModifiers(from: event.modifierFlags) == 0 {
            window?.makeFirstResponder(nil)
            return
        }

        let candidate = binding.updated(from: event)
        guard candidate.modifiers != 0 else {
            // A shortcut needs at least one modifier; nudge and keep recording.
            NSSound.beep()
            return
        }
        binding = candidate
        onChange?(candidate)
        window?.makeFirstResponder(nil)
    }

    /// Swallow key-equivalents while recording so Space/Return don't re-trigger the
    /// button's own action instead of being captured.
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if recording { keyDown(with: event); return true }
        return super.performKeyEquivalent(with: event)
    }

    func refreshTitle() {
        if recording {
            title = "Type shortcut…"
        } else if binding.modifiers != 0 {
            title = binding.displayString
        } else {
            title = "Click to record"
        }
    }
}
