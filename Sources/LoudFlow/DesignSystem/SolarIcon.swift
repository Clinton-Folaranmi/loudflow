import SwiftUI

/// Renders a bundled Solar (Iconify) icon as a tintable template image.
///
/// Icons are fetched into the asset catalog by `scripts/fetch-assets.sh` as
/// `solar-<name>` imagesets. If an icon hasn't been fetched yet, this falls back to the
/// nearest SF Symbol so the UI still renders in Xcode previews.
struct SolarIcon: View {
    let name: String              // Solar name without the "solar:" prefix, e.g. "microphone-3-bold"
    var size: CGFloat = 18
    var color: Color = Theme.ink

    var body: some View {
        Group {
            if NSImage(named: assetName) != nil {
                Image(assetName)
                    .renderingMode(.template)
                    .resizable()
                    .interpolation(.high)
                    .scaledToFit()
            } else {
                Image(systemName: Self.sfFallback[name] ?? "circle")
                    .resizable()
                    .scaledToFit()
                    .font(.system(size: size, weight: .bold))
            }
        }
        .frame(width: size, height: size)
        .foregroundColor(color)
    }

    private var assetName: String { "solar-\(name)" }

    /// SF Symbol stand-ins used only when the Solar asset is missing.
    private static let sfFallback: [String: String] = [
        Solar.mic: "mic.fill",
        Solar.today: "waveform",
        Solar.folder: "folder.fill",
        Solar.settings: "gearshape.fill",
        Solar.receipts: "chart.bar.doc.horizontal.fill",
        Solar.database: "internaldrive.fill",
        Solar.restart: "arrow.clockwise",
        Solar.copy: "doc.on.doc.fill",
        Solar.arrowRight: "chevron.right",
        Solar.play: "play.fill",
        Solar.pause: "pause.fill",
        Solar.check: "checkmark.circle.fill",
        Solar.trash: "trash.fill",
        Solar.cursor: "cursorarrow.rays",
        Solar.keyboard: "keyboard.fill",
        Solar.handStars: "hand.tap.fill",
        Solar.history: "clock.arrow.circlepath",
        Solar.textField: "character.textbox",
        Solar.stopwatch: "stopwatch.fill",
        Solar.stop: "stop.fill",
        Solar.textSquare: "text.append",
        Solar.danger: "exclamationmark.triangle.fill",
        Solar.key: "key.fill",
    ]
}

/// Canonical Solar icon names used across the app (from the spec's icon table, plus the
/// two added for the widget error states and the Settings key card).
enum Solar {
    static let mic         = "microphone-3-bold"
    static let today       = "soundwave-bold-duotone"
    static let folder      = "folder-with-files-bold-duotone"
    static let settings    = "settings-bold-duotone"
    static let receipts    = "chart-square-bold-duotone"
    static let database    = "database-bold-duotone"
    static let restart     = "restart-bold-duotone"
    static let copy        = "copy-bold-duotone"
    static let arrowRight  = "alt-arrow-right-bold"
    static let play        = "play-bold"
    static let pause       = "pause-bold"
    static let check       = "check-circle-bold"
    static let trash       = "trash-bin-trash-bold-duotone"
    static let cursor      = "cursor-bold-duotone"
    static let keyboard    = "keyboard-bold-duotone"
    static let handStars   = "hand-stars-bold-duotone"
    static let history     = "history-bold-duotone"
    static let textField   = "text-field-bold-duotone"
    static let stopwatch   = "stopwatch-bold-duotone"
    static let stop        = "stop-bold"
    static let textSquare  = "text-square-bold"
    static let danger      = "danger-triangle-bold" // widget error states (added)
    static let key         = "key-bold-duotone"      // Settings transcription card (added)
}
