import SwiftUI

struct TwoColumn<L: View, R: View>: View {
    let leftFr: CGFloat
    let rightFr: CGFloat
    var spacing: CGFloat = 20
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
                    .onChange(of: g.size.width) { _, newValue in width = newValue }
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

struct Card<Content: View>: View {
    var radius: CGFloat = Theme.Radius.card
    var padding: CGFloat = 22
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
