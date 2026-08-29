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
///
/// ## Sizing, and why it is fussy
///
/// `WidgetView` can't safely report its own size as it morphs — see below — so instead it signals
/// *that* something sized-relevant changed, and the panel measures and resizes itself, animating
/// to match the pill's own 0.22s curve so the window and the content move together instead of one
/// snapping ahead of the other.
///
/// Two rules keep that resize from taking the app down:
///
///  * **The hosting view is nested, not the `contentView`.** When `NSHostingView` owns the
///    window, resizing it re-marks the window for another constraints pass *from inside the
///    current one*, and AppKit aborts with
///    "…more Update Constraints in Window passes than there are views in the window."
///    One level of nesting (a plain `container`) takes that ownership away — but it also means
///    a `GeometryReader` background can no longer report the pill's live size: that trick only
///    fires reliably while the hosting view *is* the window's own contentView. Past the first
///    layout it silently stops updating, which is why sizing is driven by explicit signals
///    instead (see `WidgetView.onLayoutChanged`).
///  * **The resize is applied on the next runloop turn, never synchronously.** The signal
///    arrives mid-display-cycle; bouncing the actual `setFrame` to the next turn keeps it out of
///    that cycle, and rounding to whole points (dropping a size the panel already has) stops the
///    window and SwiftUI trading `127.5` against `127` forever.
///
/// Drop either rule and a morphing pill takes the app down within a fraction of a second.
final class WidgetPanelController {
    private let model: AppModel
    private let panel: NSPanel
    private let hostingView: NSHostingView<WidgetView>
    /// Plain view between the panel and the SwiftUI content — see the note in `init`.
    private let container = NSView()
    private let snapGuide = SnapGuideController()

    private var anchor: NSPoint?          // fixed corner (bottom-right if anchorRight, else bottom-left)
    private var anchorRight = true
    private var dragStartOrigin: NSPoint?
    private var repositionScheduled = false

    /// The design's snap inset is 26pt from the screen edge, measured to the *visible* pill.
    /// `WidgetView` carries a transparent margin so its shadow never clips, so the window sits
    /// that much further out than the pill does — subtract it back off.
    private let snapInset: CGFloat = 26
    private let shadowPad: CGFloat = 14
    private var edgeMargin: CGFloat { snapInset - shadowPad }

    /// Matches `WidgetView`'s `.animation(.easeInOut(duration: 0.22), ...)` on the pill itself,
    /// so the window and the content move on the same curve instead of one outrunning the other.
    private let morphDuration: TimeInterval = 0.22

