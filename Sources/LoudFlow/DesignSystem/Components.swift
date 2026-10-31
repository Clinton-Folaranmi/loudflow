import SwiftUI

// MARK: - Waveform (fBar)

struct WaveBars: View {
    var count: Int = 8
    var totalWidth: CGFloat? = 74
    var height: CGFloat = 18
    var gap: CGFloat = 2.5
    var color: Color = Theme.marigold
    var duration: Double = 0.72
    var stagger: Double = 0.06
    var minScale: CGFloat = 0.16

    @State private var animating = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: gap) {
            ForEach(0..<count, id: \.self) { i in
                Capsule()
                    .fill(color)
                    .frame(maxWidth: .infinity)
                    .frame(height: height)
                    .scaleEffect(x: 1, y: reduceMotion ? 0.6 : (animating ? 1 : minScale), anchor: .center)
                    .animation(
                        reduceMotion ? nil : .easeInOut(duration: duration)
                            .repeatForever(autoreverses: true)
                            .delay(Double(i) * stagger),
                        value: animating
                    )
            }
        }
        .frame(width: totalWidth, height: height)
        .onAppear { animating = true }
    }
}

struct LiveWaveBars: View {
    var level: Double
    var count: Int = 12
    var height: CGFloat = 30
    var gap: CGFloat = 3
    var color: Color = Theme.sage
    var minScale: CGFloat = 0.12
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: gap) {
            ForEach(0..<count, id: \.self) { i in
                Capsule()
                    .fill(color)
                    .frame(maxWidth: .infinity)
                    .frame(height: height)
                    .scaleEffect(x: 1, y: barScale(i), anchor: .center)
                    .animation(reduceMotion ? nil : .easeOut(duration: 0.09), value: level)
            }
        }
        .frame(height: height)
    }

    private func barScale(_ i: Int) -> CGFloat {
        let mid = Double(count - 1) / 2
        let dist = abs(Double(i) - mid) / mid
        let weight = 1.5 * (1 - dist * 0.6)
        return max(minScale, min(1, CGFloat(level * weight)))
    }
}

// MARK: - Pulse (fPulse)

private struct Pulsing: ViewModifier {
    let duration: Double
    @State private var on = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    func body(content: Content) -> some View {
        content
            .scaleEffect(reduceMotion ? 1 : (on ? 1.18 : 1.0))
            .opacity(reduceMotion ? 1 : (on ? 1.0 : 0.8))
            .animation(reduceMotion ? nil : .easeInOut(duration: duration).repeatForever(autoreverses: true), value: on)
            .onAppear { on = true }
    }
}

extension View {
    func pulsing(_ duration: Double) -> some View { modifier(Pulsing(duration: duration)) }
}

// MARK: - fRise transition

extension AnyTransition {
    static var fRise: AnyTransition {
        .asymmetric(
            insertion: .opacity.combined(with: .offset(y: 10)),
            removal: .opacity
        )
    }

    static func fSlideIn(fromTrailing: Bool) -> AnyTransition {
        .asymmetric(
            insertion: .opacity.combined(with: .offset(x: fromTrailing ? 10 : -10)),
            removal: .opacity
        )
    }
}

// MARK: - Keycap chip

struct Keycap: View {
    let text: String
    var fontSize: CGFloat = 11.5
    var fg: Color = Theme.muted
    var bg: Color = Theme.sagePale2
    var radius: CGFloat = Theme.Radius.pill
    var hPad: CGFloat = 9
    var vPad: CGFloat = 4

    var body: some View {
        Text(text)
            .font(Typo.font(fontSize, 700))
            .foregroundColor(fg)
            .padding(.horizontal, hPad)
            .padding(.vertical, vPad)
            .background(RoundedRectangle(cornerRadius: radius).fill(bg))
    }
}

// MARK: - Toggle (settings)

struct LFToggle: View {
    let isOn: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        ZStack(alignment: .leading) {
            RoundedRectangle(cornerRadius: Theme.Radius.pill)
                .fill(isOn ? Theme.sage : Theme.toggleOff)
                .frame(width: 42, height: 24)
            Circle()
                .fill(Color.white)
                .frame(width: 18, height: 18)
                .shadow(color: Color.black.opacity(0.22), radius: 1.5, x: 0, y: 1)
                .offset(x: isOn ? 21 : 3)
        }
        .frame(width: 42, height: 24)
        .animation(reduceMotion ? nil : Motion.feedback, value: isOn)
    }
}

// MARK: - Week/bar chart

struct ChartBar: Identifiable {
    let id = UUID()
    var fraction: Double
    var color: Color
    var label: String? = nil
    var labelColor: Color = Theme.muted
    var labelWeight: CGFloat = 700
}

struct WeekChart: View {
    var bars: [ChartBar]
    var chartHeight: CGFloat
    var gap: CGFloat
    var topRadius: CGFloat = Theme.Radius.bar
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(alignment: .top, spacing: gap) {
            ForEach(Array(bars.enumerated()), id: \.offset) { _, b in
                VStack(spacing: 8) {
                    ZStack(alignment: .bottom) {
                        Color.clear.frame(maxWidth: .infinity).frame(height: chartHeight)
                        UnevenRoundedRectangle(topLeadingRadius: topRadius, topTrailingRadius: topRadius)
                            .fill(b.color)
                            .frame(maxWidth: .infinity)
                            .frame(height: max(2, chartHeight * b.fraction))
                    }
                    if let label = b.label {
                        Text(label)
                            .font(Typo.font(12, b.labelWeight))
                            .foregroundColor(b.labelColor)
                    }
                }
                .frame(maxWidth: .infinity)
            }
        }
        .animation(reduceMotion ? nil : Motion.page, value: bars.map(\.fraction))
    }
}

