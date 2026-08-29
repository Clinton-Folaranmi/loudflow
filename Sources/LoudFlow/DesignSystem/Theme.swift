import SwiftUI

/// The LoudFlow palette, spacing, radii, and shadows — transcribed verbatim from the design
/// handoff. These values are final; do not invent new colors.
///
/// Rule of the palette: **Marigold means recording, or the one action on this surface.
/// Sage means the app itself, and things that are on.** Danger red is used for the "Delete
/// clip" label only. Never add a second decorative marigold to a surface.
enum Theme {
    // MARK: Surfaces / neutrals
    static let desk          = Color(hex: 0xDCE5DA) // app background ("desk"); also inactive chart bars
    static let card          = Color(hex: 0xFDFBF6) // primary card surfaces, sidebar, widget
    static let row           = Color(hex: 0xF7F9F5) // clip row background inside cards
    static let rowHover      = Color(hex: 0xEDF2E9) // clip row hover
    static let rowSelected   = Color(hex: 0xF1F5EF) // selected clip row in Library

    // MARK: Sage family (the app, and "on")
    static let sagePale      = Color(hex: 0xEAF0E7) // active nav pill, play rest, progress track
    static let sagePale2     = Color(hex: 0xF1F4EF) // keycap chips, secondary pill backgrounds
    static let sage          = Color(hex: 0x7E9A82) // brand mark, progress fill, active bar, toggle on, mic
    static let sageDeep      = Color(hex: 0x3F5943) // text on sage-pale surfaces, active nav label

    // MARK: Ink (primary text + dark cards)
    static let ink           = Color(hex: 0x2A3129) // primary text; dark "Saved today" card; recording widget
    static let inkOnDark     = Color(hex: 0xF2F5F0) // text on ink
    static let inkMutedOnDark = Color(hex: 0xA9BCAB) // labels on ink
    static let inkBodyOnDark = Color(hex: 0xC3D0C2) // body copy on ink
    static let barOnDark     = Color(hex: 0x4C5A4A) // inactive bars inside the dark card
    static let dividerOnDark = Color(hex: 0x3D4A3C) // rule inside the dark card

    // MARK: Greys
    static let body          = Color(hex: 0x5C6659) // secondary text
    static let muted         = Color(hex: 0x8A9188) // tertiary text, metadata
    static let placeholder   = Color(hex: 0xA8B0A6) // empty-state text
    static let hairline      = Color(hex: 0xEDF0EB) // sidebar dividers
    static let hairline2     = Color(hex: 0xF0F3EE) // settings row dividers
    static let toggleOff     = Color(hex: 0xDDE4DA) // toggle track off, dashed borders
    static let countInactive = Color(hex: 0xB4BDB2) // nav count when inactive

    // MARK: Cream family (the one warm surface — transcript / editor)
    static let cream         = Color(hex: 0xFBF6EA)
    static let creamLine     = Color(hex: 0xEDE2C8) // dividers on cream
    static let creamLine2    = Color(hex: 0xEFE6D2) // editor field border
    static let creamChip     = Color(hex: 0xF1EBDA) // secondary button on cream
    static let creamInk      = Color(hex: 0x2A2620) // text on cream
    static let creamBody     = Color(hex: 0x5C5344) // secondary text on cream
    static let creamMuted    = Color(hex: 0xA08A5C) // metadata on cream

    // MARK: Marigold (the single signal color)
    static let marigold      = Color(hex: 0xE8B930) // recording, primary CTA on cream, peak bar
    static let marigoldInk   = Color(hex: 0x8A6A08) // text/icons on cream needing marigold weight
    static let marigoldInk2  = Color(hex: 0x7A5E0A) // label on the solid marigold card
    static let marigoldPale  = Color(hex: 0xFBF3DC) // marigold chip / selected retention card
    static let marigoldFlash = Color(hex: 0xFDF3D4) // momentary highlight when text lands

    // MARK: Danger (Delete label only)
    static let danger        = Color(hex: 0xF40000)

    // MARK: Link
    static let link          = Color(hex: 0x4E6B54)
    static let linkHover     = Color(hex: 0x3A5240)

    // MARK: Radii
    enum Radius {
        static let card: CGFloat = 22
        static let cardSmall: CGFloat = 20
        static let onboarding: CGFloat = 26
        static let rowInner: CGFloat = 14
        static let block: CGFloat = 18
        static let editor: CGFloat = 14
        static let pill: CGFloat = 99
        static let logo: CGFloat = 10
        static let keycap: CGFloat = 8
        static let bar: CGFloat = 8
    }

    // MARK: Shadows
    struct ShadowSpec { let color: Color; let radius: CGFloat; let x: CGFloat; let y: CGFloat }
    enum Shadow {
        static let card         = ShadowSpec(color: Color(hex: 0x2A3129, alpha: 0.06), radius: 12, x: 0, y: 2)
        static let widgetIdle   = ShadowSpec(color: Color(hex: 0x2A3129, alpha: 0.20), radius: 30, x: 0, y: 10)
        static let widgetHover  = ShadowSpec(color: Color(hex: 0x2A3129, alpha: 0.28), radius: 34, x: 0, y: 12)
        static let widgetRec    = ShadowSpec(color: Color(hex: 0x2A3129, alpha: 0.32), radius: 30, x: 0, y: 10)
        static let onboarding   = ShadowSpec(color: Color(hex: 0x141C14, alpha: 0.40), radius: 70, x: 0, y: 24)
    }
}

extension View {
    /// Applies one of the design system's named shadow presets.
    func themeShadow(_ s: Theme.ShadowSpec) -> some View {
        shadow(color: s.color, radius: s.radius, x: s.x, y: s.y)
    }
}

extension Color {
    /// Builds a Color from a 0xRRGGBB literal (+ optional alpha), in sRGB.
    init(hex: UInt32, alpha: Double = 1) {
        let r = Double((hex >> 16) & 0xFF) / 255
        let g = Double((hex >> 8) & 0xFF) / 255
        let b = Double(hex & 0xFF) / 255
        self.init(.sRGB, red: r, green: g, blue: b, opacity: alpha)
    }
}
