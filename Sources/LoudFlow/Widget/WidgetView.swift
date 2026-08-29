import SwiftUI

/// Reports the widget's intrinsic size so the hosting panel can hug the content.
struct WidgetSizeKey: PreferenceKey {
    static var defaultValue: CGSize = .zero
    static func reduce(value: inout CGSize, nextValue: () -> CGSize) { value = nextValue() }
}

/// The floating widget: **one pill that morphs**, not five pills that swap.
///
/// Background and padding animate over 0.22s, the leading dot animates its fill and its size,
/// and only the labels change. Nothing translates vertically — the `fRise` entrance belongs to
/// the toast and the onboarding modal, not to a state the widget is already showing.
///
/// Everything anchors to the screen edge it lives near (`anchorRight`) so content unfurls
/// *inward*. Drag (past a small threshold) moves it; a plain tap records.
struct WidgetView: View {
    @ObservedObject var model: AppModel
    var anchorRight: Bool = true
    var onResize: ((CGSize) -> Void)? = nil
    var onDragChanged: ((CGSize) -> Void)? = nil
    var onDragEnded: (() -> Void)? = nil

    private let shadowPad: CGFloat = 14   // transparent margin so the shadow never clips

    @State private var moved = false
    @State private var hovering = false

    var body: some View {
        VStack(alignment: anchorRight ? .trailing : .leading, spacing: 8) {
            if let toast = model.toast {
                toastView(toast).transition(.fRise)
            }
            pill.simultaneousGesture(dragGesture)
        }
        .padding(shadowPad)
        .fixedSize()
        .animation(.easeOut(duration: 0.16), value: model.toast)
        .background(
            GeometryReader { proxy in
                Color.clear.preference(key: WidgetSizeKey.self, value: proxy.size)
            }
        )
        .onPreferenceChange(WidgetSizeKey.self) { onResize?($0) }
    }

    // Drag moves the widget; buttons/taps still fire because the drag needs >6pt of movement.
    private var dragGesture: some Gesture {
        DragGesture(minimumDistance: 6)
            .onChanged { g in moved = true; onDragChanged?(g.translation) }
            .onEnded { _ in if moved { moved = false; onDragEnded?() } }
    }

    // MARK: - The one pill

    private var state: WidgetState { model.widgetState }

    private var pill: some View {
        let items = contents
        let ordered = anchorRight ? Array(items.reversed()) : items

        return HStack(spacing: 9) {
            ForEach(Array(ordered.enumerated()), id: \.offset) { _, v in v }
        }
        .padding(padding)
        .background(Capsule().fill(pillBackground))
        .shadow(color: Color(hex: 0x2A3129, alpha: 0.18), radius: 9, x: 0, y: 4)
        .contentShape(Capsule())
        .onHover { hovering = $0 }
        .onTapGesture(perform: tapped)
        .animation(.easeInOut(duration: 0.22), value: paddingKey)
        .animation(.easeInOut(duration: 0.22), value: pillBackground)
    }

    /// Idle starts (unless the trigger is hold — then the key does it), recording stops, an
    /// error opens Settings. Everything else is inert.
    private func tapped() {
        switch state {
        case .idle:       if model.trigger != .hold { model.toggleRecording() }
        case .recording:  model.stopRecording()
        case .error:      model.handleWidgetErrorAction()
        default:          break
        }
    }

    private var contents: [AnyView] {
        var items: [AnyView] = [AnyView(dot)]

        if showsLabel {
            items.append(AnyView(
                Text(label)
                    .font(Typo.font(labelSize, 700))
                    .monospacedDigit()
                    .foregroundColor(labelInk)
                    .fixedSize()
            ))
        }
        // The keycap is an idle-only hint, and only when there is a key to press.
        if case .idle = state, hovering, model.trigger != .click {
            items.append(AnyView(Keycap(text: model.trigger.combo, fontSize: 11, hPad: 8, vPad: 3)))
        }
        if case .error(let failure) = state, !failure.action.isEmpty {
            items.append(AnyView(
                Text(failure.action).font(Typo.font(12, 800)).foregroundColor(Theme.marigold)
            ))
        }
        // Discard is only ever offered while something is being recorded.
        if case .recording = state {
            items.append(AnyView(cancelButton))
        }
        return items
    }

