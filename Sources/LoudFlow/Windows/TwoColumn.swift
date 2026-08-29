import SwiftUI

/// A top-aligned two-column row with proportional widths (the spec's `minmax(0,Xfr)` tracks)
/// and `min-width: 0` behavior, so long transcript text never forces horizontal overflow.
struct TwoColumn<L: View, R: View>: View {
    let leftFr: CGFloat
    let rightFr: CGFloat
    var spacing: CGFloat = 20
    @ViewBuilder var left: () -> L
    @ViewBuilder var right: () -> R

    @State private var width: CGFloat = 0

    var body: some View {
        HStack(alignment: .top, spacing: spacing) {
            left().frame(width: colWidth(leftFr))
            right().frame(width: colWidth(rightFr))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            GeometryReader { g in
                Color.clear
                    .onAppear { width = g.size.width }
                    .onChange(of: g.size.width) { newValue in width = newValue }
            }
        )
    }

    private func colWidth(_ fr: CGFloat) -> CGFloat {
        let total = max(0, width - spacing)
        return total * (fr / (leftFr + rightFr))
    }
}

/// A standard light card surface (Card fill, rounded, soft shadow).
struct Card<Content: View>: View {
    var radius: CGFloat = Theme.Radius.card
    var padding: CGFloat = 22
    @ViewBuilder var content: () -> Content

    var body: some View {
        content()
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: radius).fill(Theme.card))
            .themeShadow(Theme.Shadow.card)
    }
}
