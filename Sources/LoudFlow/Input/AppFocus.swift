import AppKit

/// Tracks the last **external** app that was frontmost (i.e. not LoudFlow), so the transcript
/// can be pasted back into the app you were actually typing in — even if LoudFlow's own
/// window is open. Clicking the floating widget doesn't activate LoudFlow (it's a
/// non-activating panel), so in the common case this is just your editor.
final class AppFocus {
    static let shared = AppFocus()
    private(set) var lastExternalApp: NSRunningApplication?
    private var observer: NSObjectProtocol?

    func start() {
        // Seed with the current frontmost app if it isn't us.
        if let front = NSWorkspace.shared.frontmostApplication,
           front.bundleIdentifier != Bundle.main.bundleIdentifier {
            lastExternalApp = front
        }
        observer = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil, queue: .main
        ) { [weak self] note in
            guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
            if app.bundleIdentifier != Bundle.main.bundleIdentifier {
                self?.lastExternalApp = app
            }
        }
    }
}
