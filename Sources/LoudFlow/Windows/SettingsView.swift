import SwiftUI

struct SettingsView: View {
    @ObservedObject var model: AppModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Settings").textStyle(.pageTitle).foregroundColor(Theme.ink)
                Text("Set your preferences")
                    .textStyle(.subtitle).foregroundColor(Theme.body)
            }
            .padding(.horizontal, 4)
            .padding(.top, 4)

            nameCard
            triggerGrid
            toggleCard
            retentionCard
            speakersCard
            transcriptionCard
        }
    }

    private var nameCard: some View {
        HStack(spacing: 12) {
            Text("What should I call you?").font(Typo.font(14.5, 700)).foregroundColor(Theme.ink)
            Spacer()
            TextField(model.systemFirstName, text: $model.displayName)
                .textFieldStyle(.plain)
                .font(Typo.font(14, 600))
                .foregroundColor(Theme.ink)
                .multilineTextAlignment(.trailing)
                .frame(width: 170)
                .padding(.horizontal, 12).padding(.vertical, 9)
                .background(RoundedRectangle(cornerRadius: 12).fill(Theme.row))
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.hairline, lineWidth: 1))
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: Theme.Radius.cardSmall).fill(Theme.card))
        .themeShadow(Theme.Shadow.card)
    }

    private var triggerGrid: some View {
        HStack(spacing: 14) {
            ForEach(TriggerMode.allCases, id: \.self) { t in
                TriggerCard(mode: t, selected: model.trigger == t) { model.selectTrigger(t) }
                    .frame(maxWidth: .infinity)
            }
        }
    }

    private struct OptionRow { let title: String; let keyPath: WritableKeyPath<DictationOptions, Bool> }
    private let optionRows: [OptionRow] = [
        .init(title: "Type it into whatever field I'm in", keyPath: \.insert),
        .init(title: "Keep the audio", keyPath: \.keep),
    ]

    private var toggleCard: some View {
        VStack(spacing: 0) {
            ForEach(Array(optionRows.enumerated()), id: \.offset) { idx, row in
                Button { model.options[keyPath: row.keyPath].toggle() } label: {
                    HStack(spacing: 18) {
                        Text(row.title).font(Typo.font(14.5, 700)).foregroundColor(Theme.ink)
                        Spacer()
                        LFToggle(isOn: model.options[keyPath: row.keyPath])
                    }
                    .padding(.vertical, 15)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .clickable()
                .overlay(alignment: .bottom) {
                    if idx < optionRows.count - 1 {
                        Rectangle().fill(Theme.hairline2).frame(height: 1)
                    }
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 8)
        .background(RoundedRectangle(cornerRadius: Theme.Radius.cardSmall).fill(Theme.card))
        .themeShadow(Theme.Shadow.card)
    }

    private var retentionCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 9) {
                SolarIcon(name: Solar.history, size: 18, color: Theme.marigoldInk)
                Text("Keep recordings for").font(Typo.font(15, 800)).foregroundColor(Theme.creamInk)
            }
            HStack(spacing: 8) {
                ForEach(Retention.allCases, id: \.self) { r in
                    RetentionPill(label: r.label, selected: model.retention == r) { model.retention = r; model.sweepRetention() }
                }
            }
            Text(model.retention.settingsNote)
                .font(Typo.font(12.5, 400))
                .foregroundColor(Theme.marigoldInk)
                .lineSpacing(12.5 * 0.5)
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: Theme.Radius.cardSmall).fill(Theme.cream))
    }

    private var speakersCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 9) {
                SolarIcon(name: Solar.speakers, size: 18, color: Theme.marigoldInk)
                Text("Speakers").font(Typo.font(15, 800)).foregroundColor(Theme.creamInk)
            }
            Text("When a recording has more than one voice, LoudFlow labels each one. A voice you've named that turns up again is offered as a suggestion on the transcript, not applied on its own. Your own voice is learned from your solo recordings, so LoudFlow can point you out in a meeting too. Fixing a name from a transcript only changes that recording; renaming a voice here changes every recording it's in.")
                .font(Typo.font(12.5, 400))
                .foregroundColor(Theme.creamBody)
                .lineSpacing(12.5 * 0.45)
                .fixedSize(horizontal: false, vertical: true)

            if let note = recognizerNote {
                Text(note)
                    .font(Typo.font(12, 400))
                    .foregroundColor(Theme.creamMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }

            FlowLayout(spacing: 7) {
                ForEach(model.voices.listed) { voice in
                    VoicePill(model: model, voice: voice, renaming: $renamingVoice)
                }
            }
            .animation(reduceMotion ? nil : Motion.page,
                       value: model.voices.listed.map(\.settingsLabel))
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: Theme.Radius.cardSmall).fill(Theme.cream))
    }

    @State private var renamingVoice: Int?

    private var recognizerNote: String? {
        switch model.recognizer.readiness {
        case .preparing:
            return "Fetching the voice model…"
        case .unavailable:
            return "Couldn't fetch the voice model, so voices won't be recognised on their own yet. Naming one still works."
        case .idle, .ready:
            return "Matching voices runs on this Mac. The model it needs downloads once, the first time a recording has more than one voice or you name someone."
        }
    }

    private var transcriptionCard: some View { TranscriptionCard(model: model) }
}