// MARK: - Progress track (sidebar storage / player)

struct ProgressTrack: View {
    var fraction: Double
    var height: CGFloat = 6
    var track: Color = Theme.sagePale
    var fill: Color = Theme.sage

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(track)
                Capsule().fill(fill)
                    .frame(width: max(0, min(1, fraction)) * geo.size.width)
            }
        }
        .frame(height: height)
    }
}

// MARK: - Spinning ring (in-row transcribing)

struct SpinRing: View {
    var size: CGFloat = 12
    var lineWidth: CGFloat = 2
    var track: Color = Theme.sagePale
    var lit: Color = Theme.sage

    @State private var spinning = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            Circle().stroke(track, lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: 0.25)
                .stroke(lit, style: StrokeStyle(lineWidth: lineWidth, lineCap: .butt))
                .rotationEffect(.degrees(-90))
        }
        .frame(width: size, height: size)
        .rotationEffect(.degrees(spinning && !reduceMotion ? 360 : 0))
        .animation(reduceMotion ? nil : .linear(duration: 0.7).repeatForever(autoreverses: false), value: spinning)
        .onAppear { spinning = !reduceMotion }
    }
}

// MARK: - Filter chip (Library)

struct FilterChip: View {
    let title: String
    let active: Bool
    let action: () -> Void
    @State private var hovering = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(Typo.font(12.5, 700))
                .foregroundColor(active ? Theme.creamInk : Theme.body)
                .padding(.horizontal, 14)
                .padding(.vertical, 7)
                .background(
                    Capsule().fill(active ? Theme.marigold : (hovering ? Theme.sagePale2 : .clear))
                )
                .overlay(
                    Capsule().stroke(active ? .clear : Theme.chipLine, lineWidth: 1.5)
                )
        }
        .buttonStyle(PressFeedbackStyle())
        .onHover { hovering = $0 }
        .animation(reduceMotion ? nil : Motion.feedback, value: active)
        .animation(reduceMotion ? nil : Motion.hover, value: hovering)
        .clickable()
        .accessibilityValue(active ? "Selected" : "")
    }
}

// MARK: - Scrubber (editor)

struct Scrubber: View {
    var fraction: Double
    var track: Color = Theme.creamLine
    var fill: Color = Theme.sage
    var onSeek: (Double) -> Void
    @State private var hovering = false
    @FocusState private var focused: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let trackHeight: CGFloat = 8
    private let knob: CGFloat = 16
    private let slop: CGFloat = 6

    var body: some View {
        GeometryReader { geo in
            let width = geo.size.width
            let clamped = max(0, min(1, fraction))

            ZStack(alignment: .leading) {
                Capsule().fill(track).frame(height: trackHeight)
                Capsule().fill(fill).frame(width: clamped * width, height: trackHeight)
                Circle()
                    .fill(Theme.marigold)
                    .overlay(Circle().stroke(Theme.cream, lineWidth: 2))
                    .frame(width: knob, height: knob)
                    .scaleEffect(hovering || focused ? 1.15 : 1)
                    .shadow(color: Theme.marigold.opacity(hovering || focused ? 0.25 : 0), radius: 4)
                    .offset(x: clamped * (width - knob))
            }
            .frame(height: knob, alignment: .center)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { v in seek(v.location.x, in: width) }
                    .onEnded { v in seek(v.location.x, in: width) }
            )
        }
        .frame(height: knob + slop * 2)
        .onHover { hovering = $0 }
        .focusable()
        .focused($focused)
        .onKeyPress(.leftArrow) {
            onSeek(max(0, fraction - 0.02))
            return .handled
        }
        .onKeyPress(.rightArrow) {
            onSeek(min(1, fraction + 0.02))
            return .handled
        }
        .accessibilityElement()
        .accessibilityLabel("Playback position")
        .accessibilityValue("\(Int(fraction * 100)) percent")
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: onSeek(min(1, fraction + 0.02))
            case .decrement: onSeek(max(0, fraction - 0.02))
            @unknown default: break
            }
        }
        .animation(reduceMotion ? nil : Motion.hover, value: hovering || focused)
        .clickable()
    }

    private func seek(_ x: CGFloat, in width: CGFloat) {
        guard width > knob else { return }
        onSeek(Double(max(0, min(1, (x - knob / 2) / (width - knob)))))
    }
}

// MARK: - Pointing-hand cursor

private struct ClickCursor: NSViewRepresentable {
    final class RectView: NSView {
        override func resetCursorRects() { addCursorRect(bounds, cursor: .pointingHand) }
        override func hitTest(_ point: NSPoint) -> NSView? { nil }
    }
    func makeNSView(context: Context) -> NSView { RectView() }
    func updateNSView(_ nsView: NSView, context: Context) { nsView.window?.invalidateCursorRects(for: nsView) }
}

extension View {
    func clickable() -> some View { overlay(ClickCursor()) }

    @ViewBuilder func clickable(if condition: Bool) -> some View {
        if condition { clickable() } else { self }
    }
}
