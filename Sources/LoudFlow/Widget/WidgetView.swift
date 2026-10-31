import SwiftUI

struct WidgetView: View {
    @ObservedObject var model: AppModel
    var anchorRight: Bool = true
    var onLayoutChanged: (() -> Void)? = nil
    var onDragChanged: ((CGSize) -> Void)? = nil
    var onDragEnded: (() -> Void)? = nil

    private let shadowPad: CGFloat = 14

    @State private var moved = false
    @State private var dragging = false
    @State private var hovering = false
    @State private var hoverOffTask: Task<Void, Never>?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            if anchorRight {
                if let toast = model.toast {
                    toastView(toast).transition(reduceMotion ? .opacity : .fSlideIn(fromTrailing: anchorRight))
                }
                pill.simultaneousGesture(dragGesture)
            } else {
                pill.simultaneousGesture(dragGesture)
                if let toast = model.toast {
                    toastView(toast).transition(reduceMotion ? .opacity : .fSlideIn(fromTrailing: anchorRight))
                }
            }
        }
        .padding(shadowPad)
        .fixedSize()
        .animation(reduceMotion ? nil : Motion.feedback, value: model.toast)
        .onChange(of: hovering) { _ in onLayoutChanged?() }
        .onChange(of: model.widgetState) { _ in onLayoutChanged?() }
        .onChange(of: model.toast) { _ in onLayoutChanged?() }
        .onChange(of: model.trigger) { _ in onLayoutChanged?() }
        .onChange(of: model.elapsed) { _ in onLayoutChanged?() }
    }

    private var dragGesture: some Gesture {
        DragGesture(minimumDistance: 6)
            .onChanged { g in
                if !dragging { dragging = true; hoverOffTask?.cancel() }
                moved = true
                onDragChanged?(g.translation)
            }
            .onEnded { _ in
                dragging = false
                if moved { moved = false; onDragEnded?() }
            }
    }

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
        .onHover(perform: setHovering)
        .onTapGesture(perform: tapped)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(label)
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { if tapDoesSomething { tapped() } }
        .clickable(if: tapDoesSomething)
        .animation(reduceMotion ? nil : .spring(response: 0.30, dampingFraction: 0.88), value: state)
        .animation(reduceMotion ? nil : .spring(response: 0.30, dampingFraction: 0.88), value: paddingKey)
        .animation(reduceMotion ? nil : .spring(response: 0.30, dampingFraction: 0.88), value: pillBackground)
    }

    private var tapDoesSomething: Bool {
        switch state {
        case .idle:            return model.trigger != .hold
        case .recording, .error: return true
        case .transcribing, .queued: return false
        }
    }

    private func setHovering(_ isHovering: Bool) {
        guard !dragging else { return }
        hoverOffTask?.cancel()
        if isHovering {
            hovering = true
        } else {
            // Delaying hover-off prevents the expanding pill from flickering under the pointer.
            hoverOffTask = Task {
                try? await Task.sleep(nanoseconds: 120_000_000)
                guard !Task.isCancelled else { return }
                hovering = false
            }
        }
    }

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
        if case .idle = state, hovering, model.trigger != .click {
            items.append(AnyView(Keycap(text: model.trigger.combo, fontSize: 11, hPad: 8, vPad: 3)))
        }
        if case .error(let failure) = state, !failure.action.isEmpty {
            items.append(AnyView(
                Text(failure.action).font(Typo.font(12, 800)).foregroundColor(Theme.marigold)
            ))
        }
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
        .modifier(DotPulse(duration: reduceMotion ? nil : pulseDuration))
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.22), value: dotSize)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.22), value: dotFill)
    }

    private var cancelButton: some View {
        Button { model.cancelRecording() } label: {
            ZStack {
                Circle().fill(Theme.barOnDark).frame(width: 22, height: 22)
                Image(systemName: "xmark").font(.system(size: 10, weight: .bold))
                    .foregroundColor(Theme.inkMutedOnDark)
            }
            .frame(width: 22, height: 22)
            .frame(width: 30, height: 30)
        }
        .buttonStyle(.plain)
        .clickable()
        .help("Discard — don't save or transcribe")
    }

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

    private func toastView(_ toast: Toast) -> some View {
        Text(toast.message)
            .font(Typo.font(12, 700))
            .foregroundColor(Theme.inkOnDark)
            .frame(maxWidth: 360)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 12).padding(.vertical, 8)
            .background(Capsule().fill(Theme.ink))
            .shadow(color: Color(hex: 0x2A3129, alpha: 0.18), radius: 9, x: 0, y: 4)
    }
}

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
