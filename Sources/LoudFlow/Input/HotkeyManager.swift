import Foundation
import CoreGraphics
import QuartzCore

/// Global trigger hotkeys via a `CGEventTap`:
///   • **hold** — ⌥Space keydown starts, keyup (or releasing Option) stops. Auto-repeat is
///     guarded, and the Space is consumed so it isn't typed into the frontmost app.
///   • **double** — double-tap either Control key toggles recording.
///
/// Requires Accessibility permission (the tap can't be created without it). "click" mode
/// installs no tap at all.
final class HotkeyManager {
    var onHoldStart: (() -> Void)?
    var onHoldStop: (() -> Void)?
    var onDoubleTapToggle: (() -> Void)?

    private var mode: TriggerMode = .click
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?

    private var isHolding = false
    private var lastControlTap: CFTimeInterval = 0
    private var retryTimer: Timer?

    func setMode(_ mode: TriggerMode) {
        self.mode = mode
        isHolding = false
        if mode == .click { teardown() } else { ensureTap() }
    }

    /// Called only when the user explicitly picks a hold/double trigger: prompt for
    /// Accessibility + Input Monitoring (both can be needed for a keyboard event tap), then
    /// install. This is the ONLY place that prompts.
    func requestPermissionAndInstall() {
        Permissions.requestAccessibility()
        Permissions.requestInputMonitoring()
        ensureTap()
    }

    func stop() { teardown() }

    // MARK: Tap lifecycle

    private func ensureTap() {
        guard eventTap == nil, mode != .click else { return }
        // Only install once trust is granted; otherwise poll until it is, so the hotkey starts
        // working right after the user flips the toggle in System Settings — no relaunch needed.
        guard Permissions.hasAccessibility() else { startRetry(); return }

        let mask = (1 << CGEventType.keyDown.rawValue)
                 | (1 << CGEventType.keyUp.rawValue)
                 | (1 << CGEventType.flagsChanged.rawValue)

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: CGEventMask(mask),
            callback: hotkeyTapCallback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else { startRetry(); return }   // e.g. Input Monitoring not yet granted

        eventTap = tap
        let src = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        runLoopSource = src
        CFRunLoopAddSource(CFRunLoopGetMain(), src, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        stopRetry()
    }

    /// Retry installing the tap every 1.5s until it succeeds (permission granted mid-session).
    private func startRetry() {
        guard retryTimer == nil else { return }
        retryTimer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { [weak self] _ in
            guard let self else { return }
            if self.mode == .click || self.eventTap != nil { self.stopRetry(); return }
            self.ensureTap()
        }
    }
    private func stopRetry() { retryTimer?.invalidate(); retryTimer = nil }

    private func teardown() {
        stopRetry()
        if let tap = eventTap { CGEvent.tapEnable(tap: tap, enable: false) }
        if let src = runLoopSource { CFRunLoopRemoveSource(CFRunLoopGetMain(), src, .commonModes) }
        eventTap = nil
        runLoopSource = nil
    }

    fileprivate func reenable() {
        if let tap = eventTap { CGEvent.tapEnable(tap: tap, enable: true) }
    }

    // MARK: Event handling (returns true to consume the event)

    fileprivate func handle(type: CGEventType, event: CGEvent) -> Bool {
        switch mode {
        case .hold:   return handleHold(type: type, event: event)
        case .double: handleDouble(type: type, event: event); return false
        case .click:  return false
        }
    }

    private func handleHold(type: CGEventType, event: CGEvent) -> Bool {
        let space: Int64 = 49
        let keycode = event.getIntegerValueField(.keyboardEventKeycode)
        let optionDown = event.flags.contains(.maskAlternate)

        if type == .keyDown, keycode == space, optionDown {
            if !isHolding { isHolding = true; DispatchQueue.main.async { self.onHoldStart?() } }
            return true // swallow the space
        }
        if type == .keyUp, keycode == space, isHolding {
            isHolding = false
            DispatchQueue.main.async { self.onHoldStop?() }
            return true
        }
        if type == .flagsChanged, isHolding, !optionDown {
            isHolding = false
            DispatchQueue.main.async { self.onHoldStop?() }
        }
        return false
    }

    private func handleDouble(type: CGEventType, event: CGEvent) {
        guard type == .flagsChanged else { return }
        let keycode = event.getIntegerValueField(.keyboardEventKeycode)
        let controlKeys: Set<Int64> = [59, 62] // left / right Control
        guard controlKeys.contains(keycode), event.flags.contains(.maskControl) else { return } // press only
        let now = CACurrentMediaTime()
        if now - lastControlTap < 0.35 {
            lastControlTap = 0
            DispatchQueue.main.async { self.onDoubleTapToggle?() }
        } else {
            lastControlTap = now
        }
    }
}

/// C callback for the event tap. Recovers the manager from `refcon` and asks it to handle the
/// event; re-enables the tap if the system disabled it.
private func hotkeyTapCallback(
    proxy: CGEventTapProxy,
    type: CGEventType,
    event: CGEvent,
    refcon: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
    if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
        if let refcon {
            Unmanaged<HotkeyManager>.fromOpaque(refcon).takeUnretainedValue().reenable()
        }
        return Unmanaged.passUnretained(event)
    }
    guard let refcon else { return Unmanaged.passUnretained(event) }
    let manager = Unmanaged<HotkeyManager>.fromOpaque(refcon).takeUnretainedValue()
    return manager.handle(type: type, event: event) ? nil : Unmanaged.passUnretained(event)
}
