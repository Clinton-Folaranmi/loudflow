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
        .windowStyle(.hiddenTitleBar)
    }
}

struct RootView: View {
    @ObservedObject var model: AppModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            MainWindow(model: model)
            if model.showingOnboarding {
                OnboardingView(model: model)
            }
        }
        .frame(minWidth: 980, minHeight: 680)
        .animation(reduceMotion ? nil : Motion.page, value: model.showingOnboarding)
        .background(LiveResizeFix())
    }
}

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

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let model = AppModel()
    private var widget: WidgetPanelController?
    private var retentionTimer: Timer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        AppFocus.shared.start()

        widget = WidgetPanelController(model: model)
        widget?.show()

        model.showMainWindow = {
            NSApp.activate(ignoringOtherApps: true)
            NSApp.windows.first { !($0 is NSPanel) }?.makeKeyAndOrderFront(nil)
        }

        retentionTimer = Timer.scheduledTimer(withTimeInterval: 6 * 3600, repeats: true) { _ in
            Task { @MainActor in self.model.sweepRetention() }
        }
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        model.sweepRetention()
        model.startHotkeys()
    }

    func applicationWillTerminate(_ notification: Notification) {
        Persistence.shared.flush()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag { NSApp.windows.first { !($0 is NSPanel) }?.makeKeyAndOrderFront(nil) }
        return true
    }
}
