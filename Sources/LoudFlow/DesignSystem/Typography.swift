import SwiftUI
import CoreText
import AppKit

enum Typo {
    static let family = "Nunito"

    private static let wghtAxis = NSNumber(value: 0x77676874 as UInt32)

    private static var didRegister = false
    static func registerIfNeeded() {
        guard !didRegister else { return }
        didRegister = true
        if let url = Bundle.main.url(forResource: "Nunito", withExtension: "ttf", subdirectory: "Fonts")
            ?? Bundle.main.url(forResource: "Nunito", withExtension: "ttf") {
            CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
        }
    }

    private static var available: Bool {
        registerIfNeeded()
        return NSFontManager.shared.availableFontFamilies.contains(family)
    }

    private static func nunito(_ size: CGFloat, _ weight: CGFloat) -> NSFont? {
        guard available else { return nil }
        let attrs: [CFString: Any] = [
            kCTFontFamilyNameAttribute: family,
            kCTFontVariationAttribute: [wghtAxis: NSNumber(value: Double(weight))],
        ]
        let desc = CTFontDescriptorCreateWithAttributes(attrs as CFDictionary)
        let ct = CTFontCreateWithFontDescriptor(desc, size, nil)
        return ct as NSFont
    }

    private static func systemWeight(_ w: CGFloat) -> Font.Weight {
        switch w {
        case ..<450: return .regular
        case ..<550: return .medium
        case ..<650: return .semibold
        case ..<750: return .bold
        default:     return .heavy
        }
    }

    static func font(_ size: CGFloat, _ weight: CGFloat) -> Font {
        if let ns = nunito(size, weight) { return Font(ns) }
        return .system(size: size, weight: systemWeight(weight))
    }
}

struct TextStyleSpec {
    var size: CGFloat
    var weight: CGFloat
    var trackingEm: CGFloat = 0
    var lineHeight: CGFloat? = nil

    static let greeting        = TextStyleSpec(size: 34, weight: 800, trackingEm: -0.03, lineHeight: 1.1)
    static let pageTitle       = TextStyleSpec(size: 32, weight: 800, trackingEm: -0.03, lineHeight: 1.1)
    static let subtitle        = TextStyleSpec(size: 14.5, weight: 400)
    static let bigStat         = TextStyleSpec(size: 44, weight: 800, trackingEm: -0.03, lineHeight: 1.05)
    static let statReceipts    = TextStyleSpec(size: 36, weight: 800, trackingEm: -0.03)
    static let cardTitle       = TextStyleSpec(size: 16, weight: 800)
    static let cardTitleSm     = TextStyleSpec(size: 15, weight: 800)
    static let sectionLabel    = TextStyleSpec(size: 11.5, weight: 700, trackingEm: 0.09)
    static let body            = TextStyleSpec(size: 14, weight: 400, lineHeight: 1.5)
    static let bodySmall       = TextStyleSpec(size: 13, weight: 400, lineHeight: 1.5)
    static let transcript      = TextStyleSpec(size: 17.5, weight: 400, lineHeight: 1.65)
    static let clipRow         = TextStyleSpec(size: 14, weight: 400, lineHeight: 1.4)
    static let clipRowSelected = TextStyleSpec(size: 14, weight: 700, lineHeight: 1.4)
    static let metadata        = TextStyleSpec(size: 11.5, weight: 600)
    static let metadataStrong  = TextStyleSpec(size: 12, weight: 700)
    static let navItem         = TextStyleSpec(size: 13.5, weight: 400)
    static let navItemActive   = TextStyleSpec(size: 13.5, weight: 700)
    static let button          = TextStyleSpec(size: 13, weight: 800)
    static let onboardingTitle = TextStyleSpec(size: 27, weight: 800, trackingEm: -0.03, lineHeight: 1.15)
    static let onboardingKicker = TextStyleSpec(size: 11.5, weight: 800, trackingEm: 0.12)
}

private struct TextStyleModifier: ViewModifier {
    let spec: TextStyleSpec
    func body(content: Content) -> some View {
        var v = AnyView(
            content
                .font(Typo.font(spec.size, spec.weight))
                .tracking(spec.trackingEm * spec.size)
        )
        if let lh = spec.lineHeight {
            v = AnyView(v.lineSpacing(spec.size * (lh - 1)))
        }
        return v
    }
}

extension View {
    func textStyle(_ spec: TextStyleSpec) -> some View { modifier(TextStyleModifier(spec: spec)) }
}
