import SwiftUI

// MARK: - Waveform (fBar)

/// Staggered waveform bars. Matches the `fBar` keyframe: scaleY 0.16 ↔ 1 over 0.72s
/// ease-in-out infinite, each bar delayed by `stagger`. Purely decorative — the spec is
/// explicit that no live levels/words are shown while recording.
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

    var body: some View {
        HStack(spacing: gap) {
            ForEach(0..<count, id: \.self) { i in
                Capsule()
                    .fill(color)
                    .frame(maxWidth: .infinity)
                    .frame(height: height)
                    .scaleEffect(x: 1, y: animating ? 1 : minScale, anchor: .center)
                    .animation(
                        .easeInOut(duration: duration)
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

/// Bars driven by a live 0…1 level (the onboarding mic test). Center bars react most, so it
/// reads like a real meter responding to your voice.
struct LiveWaveBars: View {
    var level: Double
    var count: Int = 12
    var height: CGFloat = 30
    var gap: CGFloat = 3
    var color: Color = Theme.sage
    var minScale: CGFloat = 0.12

    var body: some View {
        HStack(spacing: gap) {
            ForEach(0..<count, id: \.self) { i in
                Capsule()
                    .fill(color)
                    .frame(maxWidth: .infinity)
                    .frame(height: height)
                    .scaleEffect(x: 1, y: barScale(i), anchor: .center)
                    .animation(.easeOut(duration: 0.09), value: level)
            }
        }
        .frame(height: height)
    }

    private func barScale(_ i: Int) -> CGFloat {
        let mid = Double(count - 1) / 2
        let dist = abs(Double(i) - mid) / mid          // 0 at center → 1 at edges
        let weight = 1.5 * (1 - dist * 0.6)            // center bars taller
        return max(minScale, min(1, CGFloat(level * weight)))
    }
}

// MARK: - Pulse (fPulse)

/// `fPulse`: scale 1 ↔ 1.18, opacity .8 ↔ 1. Recording dot uses 1.5s; transcribing badge 1.1s.
private struct Pulsing: ViewModifier {
    let duration: Double
    @State private var on = false
    func body(content: Content) -> some View {
        content
            .scaleEffect(on ? 1.18 : 1.0)
            .opacity(on ? 1.0 : 0.8)
            .animation(.easeInOut(duration: duration).repeatForever(autoreverses: true), value: on)
            .onAppear { on = true }
    }
}

extension View {
    func pulsing(_ duration: Double) -> some View { modifier(Pulsing(duration: duration)) }
}

// MARK: - fRise transition

extension AnyTransition {
    /// `fRise`: fade in + translateY(10 → 0). Pair with `.easeOut(duration: 0.18)`.
    static var fRise: AnyTransition {
        .asymmetric(
            insertion: .opacity.combined(with: .offset(y: 10)),
            removal: .opacity
        )
    }

    /// Fade in + translateX, sliding out from behind whatever it's docked against (the widget
    /// pill) rather than dropping in from above — for content that appears beside a fixed
    /// anchor instead of above or below it. `fromTrailing` says which side that anchor is on:
    /// true starts the slide from the trailing (right) side, false from the leading side.
    static func fSlideIn(fromTrailing: Bool) -> AnyTransition {
        .asymmetric(
            insertion: .opacity.combined(with: .offset(x: fromTrailing ? 10 : -10)),
            removal: .opacity
        )
    }
}

// MARK: - Keycap chip

/// A rounded keycap chip ("no keys", "⌥ Space", "⌃⌃"). Defaults match the sidebar/widget
/// pill style; override for the square-cornered variant used on settings/onboarding cards.
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

/// 42×24 toggle: track sage (on) / #DDE4DA (off), 18px white knob sliding left 3 ↔ 21px in 0.16s.
struct LFToggle: View {
    let isOn: Bool
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
        .animation(.easeInOut(duration: 0.16), value: isOn)
    }
}

// MARK: - Week/bar chart

struct ChartBar: Identifiable {
    let id = UUID()
    var fraction: Double            // 0…1 of the chart's height
    var color: Color
    var label: String? = nil
    var labelColor: Color = Theme.muted
    var labelWeight: CGFloat = 700
}

/// A simple bottom-anchored bar chart. Used both by the dark "Saved today" card
/// (no labels, 64pt) and the Receipts "Words per day" card (labels, 170pt).
struct WeekChart: View {
    var bars: [ChartBar]
    var chartHeight: CGFloat
    var gap: CGFloat
    var topRadius: CGFloat = Theme.Radius.bar

    var body: some View {
        HStack(alignment: .top, spacing: gap) {
            ForEach(bars) { b in
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
    }
}

// MARK: - Progress track (sidebar storage / player)

struct ProgressTrack: View {
    var fraction: Double            // 0…1
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

/// A 12px ring with one lit edge, turning once every 0.7s. Replaces the indeterminate
/// `ProgressView()` in a clip row, which read as a system control rather than as this app.
struct SpinRing: View {
    var size: CGFloat = 12
    var lineWidth: CGFloat = 2
    var track: Color = Theme.sagePale
    var lit: Color = Theme.sage

    @State private var spinning = false

    var body: some View {
        ZStack {
            Circle().stroke(track, lineWidth: lineWidth)
            // A quarter turn of colour, starting at the top — the CSS `border-top-color` look.
            Circle()
                .trim(from: 0, to: 0.25)
                .stroke(lit, style: StrokeStyle(lineWidth: lineWidth, lineCap: .butt))
                .rotationEffect(.degrees(-90))
        }
        .frame(width: size, height: size)
        .rotationEffect(.degrees(spinning ? 360 : 0))
        .animation(.linear(duration: 0.7).repeatForever(autoreverses: false), value: spinning)
        .onAppear { spinning = true }
    }
}

// MARK: - Filter chip (Library)

/// `All` · `Notes` · `Meetings`. Active is a marigold fill; inactive is an outline, so only one
/// chip ever carries the signal colour.
struct FilterChip: View {
    let title: String
    let active: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(Typo.font(12.5, 700))
                .foregroundColor(active ? Theme.creamInk : Theme.body)
                .padding(.horizontal, 14)
                .padding(.vertical, 7)
                .background(
                    Capsule().fill(active ? Theme.marigold : .clear)
                )
                .overlay(
                    Capsule().stroke(active ? .clear : Theme.chipLine, lineWidth: 1.5)
                )
        }
        .buttonStyle(.plain)
        .clickable()
    }
}

// MARK: - Scrubber (editor)

/// The editor's progress track, but draggable: a 16px marigold knob riding an 8px track, with
/// a 6px vertical hit-slop so it can be grabbed without precision. Click anywhere on the track
/// to jump there.
///
/// The position it shows belongs to the clip, not to the player — see `AppModel.progressByClip`.
struct Scrubber: View {
    var fraction: Double
    var track: Color = Theme.creamLine
    var fill: Color = Theme.sage
    var onSeek: (Double) -> Void

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
                    // Kept inside the track's ends so the knob never overhangs the card.
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
        .clickable()
    }

    private func seek(_ x: CGFloat, in width: CGFloat) {
        guard width > knob else { return }
        // The knob's travel is inset by its own width, so undo that to get the real position.
        onSeek(Double(max(0, min(1, (x - knob / 2) / (width - knob)))))
    }
}

// MARK: - Pointing-hand cursor

/// Pointing-hand cursor over a clickable region, applied as a cursor rect rather than
/// `NSCursor.push()/pop()` — push/pop unbalances the moment a hovered view disappears out from
/// under the mouse, which the morphing widget pill and hover-only pills do constantly. A cursor
/// rect can't drift like that: AppKit re-evaluates it itself.
private struct ClickCursor: NSViewRepresentable {
    final class RectView: NSView {
        override func resetCursorRects() { addCursorRect(bounds, cursor: .pointingHand) }
        // Never take the click or the hover — this view exists only to own a cursor rect.
        override func hitTest(_ point: NSPoint) -> NSView? { nil }
    }
    func makeNSView(context: Context) -> NSView { RectView() }
    func updateNSView(_ nsView: NSView, context: Context) { nsView.window?.invalidateCursorRects(for: nsView) }
}

extension View {
    /// Shows the pointing-hand cursor while hovering this view. Purely visual — it does not
    /// affect hit testing or add its own tap handling.
    func clickable() -> some View { overlay(ClickCursor()) }

    /// `clickable()`, but only when `condition` holds — for a view whose tap does nothing in
    /// some states (a turn block that seeks only while reading, not while editing).
    @ViewBuilder func clickable(if condition: Bool) -> some View {
        if condition { clickable() } else { self }
    }
}
