import AppKit

final class AppFocus {
    static let shared = AppFocus()
    private(set) var lastExternalApp: NSRunningApplication?
    private var observer: NSObjectProtocol?

    func start() {
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