// MARK: - Voice pill

private struct VoicePill: View {
    @ObservedObject var model: AppModel
    let voice: Voice
    @Binding var renaming: Int?

    @State private var draft = ""
    @State private var penHovering = false
    @State private var playHovering = false
    @State private var confirmingForget = false
    @FocusState private var focused: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var isRenaming: Bool { renaming == voice.id }
    private var isPlaying: Bool { model.playingVoiceId == voice.id }
    private var canPlay: Bool { voice.isNamed && model.voices.sampleURL(for: voice.id) != nil }

    var body: some View {
        HStack(spacing: 6) {
            playButton

            if isRenaming {
                nameField
            } else {
                Text(voice.settingsLabel)
                    .font(Typo.font(13, 700))
                    .foregroundColor(voice.isNamed ? Theme.creamInk : Theme.creamMuted)
                    .padding(.horizontal, 2)

                penButton
                if !voice.isYou && voice.isNamed {
                    if confirmingForget {
                        Button { model.forgetVoice(voice.id); confirmingForget = false } label: {
                            Text("Forget?")
                                .font(Typo.font(11.5, 800))
                                .foregroundColor(Theme.danger)
                        }
                        .buttonStyle(PressFeedbackStyle())
                        Button { withAnimation(reduceMotion ? nil : Motion.feedback) { confirmingForget = false } } label: {
                            Text("Cancel").font(Typo.font(11.5, 700)).foregroundColor(Theme.creamMuted)
                        }
                        .buttonStyle(PressFeedbackStyle())
                    } else {
                        Button { withAnimation(reduceMotion ? nil : Motion.feedback) { confirmingForget = true } } label: {
                            Text("Forget")
                                .font(Typo.font(11.5, 700))
                                .foregroundColor(Theme.creamMuted)
                                .padding(.horizontal, 5)
                        }
                        .buttonStyle(PressFeedbackStyle())
                        .clickable()
                        .help("Forget this voice")
                    }
                }
            }
        }
        .padding(5)
        .background(Capsule().fill(Theme.card))
        .overlay(Capsule().stroke(isRenaming ? Theme.marigold : Theme.creamLine2, lineWidth: 1.5))
        .onExitCommand { confirmingForget = false }
    }

    private var playButton: some View {
        Button { model.toggleVoiceSample(voice.id) } label: {
            ZStack {
                Circle().fill(isPlaying ? Theme.marigold
                              : (playHovering && canPlay ? Theme.marigold : Theme.sagePale))
                SolarIcon(name: isPlaying ? Solar.pause : Solar.play, size: 10,
                          color: isPlaying ? Theme.creamInk : Theme.sageDeep)
            }
            .frame(width: 20, height: 20)
            .frame(width: 28, height: 28)
        }
        .buttonStyle(PressFeedbackStyle())
        .clickable(if: canPlay)
        .disabled(!canPlay)
        .onHover { playHovering = $0 }
        .animation(reduceMotion ? nil : Motion.hover, value: playHovering)
        .help(canPlay ? "Hear \(voice.name ?? "")" : "Name this voice to keep a sample")
    }

    private var penButton: some View {
        Button {
            draft = voice.name ?? ""
            renaming = voice.id
            focused = true
        } label: {
            ZStack {
                Circle().fill(penHovering ? Theme.marigold : Theme.creamChip)
                SolarIcon(name: Solar.pen, size: 10, color: Theme.marigoldInk)
            }
            .frame(width: 20, height: 20)
            .frame(width: 28, height: 28)
        }
        .buttonStyle(PressFeedbackStyle())
        .clickable()
        .onHover { penHovering = $0 }
        .animation(reduceMotion ? nil : Motion.hover, value: penHovering)
        .help(voice.isNamed ? "Rename this voice" : "Name this voice")
    }

