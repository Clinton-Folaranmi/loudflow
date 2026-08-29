import SwiftUI

/// A top-aligned two-column row with proportional widths (the spec's `minmax(0,Xfr)` tracks)
/// and `min-width: 0` behavior, so long transcript text never forces horizontal overflow.
struct TwoColumn<L: View, R: View>: View {
    let leftFr: CGFloat
    let rightFr: CGFloat
    var spacing: CGFloat = 20
    /// When true both columns stretch to the height of the row (the spec's `flex:1; min-height:0`),
    /// so each side can scroll inside its own box instead of growing the page.
    var fillHeight: Bool = false
    @ViewBuilder var left: () -> L
    @ViewBuilder var right: () -> R

    @State private var width: CGFloat = 0

    var body: some View {
        HStack(alignment: .top, spacing: spacing) {
            column(colWidth(leftFr)) { left() }
            column(colWidth(rightFr)) { right() }
        }
        .frame(maxWidth: .infinity, maxHeight: fillHeight ? .infinity : nil, alignment: .topLeading)
        .background(
            GeometryReader { g in
                Color.clear
                    .onAppear { width = g.size.width }
                    .onChange(of: g.size.width) { newValue in width = newValue }
            }
        )
    }

    @ViewBuilder private func column<C: View>(_ w: CGFloat, @ViewBuilder _ content: () -> C) -> some View {
        content()
            .frame(width: w)
            .frame(maxHeight: fillHeight ? .infinity : nil, alignment: .top)
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
    /// Stretch the card (and its content) to the height it is offered, for panes that scroll
    /// internally rather than growing.
    var fillHeight: Bool = false
    @ViewBuilder var content: () -> Content

    var body: some View {
        content()
            .padding(padding)
            .frame(maxWidth: .infinity, maxHeight: fillHeight ? .infinity : nil,
                   alignment: fillHeight ? .topLeading : .leading)
            .background(RoundedRectangle(cornerRadius: radius).fill(Theme.card))
            .themeShadow(Theme.Shadow.card)
    }
}
