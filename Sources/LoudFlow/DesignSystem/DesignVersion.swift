import Foundation

/// The design changelog version this build implements.
///
/// Bumped only when a version in `design/CHANGES.md` is applied **in full** — a partly-applied
/// version leaves this where it is. Shown next to the app version in the sidebar footer
/// (`LoudFlow 1.4.0 (10) · design 4`) so a stale build is visible without opening Xcode.
///
/// See `design/SYNC.md` for the weekly loop this belongs to.
enum DesignVersion {
    static let current = 5
}