    private var nameField: some View {
        TextField("Type a name", text: $draft)
            .textFieldStyle(.plain)
            .font(Typo.font(13, 700))
            .foregroundColor(Theme.creamInk)
            .focused($focused)
            .frame(width: 110)
            .padding(.horizontal, 9).padding(.vertical, 2)
            .background(Capsule().fill(Theme.marigoldPale))
            .overlay(Capsule().stroke(Theme.marigold, lineWidth: 1.5))
            .onSubmit {
                let name = draft.trimmingCharacters(in: .whitespaces)
                renaming = nil
                guard !name.isEmpty else { return }
                if voice.isYou {
                    model.displayName = name
                } else {
                    model.renameVoice(voice.id, to: name, from: nil)
                }
            }
            .onExitCommand { renaming = nil }
            .onAppear { focused = true }
    }
}

private struct FlowLayout: Layout {
    var spacing: CGFloat = 7

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let offered = proposal.width ?? .infinity
        let rows = layout(subviews, in: offered)
        let height = rows.last.map { $0.y + $0.height } ?? 0
        let natural = rows.map(\.width).max() ?? 0
        // SwiftUI can propose an unbounded width; report the content width in that case.
        return CGSize(width: offered.isFinite ? offered : natural, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        for row in layout(subviews, in: bounds.width) {
            var x = bounds.minX
            for index in row.indices {
                let size = subviews[index].sizeThatFits(.unspecified)
                subviews[index].place(at: CGPoint(x: x, y: bounds.minY + row.y),
                                      proposal: ProposedViewSize(size))
                x += size.width + spacing
            }
        }
    }

    private struct Row { var indices: [Int] = []; var y: CGFloat = 0; var height: CGFloat = 0; var width: CGFloat = 0 }

    private func layout(_ subviews: Subviews, in proposedWidth: CGFloat) -> [Row] {
        let width = proposedWidth.isFinite ? proposedWidth : .greatestFiniteMagnitude
        var rows: [Row] = []
        var row = Row()
        var x: CGFloat = 0
        var y: CGFloat = 0

        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(.unspecified)
            if x > 0, x + size.width > width {
                row.y = y; row.width = x - spacing
                rows.append(row)
                y += row.height + spacing
                row = Row(); x = 0
            }
            row.indices.append(index)
            row.height = max(row.height, size.height)
            x += size.width + spacing
        }
        if !row.indices.isEmpty {
            row.y = y; row.width = max(0, x - spacing)
            rows.append(row)
        }
        return rows
    }
}

// MARK: - Trigger card

private struct TriggerCard: View {
    let mode: TriggerMode
    let selected: Bool
    let action: () -> Void
    @State private var hovering = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Button(action: action) {
            HStack(spacing: 9) {
                SolarIcon(name: mode.iconName, size: 19, color: Theme.sage)
                Text(mode.name).font(Typo.font(14.5, 800)).foregroundColor(Theme.ink)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 8)
                Keycap(text: mode.combo, fg: Theme.body, bg: Theme.sagePale2, radius: Theme.Radius.keycap)
            }
            .padding(EdgeInsets(top: 16, leading: 17, bottom: 16, trailing: 17))
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: Theme.Radius.block)
                .fill(hovering && !selected ? Theme.sagePale2 : Theme.card))
            .overlay(
                RoundedRectangle(cornerRadius: Theme.Radius.block)
                    .stroke(selected ? Theme.marigold : Theme.hairline, lineWidth: 2)
            )
        }
        .buttonStyle(PressFeedbackStyle())
        .onHover { hovering = $0 }
        .animation(reduceMotion ? nil : Motion.feedback, value: selected)
        .animation(reduceMotion ? nil : Motion.hover, value: hovering)
        .clickable()
        .accessibilityValue(selected ? "Selected" : "")
    }
}

// MARK: - Retention pill

private struct RetentionPill: View {
    let label: String
    let selected: Bool
    let action: () -> Void
    @State private var hovering = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        Button(action: action) {
            Text(label)
                .font(Typo.font(13, 700))
                .foregroundColor(selected ? Theme.creamInk : Theme.creamBody)
                .padding(.horizontal, 16).padding(.vertical, 9)
                .background(Capsule().fill(selected ? Theme.marigold : (hovering ? Theme.creamChip : .clear)))
                .overlay(Capsule().stroke(selected ? Theme.marigold : Theme.creamLine, lineWidth: 1.5))
        }
        .buttonStyle(PressFeedbackStyle())
        .onHover { hovering = $0 }
        .animation(reduceMotion ? nil : Motion.feedback, value: selected)
        .animation(reduceMotion ? nil : Motion.hover, value: hovering)
        .clickable()
        .accessibilityValue(selected ? "Selected" : "")
    }
}
