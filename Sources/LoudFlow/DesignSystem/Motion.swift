import SwiftUI

enum Motion {
    static let hover = Animation.easeOut(duration: 0.12)
    static let feedback = Animation.easeOut(duration: 0.16)
    static let page = Animation.easeOut(duration: 0.20)
    static let selection = Animation.spring(response: 0.28, dampingFraction: 0.86)
}

struct PressFeedbackStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.975 : 1)
            .animation(reduceMotion ? nil : Motion.hover, value: configuration.isPressed)
    }
}
