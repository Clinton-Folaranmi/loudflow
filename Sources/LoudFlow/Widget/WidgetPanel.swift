import AppKit
import SwiftUI

final class WidgetPanelController {
    private let model: AppModel
    private let panel: NSPanel
    private let hostingView: NSHostingView<WidgetView>
    private let container = NSView()
    private let snapGuide = SnapGuideController()

    private var anchor: NSPoint?
    private var anchorRight = true
    private var dragStartOrigin: NSPoint?
    private var dragStartCursor: NSPoint?
    private var remeasureAfterDrag = false
    private var repositionScheduled = false

    private let snapInset: CGFloat = 26
    private let shadowPad: CGFloat = 14
    private var edgeMargin: CGFloat { snapInset - shadowPad }

    private let morphDuration: TimeInterval = 0.22

    init(model: AppModel) {
        self.model = model
        hostingView = NSHostingView(rootView: WidgetView(model: model))
        panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 120, height: 56),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered, defer: false
        )
        let start = NSRect(x: 0, y: 0, width: 120, height: 56)
        container.frame = start
        hostingView.frame = start
        hostingView.autoresizingMask = [.width, .height]
        container.addSubview(hostingView)

        // Using the hosting view as contentView can cause an AppKit layout loop.
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

    private func remeasure() {
        if dragStartOrigin != nil {
            remeasureAfterDrag = true
            return
        }
        guard !repositionScheduled else { return }
        repositionScheduled = true

        // Measure after SwiftUI completes this update pass.
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.repositionScheduled = false
            if self.anchor == nil { self.anchor = self.defaultAnchor(); self.anchorRight = true; self.bindRootView() }
            self.hostingView.layoutSubtreeIfNeeded()
            self.apply(size: self.hostingView.fittingSize, animated: true)
        }
    }

    private func apply(size: CGSize, animated: Bool) {
        let target = CGSize(width: size.width.rounded(.up), height: size.height.rounded(.up))
        guard target.width >= 24, target.height >= 24 else { return }
        let current = panel.frame.size
        guard abs(current.width - target.width) >= 0.5 || abs(current.height - target.height) >= 0.5
        else { return }
        applyFrame(size: target, animated: animated)
    }

    private func applyFrame(size: CGSize, animated: Bool) {
        guard let a = anchor, let vf = (panel.screen ?? NSScreen.main)?.visibleFrame else { return }
        var originX = anchorRight ? a.x - size.width : a.x
        var originY = a.y
        originX = min(max(originX, vf.minX), vf.maxX - size.width)
        originY = min(max(originY, vf.minY), vf.maxY - size.height)
        anchor = NSPoint(x: anchorRight ? originX + size.width : originX, y: originY)
        let frame = NSRect(origin: NSPoint(x: originX, y: originY), size: size)
        if animated && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = morphDuration
                ctx.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                panel.animator().setFrame(frame, display: true)
            }
        } else {
            panel.setFrame(frame, display: true)
        }
    }

    private func defaultAnchor() -> NSPoint {
        guard let vf = NSScreen.main?.visibleFrame else { return NSPoint(x: 40, y: 40) }
        return NSPoint(x: vf.maxX - edgeMargin, y: vf.minY + edgeMargin)
    }

    private func screenMidX() -> CGFloat { (NSScreen.main?.visibleFrame).map { $0.midX } ?? 0 }

    private func dragScreen(for cursor: NSPoint) -> NSScreen? {
        NSScreen.screens.first(where: { $0.frame.contains(cursor) }) ?? panel.screen ?? NSScreen.main
    }

    private var combinedVisibleFrame: NSRect {
        NSScreen.screens.map(\.visibleFrame).reduce(.null) { $0.union($1) }
    }

    private func dragChanged(_ t: CGSize) {
        // Local coordinates move with the panel during a drag.
        let cursor = NSEvent.mouseLocation
        let firstUpdate = dragStartOrigin == nil
        if firstUpdate {
            dragStartOrigin = panel.frame.origin
            dragStartCursor = NSPoint(x: cursor.x - t.width, y: cursor.y + t.height)
        }
        guard let start = dragStartOrigin, let pointerStart = dragStartCursor,
              let screen = dragScreen(for: cursor) else { return }
        let vf = screen.visibleFrame
        let size = panel.frame.size

        var x = start.x + cursor.x - pointerStart.x
        var y = start.y + cursor.y - pointerStart.y
        let travel = combinedVisibleFrame
        x = min(max(x, travel.minX), travel.maxX - size.width)
        y = min(max(y, travel.minY), travel.maxY - size.height)
        panel.setFrameOrigin(NSPoint(x: x, y: y))
        let target = nearestEdge(of: panel.frame, in: vf)
        if firstUpdate { snapGuide.show(target: target, in: vf) }
        else { snapGuide.update(target: target, in: vf) }
    }

    private func dragEnded() {
        dragStartOrigin = nil
        dragStartCursor = nil
        snapGuide.hide()
        guard let vf = dragScreen(for: NSEvent.mouseLocation)?.visibleFrame else { return }
        let frame = panel.frame
        let edge = nearestEdge(of: frame, in: vf)
        let previousAnchorRight = anchorRight

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
        if previousAnchorRight != anchorRight {
            bindRootView()
        }

        guard let a = anchor else { return }
        Preferences.widgetOrigin = CGPoint(x: a.x, y: a.y)

        let target = NSPoint(x: anchorRight ? a.x - frame.width : a.x, y: a.y)
        if NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            panel.setFrameOrigin(target)
        } else {
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.22
                ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
                panel.animator().setFrameOrigin(target)
            }
        }
        remeasureAfterDrag = false
        let settleDelay = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? 0 : 0.22
        DispatchQueue.main.asyncAfter(deadline: .now() + settleDelay) { [weak self] in
            self?.remeasure()
        }
    }

    private func clampY(_ frame: NSRect, in vf: NSRect) -> CGFloat {
        min(max(frame.minY, vf.minY + edgeMargin), vf.maxY - frame.height - edgeMargin)
    }

    private func clampX(_ frame: NSRect, in vf: NSRect) -> CGFloat {
        min(max(frame.minX, vf.minX + edgeMargin), vf.maxX - frame.width - edgeMargin)
    }

    private func nearestEdge(of frame: NSRect, in vf: NSRect) -> WidgetEdge {
        let dLeft = frame.midX - vf.minX
        let dRight = vf.maxX - frame.midX
        let dBottom = frame.midY - vf.minY
        let m = min(dLeft, dRight, dBottom)
        if m == dBottom { return .bottom }
        return dLeft < dRight ? .left : .right
    }
}
