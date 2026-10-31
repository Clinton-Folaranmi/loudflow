import Foundation
import CoreGraphics
import QuartzCore

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

    func requestPermissionAndInstall() {
        Permissions.requestAccessibility()
        Permissions.requestInputMonitoring()
        ensureTap()
    }

    func stop() { teardown() }

    private func ensureTap() {
        guard eventTap == nil, mode != .click else { return }
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
        ) else { startRetry(); return }

        eventTap = tap
        let src = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        runLoopSource = src
        CFRunLoopAddSource(CFRunLoopGetMain(), src, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        stopRetry()
    }

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
            return true
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
        let controlKeys: Set<Int64> = [59, 62]
        guard controlKeys.contains(keycode), event.flags.contains(.maskControl) else { return }
        let now = CACurrentMediaTime()
        if now - lastControlTap < 0.35 {
            lastControlTap = 0
            DispatchQueue.main.async { self.onDoubleTapToggle?() }
        } else {
            lastControlTap = now
        }
    }
}

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
