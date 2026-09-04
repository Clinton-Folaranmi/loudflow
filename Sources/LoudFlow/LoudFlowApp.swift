import SwiftUI
import AppKit

@main
struct LoudFlowApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        Window("LoudFlow", id: "main") {
            RootView(model: appDelegate.model)
        }
        .defaultSize(width: 1180, height: 820)
        .windowResizability(.contentMinSize)
        .windowStyle(.hiddenTitleBar)   // desk runs to the top; traffic lights float over content
    }
}

/// Composes the main window and the onboarding overlay. The floating widget is a separate
/// OS-level panel (see `WidgetPanelController`), not part of this view tree.
struct RootView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        ZStack {
            MainWindow(model: model)
            if model.showingOnboarding {
                OnboardingView(model: model)
            }
        }
        .frame(minWidth: 980, minHeight: 680)
        .animation(.easeOut(duration: 0.2), value: model.showingOnboarding)
        .background(LiveResizeFix())
    }
}

/// A window's content view redraws its layer from a cached bitmap while you drag-resize it,
/// stretching the last frame to the new size instead of asking SwiftUI to relayout — real
/// content only catches up once you let go. That reads as the window ignoring you while you're
/// actively resizing it. Continuous redraw during the drag has to be opted into explicitly.
private struct LiveResizeFix: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            view.window?.contentView?.layerContentsRedrawPolicy = .duringViewResize
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
}

/// App lifecycle: owns the shared model, brings up the floating widget, keeps running when the
/// window closes, and schedules retention sweeps.
///
/// There is intentionally **no menu-bar item** (per the app owner's decision — the API key is
/// not tucked away there). The window is reopened from the Dock; the widget floats regardless.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let model = AppModel()
    private var widget: WidgetPanelController?
    private var retentionTimer: Timer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Track the last external app so transcripts paste back where you were typing.
        AppFocus.shared.start()

        // Bring up the always-on-top widget.
        widget = WidgetPanelController(model: model)
        widget?.show()

        // Let the model surface the main window (widget error actions, "Fix it", etc.).
        model.showMainWindow = {
            NSApp.activate(ignoringOtherApps: true)
            NSApp.windows.first { !($0 is NSPanel) }?.makeKeyAndOrderFront(nil)
        }

        // Retention: sweep now and every 6 hours (also on activation, below).
        retentionTimer = Timer.scheduledTimer(withTimeInterval: 6 * 3600, repeats: true) { _ in
            Task { @MainActor in self.model.sweepRetention() }
        }
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        model.sweepRetention()
        model.startHotkeys()        // (re)install the event tap once Accessibility is granted
    }

    // Keep running with the widget after the window is closed; reopen from the Dock.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag { NSApp.windows.first { !($0 is NSPanel) }?.makeKeyAndOrderFront(nil) }
        return true
    }
}
