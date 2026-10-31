import SwiftUI

enum Theme {

    static let desk          = Color(hex: 0xDCE5DA)
    static let card          = Color(hex: 0xFDFBF6)
    static let row           = Color(hex: 0xF7F9F5)
    static let rowHover      = Color(hex: 0xEDF2E9)

    static let sagePale      = Color(hex: 0xEAF0E7)
    static let sagePale2     = Color(hex: 0xF1F4EF)
    static let sage          = Color(hex: 0x7E9A82)
    static let sageDeep      = Color(hex: 0x3F5943)

    static let ink           = Color(hex: 0x2A3129)
    static let inkOnDark     = Color(hex: 0xF2F5F0)
    static let inkMutedOnDark = Color(hex: 0xA9BCAB)
    static let inkBodyOnDark = Color(hex: 0xC3D0C2)
    static let barOnDark     = Color(hex: 0x4C5A4A)
    static let dividerOnDark = Color(hex: 0x3D4A3C)

    static let body          = Color(hex: 0x5C6659)
    static let muted         = Color(hex: 0x8A9188)
    static let placeholder   = Color(hex: 0xA8B0A6)
    static let hairline      = Color(hex: 0xEDF0EB)
    static let hairline2     = Color(hex: 0xF0F3EE)
    static let toggleOff     = Color(hex: 0xDDE4DA)
    static let countInactive = Color(hex: 0xB4BDB2)
    static let chipLine      = Color(hex: 0xCBD6C7)
    static let playMuted     = Color(hex: 0xA8B0A6)

    static let cream         = Color(hex: 0xFBF6EA)
    static let creamLine     = Color(hex: 0xEDE2C8)
    static let creamLine2    = Color(hex: 0xEFE6D2)
    static let creamChip     = Color(hex: 0xF1EBDA)
    static let creamInk      = Color(hex: 0x2A2620)
    static let creamBody     = Color(hex: 0x5C5344)
    static let creamMuted    = Color(hex: 0xA08A5C)

    static let marigold      = Color(hex: 0xE8B930)
    static let marigoldInk   = Color(hex: 0x8A6A08)
    static let marigoldInk2  = Color(hex: 0x7A5E0A)
    static let marigoldPale  = Color(hex: 0xFBF3DC)
    static let marigoldFlash = Color(hex: 0xFDF3D4)

    static let danger        = Color(hex: 0xF40000)

    static let link          = Color(hex: 0x4E6B54)
    static let linkHover     = Color(hex: 0x3A5240)

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
    func themeShadow(_ s: Theme.ShadowSpec) -> some View {
        shadow(color: s.color, radius: s.radius, x: s.x, y: s.y)
    }
}

extension Color {
    init(hex: UInt32, alpha: Double = 1) {
        let r = Double((hex >> 16) & 0xFF) / 255
        let g = Double((hex >> 8) & 0xFF) / 255
        let b = Double(hex & 0xFF) / 255
        self.init(.sRGB, red: r, green: g, blue: b, opacity: alpha)
    }
}
