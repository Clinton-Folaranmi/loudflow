import Foundation
import AppKit
import CoreGraphics

enum TextInserter {

    @discardableResult
    static func insert(_ text: String) -> Bool {
        guard !text.isEmpty else { return false }
        guard Permissions.hasAccessibility() else {
            copyToClipboard(text)
            return false
        }

        let pb = NSPasteboard.general
        let previous = pb.string(forType: .string)
        pb.clearContents()
        pb.setString(text, forType: .string)
        let transcriptChangeCount = pb.changeCount

        // Leave the transcript on the clipboard long enough for the target app to read it.
        let restore = {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                guard pb.changeCount == transcriptChangeCount else { return }
                pb.clearContents()
                if let previous { pb.setString(previous, forType: .string) }
            }
        }

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

    private static func paste() {
        let source = CGEventSource(stateID: .combinedSessionState)
        let vKey: CGKeyCode = 9
        guard let down = CGEvent(keyboardEventSource: source, virtualKey: vKey, keyDown: true),
              let up = CGEvent(keyboardEventSource: source, virtualKey: vKey, keyDown: false)
        else { return }
        down.flags = .maskCommand
        up.flags = .maskCommand
        down.post(tap: .cgAnnotatedSessionEventTap)
        up.post(tap: .cgAnnotatedSessionEventTap)
    }
}
