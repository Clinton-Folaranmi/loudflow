import Foundation
import AppKit
import CoreGraphics

/// Puts the transcript where it belongs: pasted at the cursor in the app you were typing in,
/// or left on the clipboard.
///
/// It reactivates the last external app (see `AppFocus`), puts the text on the pasteboard,
/// synthesizes ⌘V, then restores the previous clipboard. This needs Accessibility permission;
/// without it we just leave the text on the clipboard.
enum TextInserter {

    /// Returns true if it actually pasted; false if it could only copy to the clipboard.
    @discardableResult
    static func insert(_ text: String) -> Bool {
        guard !text.isEmpty else { return false }
        guard Permissions.hasAccessibility() else {
            copyToClipboard(text)     // can't synthesize the paste without trust
            return false
        }

        let pb = NSPasteboard.general
        let previous = pb.string(forType: .string)
        pb.clearContents()
        pb.setString(text, forType: .string)

        let restore = {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                pb.clearContents()
                if let previous { pb.setString(previous, forType: .string) }
            }
        }

        // Reactivate the app the user was typing in, then paste into it.
        if let target = AppFocus.shared.lastExternalApp,
           target.bundleIdentifier != Bundle.main.bundleIdentifier {
            target.activate(options: [])
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
                paste()
                restore()
            }
        } else {
            paste()
            restore()
        }
        return true
    }

    static func copyToClipboard(_ text: String) {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(text, forType: .string)
    }

    /// Synthesize ⌘V into the frontmost app.
    private static func paste() {
        let source = CGEventSource(stateID: .combinedSessionState)
        let vKey: CGKeyCode = 9   // 'v'
        guard let down = CGEvent(keyboardEventSource: source, virtualKey: vKey, keyDown: true),
              let up = CGEvent(keyboardEventSource: source, virtualKey: vKey, keyDown: false)
        else { return }
        down.flags = .maskCommand
        up.flags = .maskCommand
        down.post(tap: .cgAnnotatedSessionEventTap)
        up.post(tap: .cgAnnotatedSessionEventTap)
    }
}
