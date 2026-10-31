import SwiftUI

struct SolarIcon: View {
    let name: String
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
        Solar.speakers: "person.2.fill",
        Solar.pen: "pencil",
        Solar.info: "info.circle.fill",
    ]
}

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
    static let danger      = "danger-triangle-bold"
    static let key         = "key-bold-duotone"
    static let speakers    = "users-group-rounded-bold-duotone"
    static let pen         = "pen-bold-duotone"
    static let info        = "info-circle-bold-duotone"
}
