import SwiftUI

/// Reports the widget's intrinsic size so the hosting panel can hug the content.
struct WidgetSizeKey: PreferenceKey {
    static var defaultValue: CGSize = .zero
    static func reduce(value: inout CGSize, nextValue: () -> CGSize) { value = nextValue() }
}

/// The floating widget. At rest it's just the mic dot (Wispr-style); hovering expands it to
/// the labeled pill; recording swaps in a pill with **stop** and **cancel (✕)** buttons.
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
            pill
                .id(stateKey)
                .transition(.fRise)
                .simultaneousGesture(dragGesture)
        }
        .padding(shadowPad)
        .fixedSize()
        .animation(.easeOut(duration: 0.16), value: stateKey)
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

    private var stateKey: String {
        switch model.widgetState {
        case .idle: return "idle"
        case .recording: return "rec"
        case .transcribing: return "trans"
        case .queued: return "queued"
        case .error(let f): return "err-\(f)"
        }
    }

    @ViewBuilder private var pill: some View {
        switch model.widgetState {
        case .idle:          idlePill
        case .recording:     recordingPill
        case .transcribing:  transcribingPill
        case .queued:        queuedPill
        case .error(let f):  errorPill(f)
        }
    }

    private func pillRow(spacing: CGFloat, _ items: [AnyView]) -> some View {
        let ordered = anchorRight ? Array(items.reversed()) : items
        return HStack(spacing: spacing) {
            ForEach(Array(ordered.enumerated()), id: \.offset) { _, v in v }
        }
    }

    private func widgetShadow<V: View>(_ v: V) -> some View {
        v.shadow(color: Color(hex: 0x2A3129, alpha: 0.18), radius: 9, x: 0, y: 4)
    }

    // MARK: Idle (icon-only, expands on hover)

    private var idlePill: some View {
        let mic = AnyView(circle(Theme.sage, 24) { SolarIcon(name: Solar.mic, size: 13, color: Theme.card) })
        var items: [AnyView] = [mic]
        if hovering {
            items.append(AnyView(Text(model.trigger.widgetLabel).font(Typo.font(13, 700)).foregroundColor(Theme.sageDeep)))
            if model.trigger != .click {   // no keycap for click mode ("no keys")
                items.append(AnyView(Keycap(text: model.trigger.combo, fontSize: 11, hPad: 8, vPad: 3)))
            }
        }
        return widgetShadow(
            pillRow(spacing: 9, items)
                .padding(hovering
                         ? EdgeInsets(top: 8, leading: 12, bottom: 8, trailing: 12)
                         : EdgeInsets(top: 6, leading: 6, bottom: 6, trailing: 6))
                .background(Capsule().fill(Theme.card))
        )
        .contentShape(Capsule())
        .onHover { h in withAnimation(.easeOut(duration: 0.16)) { hovering = h } }
        .onTapGesture { if model.trigger != .hold { model.toggleRecording() } }
    }

    // MARK: Recording (stop + cancel)

    private var recordingPill: some View {
        let stop = AnyView(
            Button { model.stopRecording() } label: {
                ZStack {
                    Circle().fill(Theme.marigold).frame(width: 22, height: 22).pulsing(1.5)
                    SolarIcon(name: Solar.stop, size: 10, color: Theme.ink)
                }.frame(width: 22, height: 22)
            }.buttonStyle(.plain)
        )
        let label = AnyView(
            Text("Listening  \(Clip.formatSeconds(model.elapsed))")
                .font(Typo.font(12.5, 700))
                .monospacedDigit()
                .foregroundColor(Theme.marigold)
        )
        let cancel = AnyView(
            Button { model.cancelRecording() } label: {
                ZStack {
                    Circle().fill(Theme.barOnDark).frame(width: 22, height: 22)
                    Image(systemName: "xmark").font(.system(size: 10, weight: .bold))
                        .foregroundColor(Theme.inkMutedOnDark)
                }.frame(width: 22, height: 22)
            }.buttonStyle(.plain)
            .help("Discard — don't save or transcribe")
        )
        return widgetShadow(
            pillRow(spacing: 9, [stop, label, cancel])
                .padding(EdgeInsets(top: 8, leading: 10, bottom: 8, trailing: 10))
                .background(Capsule().fill(Theme.ink))
        )
        .contentShape(Capsule())
    }

    // MARK: Transcribing

    private var transcribingPill: some View {
        let dot = AnyView(circle(Theme.marigold, 24) { SolarIcon(name: Solar.textSquare, size: 13, color: Theme.card) }.pulsing(1.1))
        let label = AnyView(Text("Transcribing…").font(Typo.font(13, 700)).foregroundColor(Theme.sageDeep))
        return widgetShadow(
            pillRow(spacing: 9, [dot, label])
                .padding(EdgeInsets(top: 8, leading: 12, bottom: 8, trailing: 12))
                .background(Capsule().fill(Theme.card))
        )
    }

    // MARK: Queued

    private var queuedPill: some View {
        let dot = AnyView(circle(Theme.sagePale, 22) { SolarIcon(name: Solar.history, size: 12, color: Theme.sageDeep) })
        let label = AnyView(Text(TranscriptionFailure.network.message).font(Typo.font(12, 700)).foregroundColor(Theme.inkOnDark))
        return widgetShadow(
            pillRow(spacing: 9, [dot, label])
                .padding(EdgeInsets(top: 8, leading: 12, bottom: 8, trailing: 12))
                .background(Capsule().fill(Theme.ink))
        )
    }

    // MARK: Error

    private func errorPill(_ failure: TranscriptionFailure) -> some View {
        let dot = AnyView(circle(Theme.marigold, 22) { SolarIcon(name: Solar.danger, size: 12, color: Theme.ink) })
        var items: [AnyView] = [dot, AnyView(Text(failure.message).font(Typo.font(12, 700)).foregroundColor(Theme.inkOnDark))]
        if !failure.action.isEmpty {
            items.append(AnyView(Text(failure.action).font(Typo.font(12, 800)).foregroundColor(Theme.marigold)))
        }
        return widgetShadow(
            pillRow(spacing: 9, items)
                .padding(EdgeInsets(top: 8, leading: 12, bottom: 8, trailing: 12))
                .background(Capsule().fill(Theme.ink))
        )
        .contentShape(Capsule())
        .onTapGesture { model.handleWidgetErrorAction() }
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

    // MARK: Helper

    private func circle<Content: View>(_ color: Color, _ size: CGFloat,
                                       @ViewBuilder _ content: () -> Content) -> some View {
        ZStack {
            Circle().fill(color).frame(width: size, height: size)
            content()
        }
        .frame(width: size, height: size)
    }
}
