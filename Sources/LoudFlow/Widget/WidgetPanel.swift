import AppKit
import SwiftUI

/// Owns the always-on-top floating widget window.
///
/// Borderless, **non-activating** `NSPanel` (clicking it never steals key focus, so inserted
/// text lands where your cursor already was). Position is user-controlled and persisted.
///
/// Dragging shows edge guides and **snaps to the nearest of three edges** (left / right /
/// bottom) on release, with a short animation. It keeps a fixed **anchor corner** on that
/// edge so hover-expand / recording / toast grow *inward* — the dot never jumps.
final class WidgetPanelController {
    private let model: AppModel
    private let panel: NSPanel
    private let hostingView: NSHostingView<WidgetView>
    private let snapGuide = SnapGuideController()

    private var anchor: NSPoint?          // fixed corner (bottom-right if anchorRight, else bottom-left)
    private var anchorRight = true
    private var dragStartOrigin: NSPoint?

    /// The design's snap inset is 26pt from the screen edge, measured to the *visible* pill.
    /// `WidgetView` carries a transparent margin so its shadow never clips, so the window sits
    /// that much further out than the pill does — subtract it back off.
    private let snapInset: CGFloat = 26
    private let shadowPad: CGFloat = 14
    private var edgeMargin: CGFloat { snapInset - shadowPad }

    init(model: AppModel) {
        self.model = model
        panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 120, height: 56),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered, defer: false
        )
        hostingView = NSHostingView(rootView: WidgetView(model: model))

        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.isMovableByWindowBackground = false
        panel.hidesOnDeactivate = false
        panel.ignoresMouseEvents = false
        panel.contentView = hostingView
        hostingView.autoresizingMask = [.width, .height]

        if let saved = Preferences.widgetOrigin {
            anchor = NSPoint(x: saved.x, y: saved.y)
            anchorRight = saved.x > screenMidX()
        }
        bindRootView()
    }

    func show() {
        reposition(for: hostingView.fittingSize)
        panel.orderFrontRegardless()
    }

    private func bindRootView() {
        hostingView.rootView = WidgetView(
            model: model,
            anchorRight: anchorRight,
            onResize: { [weak self] size in self?.reposition(for: size) },
            onDragChanged: { [weak self] t in self?.dragChanged(t) },
            onDragEnded: { [weak self] in self?.dragEnded() }
        )
    }

    // MARK: Positioning (anchor corner stays fixed across resizes)

    private func reposition(for size: CGSize) {
        let w = max(size.width, 1), h = max(size.height, 1)
        if anchor == nil { anchor = defaultAnchor(); anchorRight = true; bindRootView() }
        applyFrame(size: CGSize(width: w, height: h), animated: false)
    }

    private func applyFrame(size: CGSize, animated: Bool) {
        guard let a = anchor, let vf = NSScreen.main?.visibleFrame else { return }
        var originX = anchorRight ? a.x - size.width : a.x
        var originY = a.y
        originX = min(max(originX, vf.minX), vf.maxX - size.width)
        originY = min(max(originY, vf.minY), vf.maxY - size.height)
        anchor = NSPoint(x: anchorRight ? originX + size.width : originX, y: originY)
        let frame = NSRect(x: originX, y: originY, width: size.width, height: size.height)
        if animated {
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.22
                ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
                panel.animator().setFrame(frame, display: true)
            }
        } else {
            panel.setFrame(frame, display: true)
        }
    }

    private func defaultAnchor() -> NSPoint {
        guard let vf = NSScreen.main?.visibleFrame else { return NSPoint(x: 40, y: 40) }
        return NSPoint(x: vf.maxX - edgeMargin, y: vf.minY + edgeMargin)   // bottom-right
    }

    private func screenMidX() -> CGFloat { (NSScreen.main?.visibleFrame).map { $0.midX } ?? 0 }

    // MARK: Dragging + snapping

    private func dragChanged(_ t: CGSize) {
        if dragStartOrigin == nil { dragStartOrigin = panel.frame.origin }
        guard let start = dragStartOrigin, let vf = NSScreen.main?.visibleFrame else { return }
        let size = panel.frame.size
        var x = start.x + t.width
        var y = start.y - t.height          // SwiftUI +y down → screen +y up
        x = min(max(x, vf.minX), vf.maxX - size.width)
        y = min(max(y, vf.minY), vf.maxY - size.height)
        panel.setFrameOrigin(NSPoint(x: x, y: y))
        snapGuide.show(target: nearestEdge(of: panel.frame, in: vf))
    }

    private func dragEnded() {
        dragStartOrigin = nil
        snapGuide.hide()
        guard let vf = NSScreen.main?.visibleFrame else { return }
        let frame = panel.frame
        let edge = nearestEdge(of: frame, in: vf)

        // The cross axis is clamped to the same inset, so a widget dropped in a corner ends up
        // neatly inset rather than jammed against two edges at once.
        switch edge {
        case .left:
            anchorRight = false
            anchor = NSPoint(x: vf.minX + edgeMargin, y: clampY(frame, in: vf))
        case .right:
            anchorRight = true
            anchor = NSPoint(x: vf.maxX - edgeMargin, y: clampY(frame, in: vf))
        case .bottom:
            anchorRight = frame.midX > vf.midX
            let x = clampX(frame, in: vf)
            anchor = NSPoint(x: anchorRight ? x + frame.width : x, y: vf.minY + edgeMargin)
        }
        bindRootView()                          // flip layout to expand inward
        applyFrame(size: frame.size, animated: true)
        if let a = anchor { Preferences.widgetOrigin = CGPoint(x: a.x, y: a.y) }
    }

    private func clampY(_ frame: NSRect, in vf: NSRect) -> CGFloat {
        min(max(frame.minY, vf.minY + edgeMargin), vf.maxY - frame.height - edgeMargin)
    }

    private func clampX(_ frame: NSRect, in vf: NSRect) -> CGFloat {
        min(max(frame.minX, vf.minX + edgeMargin), vf.maxX - frame.width - edgeMargin)
    }

    /// Nearest of the three dockable edges to the widget's center.
    private func nearestEdge(of frame: NSRect, in vf: NSRect) -> WidgetEdge {
        let dLeft = frame.midX - vf.minX
        let dRight = vf.maxX - frame.midX
        let dBottom = frame.midY - vf.minY
        let m = min(dLeft, dRight, dBottom)
        if m == dBottom { return .bottom }
        return dLeft < dRight ? .left : .right
    }
}