    private var dot: some View {
        ZStack {
            Circle().fill(dotFill)
            SolarIcon(name: dotIcon, size: dotIconSize, color: dotInk)
        }
        .frame(width: dotSize, height: dotSize)
        .modifier(DotPulse(duration: pulseDuration))
        .animation(.easeInOut(duration: 0.22), value: dotSize)
        .animation(.easeInOut(duration: 0.22), value: dotFill)
    }

    private var cancelButton: some View {
        Button { model.cancelRecording() } label: {
            ZStack {
                Circle().fill(Theme.barOnDark).frame(width: 22, height: 22)
                Image(systemName: "xmark").font(.system(size: 10, weight: .bold))
                    .foregroundColor(Theme.inkMutedOnDark)
            }
            .frame(width: 22, height: 22)
        }
        .buttonStyle(.plain)
        .help("Discard — don't save or transcribe")
    }

    // MARK: Per-state values

    private var pillBackground: Color {
        switch state {
        case .idle, .transcribing: return Theme.card
        default:                   return Theme.ink
        }
    }

    private var padding: EdgeInsets {
        switch state {
        case .idle:
            return hovering
                ? EdgeInsets(top: 8, leading: 12, bottom: 8, trailing: 12)
                : EdgeInsets(top: 6, leading: 6, bottom: 6, trailing: 6)
        case .recording:
            return EdgeInsets(top: 8, leading: 10, bottom: 8, trailing: 10)
        default:
            return EdgeInsets(top: 8, leading: 12, bottom: 8, trailing: 12)
        }
    }

    /// `EdgeInsets` isn't `Equatable`, so animate on a stand-in that is.
    private var paddingKey: String {
        "\(padding.top)-\(padding.leading)"
    }

    private var dotSize: CGFloat {
        switch state {
        case .recording, .queued, .error: return 22
        case .idle, .transcribing:        return 24
        }
    }

    private var dotIconSize: CGFloat {
        switch state {
        case .recording:         return 10
        case .queued, .error:    return 12
        case .idle, .transcribing: return 13
        }
    }

    private var dotFill: Color {
        switch state {
        case .idle:   return Theme.sage
        case .queued: return Theme.sagePale
        default:      return Theme.marigold
        }
    }

    private var dotInk: Color {
        switch state {
        case .idle, .transcribing: return Theme.card
        case .queued:              return Theme.sageDeep
        default:                   return Theme.ink
        }
    }

    private var dotIcon: String {
        switch state {
        case .idle:          return Solar.mic
        case .recording:     return Solar.stop
        case .transcribing:  return Solar.textSquare
        case .queued:        return Solar.history
        case .error:         return Solar.danger
        }
    }

    private var pulseDuration: Double? {
        switch state {
        case .recording:    return 1.5
        case .transcribing: return 1.1
        default:            return nil
        }
    }

    /// Idle says nothing until you hover it; every other state has something to report.
    private var showsLabel: Bool {
        if case .idle = state { return hovering }
        return true
    }

    private var label: String {
        switch state {
        case .idle:          return model.trigger.widgetLabel
        case .recording:     return "Listening  \(Clip.formatSeconds(model.elapsed))"
        case .transcribing:  return "Transcribing…"
        case .queued:        return TranscriptionFailure.network.message
        case .error(let f):  return f.message
        }
    }

    private var labelSize: CGFloat {
        switch state {
        case .idle, .transcribing: return 13
        default:                   return 12.5
        }
    }

    private var labelInk: Color {
        switch state {
        case .idle, .transcribing: return Theme.sageDeep
        case .recording:           return Theme.marigold
        default:                   return Theme.inkOnDark
        }
    }

    // MARK: Toast

    private func toastView(_ toast: Toast) -> some View {
        HStack(spacing: 10) {
            Text(toast.message).font(Typo.font(12, 700)).foregroundColor(Theme.inkOnDark)
            if !toast.action.isEmpty {
                Text(toast.action).font(Typo.font(12, 700)).foregroundColor(Theme.marigold)
                    .onTapGesture { if toast.kind == .fixLast { model.fixLast() } }
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
        .background(Capsule().fill(Theme.ink))
        .shadow(color: Color(hex: 0x2A3129, alpha: 0.18), radius: 9, x: 0, y: 4)
    }
}

/// `fPulse` applied only in the states that call for it. Keyed on the duration so the animation
/// restarts cleanly when the widget morphs from recording into transcribing.
private struct DotPulse: ViewModifier {
    let duration: Double?

    func body(content: Content) -> some View {
        if let duration {
            content.pulsing(duration).id(duration)
        } else {
            content
        }
    }
}
