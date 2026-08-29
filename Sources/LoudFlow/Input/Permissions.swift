import Foundation
import AVFoundation
import AppKit
import ApplicationServices
import IOKit.hid

/// Microphone and Accessibility permission helpers.
///
/// - **Microphone**: standard AVFoundation TCC prompt (also needs the Info.plist usage string).
/// - **Accessibility**: required for the global hold/double-tap hotkeys and for typing text
///   into other apps. There is no programmatic grant — the user flips it in
///   System Settings → Privacy & Security → Accessibility. `requestAccessibility()` shows the
///   system prompt and opens the pane.
enum Permissions {

    // MARK: Microphone

    static func micStatus() -> AVAuthorizationStatus {
        AVCaptureDevice.authorizationStatus(for: .audio)
    }

    static func requestMic(_ completion: @escaping (Bool) -> Void) {
        switch micStatus() {
        case .authorized:
            completion(true)
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .audio) { granted in
                DispatchQueue.main.async { completion(granted) }
            }
        default:
            completion(false)
        }
    }

    // MARK: Accessibility

    static func hasAccessibility() -> Bool {
        AXIsProcessTrusted()
    }

    /// Shows the system Accessibility prompt (if not yet trusted) and opens the pane.
    @discardableResult
    static func requestAccessibility() -> Bool {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        let trusted = AXIsProcessTrustedWithOptions([key: true] as CFDictionary)
        if !trusted { openAccessibilitySettings() }
        return trusted
    }

    /// Shows the system Accessibility prompt (once) without force-opening System Settings.
    /// Used when an auto-type attempt fails because trust isn't granted.
    static func nudgeAccessibility() {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        _ = AXIsProcessTrustedWithOptions([key: true] as CFDictionary)
    }

    static func openAccessibilitySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    // MARK: Input Monitoring

    /// Modern macOS can require Input Monitoring (in addition to Accessibility) for a keyboard
    /// event tap to actually receive key events.
    static func hasInputMonitoring() -> Bool {
        IOHIDCheckAccess(kIOHIDRequestTypeListenEvent) == kIOHIDAccessTypeGranted
    }

    @discardableResult
    static func requestInputMonitoring() -> Bool {
        IOHIDRequestAccess(kIOHIDRequestTypeListenEvent)
    }
}