    init(model: AppModel) {
        self.model = model
        hostingView = NSHostingView(rootView: WidgetView(model: model))
        panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 120, height: 56),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered, defer: false
        )
        // The hosting view is deliberately a *subview*, not the panel's contentView.
        //
        // When `NSHostingView` is the contentView, SwiftUI considers itself the owner of the
        // window and resizes it from `windowDidLayout` — inside the window's own layout pass:
        //
        //     -[NSWindow layoutIfNeeded]
        //       NSHostingView.windowDidLayout()
        //         NSHostingView.updateAnimatedWindowSize()
        //           -[NSView setFrameSize:]
        //             -[NSView setNeedsUpdateConstraints:]   ← marks the window again
        //
        // Marking the window mid-pass re-runs the pass, and AppKit's allowance is "more passes
        // than there are views in the window". This window has almost no views, so a morphing
        // pill blows through it in a fraction of a second and raises:
        //
        //     The window has been marked as needing another Update Constraints in Window pass,
        //     but it has already had more Update Constraints in Window passes than there are
        //     views in the window.
        //
        // One level of nesting removes that ownership. Sizing stays ours, driven by the size
        // `WidgetView` reports — see `reposition(for:)`.
        // Order matters: the container has to be the contentView *before* its bounds are read,
        // or it is still zero-sized — and an autoresizing mask cannot grow a view from zero, so
        // the SwiftUI content would lay out into nothing and measure 0x0 forever.
        let start = NSRect(x: 0, y: 0, width: 120, height: 56)
        container.frame = start
        hostingView.frame = start
        hostingView.autoresizingMask = [.width, .height]
        container.addSubview(hostingView)
        panel.contentView = container
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.isMovableByWindowBackground = false
        panel.hidesOnDeactivate = false
        panel.ignoresMouseEvents = false

        if let saved = Preferences.widgetOrigin {
            anchor = NSPoint(x: saved.x, y: saved.y)
            anchorRight = saved.x > screenMidX()
        }
        bindRootView()
    }

    func show() {
        if anchor == nil { anchor = defaultAnchor(); anchorRight = true; bindRootView() }
        // Seed a real size up front, unanimated. `remeasure()` keeps it current after this.
        hostingView.layoutSubtreeIfNeeded()
        apply(size: hostingView.fittingSize, animated: false)
        panel.orderFrontRegardless()
    }

    private func bindRootView() {
        hostingView.rootView = WidgetView(
            model: model,
            anchorRight: anchorRight,
            onLayoutChanged: { [weak self] in self?.remeasure() },
            onDragChanged: { [weak self] t in self?.dragChanged(t) },
            onDragEnded: { [weak self] in self?.dragEnded() }
        )
    }

    // MARK: Sizing

    /// Something that can change the pill's size just changed. Re-measure and resize on the next
    /// runloop turn — never synchronously inside the state change, which is delivered
    /// mid-display-cycle where a `setFrame` would re-enter AppKit's layout pass (see the crash
    /// note on `init`). By the next turn the new state has settled, so `fittingSize` reports the
    /// real destination rather than a frame of the in-flight SwiftUI animation.
    private func remeasure() {
        guard !repositionScheduled else { return }
        repositionScheduled = true
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.repositionScheduled = false
            if self.anchor == nil { self.anchor = self.defaultAnchor(); self.anchorRight = true; self.bindRootView() }
            self.hostingView.layoutSubtreeIfNeeded()
            self.apply(size: self.hostingView.fittingSize, animated: true)
        }
    }

    /// Whole points only — a window cannot hold a half-point width, and asking it to is how the
    /// layout engine ends up chasing its own tail.
    private func apply(size: CGSize, animated: Bool) {
        let target = CGSize(width: size.width.rounded(.up), height: size.height.rounded(.up))
        // A measurement this small means the content was laid out in a collapsed host rather
        // than at its own size; taking it would make that permanent.
        guard target.width >= 24, target.height >= 24 else { return }
        let current = panel.frame.size
        guard abs(current.width - target.width) >= 0.5 || abs(current.height - target.height) >= 0.5
        else { return }
        applyFrame(size: target, animated: animated)
    }

    /// Sets the panel's frame so its anchored corner stays put as the pill grows and shrinks.
    /// Animated resizes run on the same duration and curve as the pill's own morph, so the window
    /// grows and shrinks in step with the content instead of jumping ahead of or behind it.
    private func applyFrame(size: CGSize, animated: Bool) {
        guard let a = anchor, let vf = NSScreen.main?.visibleFrame else { return }
        var originX = anchorRight ? a.x - size.width : a.x
        var originY = a.y
        originX = min(max(originX, vf.minX), vf.maxX - size.width)
        originY = min(max(originY, vf.minY), vf.maxY - size.height)
        anchor = NSPoint(x: anchorRight ? originX + size.width : originX, y: originY)
        let frame = NSRect(origin: NSPoint(x: originX, y: originY), size: size)
        if animated {
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = morphDuration
                ctx.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                panel.animator().setFrame(frame, display: true)
            }
        } else {
            panel.setFrame(frame, display: true)
        }
    }

    // MARK: Positioning

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

        guard let a = anchor else { return }
        Preferences.widgetOrigin = CGPoint(x: a.x, y: a.y)

        // Animate the slide home. Origin only — the size is already correct.
        let target = NSPoint(x: anchorRight ? a.x - frame.width : a.x, y: a.y)
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.22
            ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().setFrameOrigin(target)
        }
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
