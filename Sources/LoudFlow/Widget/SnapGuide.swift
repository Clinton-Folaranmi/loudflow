import AppKit
import SwiftUI

/// The three screen edges the widget can dock to (top is reserved for the menu bar).
enum WidgetEdge { case left, right, bottom }

/// A full-screen, click-through overlay shown while dragging the widget. It highlights the
/// three dockable edges and emphasizes the one the widget will snap to.
final class SnapGuideController {
    private let panel: NSPanel
    private let hosting: NSHostingView<SnapGuideView>

    init() {
        panel = NSPanel(contentRect: .zero,
                        styleMask: [.borderless, .nonactivatingPanel],
                        backing: .buffered, defer: false)
        hosting = NSHostingView(rootView: SnapGuideView(target: nil))
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = .floating
        panel.ignoresMouseEvents = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.contentView = hosting
        hosting.autoresizingMask = [.width, .height]
    }

    func show(target: WidgetEdge?) {
        guard let vf = NSScreen.main?.visibleFrame else { return }
        panel.setFrame(vf, display: false)
        hosting.rootView = SnapGuideView(target: target)
        panel.orderFrontRegardless()
    }

    func update(target: WidgetEdge?) {
        hosting.rootView = SnapGuideView(target: target)
    }

    func hide() { panel.orderOut(nil) }
}

private struct SnapGuideView: View {
    var target: WidgetEdge?

    var body: some View {
        GeometryReader { geo in
            ZStack {
                bar(.left, geo)
                bar(.right, geo)
                bar(.bottom, geo)
            }
        }
        .allowsHitTesting(false)
    }

    @ViewBuilder private func bar(_ edge: WidgetEdge, _ geo: GeometryProxy) -> some View {
        let active = edge == target
        let color = active ? Theme.marigold : Theme.sage.opacity(0.4)
        let thickness: CGFloat = active ? 6 : 4
        let inset: CGFloat = 8
        switch edge {
        case .left:
            Capsule().fill(color)
                .frame(width: thickness, height: geo.size.height * 0.55)
                .position(x: inset, y: geo.size.height / 2)
        case .right:
            Capsule().fill(color)
                .frame(width: thickness, height: geo.size.height * 0.55)
                .position(x: geo.size.width - inset, y: geo.size.height / 2)
        case .bottom:
            Capsule().fill(color)
                .frame(width: geo.size.width * 0.5, height: thickness)
                .position(x: geo.size.width / 2, y: geo.size.height - inset)
        }
    }
}
