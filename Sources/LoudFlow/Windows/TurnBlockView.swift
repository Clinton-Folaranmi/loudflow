import SwiftUI

struct TurnBlockView: View {
    @ObservedObject var model: AppModel
    let clip: Clip
    let index: Int
    let turn: Turn
    let editing: Bool
    let active: Bool
    @Binding var text: String

    @Binding var renamingVoice: Int?

    @State private var hovering = false
    @State private var draft = ""
    @FocusState private var nameFocused: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var voice: Voice? { model.voices.voice(turn.speaker) }
    private var ink: Color { voice?.ink ?? Theme.creamInk }
    private var label: String { clip.speakerLabel(turn.speaker, voices: model.voices.voices) }
    private var isRenaming: Bool { renamingVoice == turn.speaker }

    private var fill: Color { active ? Theme.creamChip : (hovering ? Theme.creamLine2 : .clear) }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            header
            if isFirstOccurrence, let suggested = suggestedVoice, let name = suggested.name {
                SuggestionChip(
                    name: name,
                    accept: { model.acceptSuggestion(for: turn.speaker, in: clip.id) },
                    reject: { model.rejectSuggestion(for: turn.speaker, in: clip.id) }
                )
                .transition(.opacity.combined(with: .scale(scale: 0.97)))
            }
            body_text
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(RoundedRectangle(cornerRadius: 10).fill(fill))
        .contentShape(RoundedRectangle(cornerRadius: 10))
        .onHover { hovering = $0 }
        .onTapGesture {
            guard !editing else { return }
            model.playTurn(clip, at: turn.at)
        }
        .focusable(!editing)
        .onKeyPress(.return) {
            guard !editing else { return .ignored }
            model.playTurn(clip, at: turn.at)
            return .handled
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(label), \(Clip.formatSeconds(Int(turn.at))), \(turn.text)")
        .accessibilityHint(editing ? "Editing transcript" : "Play from this turn")
        .accessibilityAction {
            if !editing { model.playTurn(clip, at: turn.at) }
        }
        .animation(reduceMotion ? nil : Motion.feedback, value: active)
        .animation(reduceMotion ? nil : Motion.hover, value: hovering)
        .clickable(if: !editing)
    }

    private var header: some View {
        HStack(spacing: 7) {
            if isRenaming {
                nameField
            } else {
                Text(label)
                    .font(Typo.font(12.5, 800))
                    .foregroundColor(ink)
                renamePen
            }

            Spacer(minLength: 8)

            Text(Clip.formatSeconds(Int(turn.at)))
                .font(Typo.font(11.5, 700))
                .monospacedDigit()
                .foregroundColor(Theme.creamMuted)
        }
        .frame(height: 20)
    }

    private var renamePen: some View {
        PenButton(
            visible: hovering,
            candidates: candidates,
            showsYou: turn.speaker != Voice.youID && !clip.speakerIds.contains(Voice.youID),
            canDetach: turn.speaker != Voice.youID && (voice?.isNamed ?? false),
            onPick: { target in model.reassignSpeaker(turn.speaker, in: clip.id, to: target) },
            onNotThisPerson: { model.detachSpeaker(turn.speaker, in: clip.id) },
            onTypeAName: {
                draft = voice?.name ?? ""
                renamingVoice = turn.speaker
                nameFocused = true
            }
        )
    }

    private var candidates: [PenButton.Candidate] {

        guard turn.speaker != Voice.youID || !clip.twoTrack else { return [] }
        let present = Set(clip.speakerIds)
        return model.voices.listed
            .filter { $0.isNamed && !$0.isYou && !present.contains($0.id) }
            .compactMap { v in v.name.map { PenButton.Candidate(id: v.id, name: $0) } }
    }

    private var suggestedVoice: Voice? {
        model.suggestions[clip.id]?[turn.speaker].flatMap { model.voices.voice($0) }
    }

    private var isFirstOccurrence: Bool {
        guard let turns = clip.turns else { return false }
        return turns.firstIndex(where: { $0.speaker == turn.speaker }) == index
    }

    private var nameField: some View {
        TextField("", text: $draft)
            .textFieldStyle(.plain)
            .font(Typo.font(12.5, 800))
            .foregroundColor(ink)
            .focused($nameFocused)
            .frame(width: 130)
            .padding(.horizontal, 7)
            .padding(.vertical, 2)
            .background(RoundedRectangle(cornerRadius: 6).fill(Theme.marigoldPale))
            .overlay(RoundedRectangle(cornerRadius: 6).stroke(Theme.marigold, lineWidth: 1.5))
            .onSubmit(commitName)
            .onExitCommand { renamingVoice = nil }
            .onAppear { nameFocused = true }
    }

    private func commitName() {
        defer { renamingVoice = nil }
        let name = draft.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        if turn.speaker == Voice.youID {
            model.displayName = name
        } else {
            model.nameSpeaker(turn.speaker, in: clip.id, to: name)
        }
    }

    @ViewBuilder private var body_text: some View {
        if editing {
            TextField("", text: $text, axis: .vertical)
                .textFieldStyle(.plain)
                .font(Typo.font(14, 400))
                .lineSpacing(14 * 0.55)
                .foregroundColor(Theme.creamInk)
                .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            Text(turn.text)
                .font(Typo.font(14, 400))
                .lineSpacing(14 * 0.55)
                .foregroundColor(Theme.creamInk)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

private struct PenButton: View {
    struct Candidate: Identifiable { let id: Int; let name: String }

    let visible: Bool
    let candidates: [Candidate]
    let showsYou: Bool
    let canDetach: Bool
    let onPick: (Int) -> Void
    let onNotThisPerson: () -> Void
    let onTypeAName: () -> Void

    @State private var hovering = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var hasMenu: Bool { !candidates.isEmpty || showsYou || canDetach }

    var body: some View {
        Group {
            if !hasMenu {
                Button(action: onTypeAName) { pen }.buttonStyle(.plain).clickable()
            } else {
                Menu {
                    ForEach(candidates) { c in
                        Button(c.name) { onPick(c.id) }
                    }
                    if showsYou {
                        Button("You") { onPick(Voice.youID) }
                    }
                    Divider()
                    Button("Type a name…", action: onTypeAName)
                    if canDetach {
                        Button("Not this person", action: onNotThisPerson)
                    }
                } label: {
                    pen
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .frame(width: 20, height: 20)
                .clickable()
            }
        }
        .onHover { hovering = $0 }
        .opacity(visible ? 1 : 0.55)
        .animation(reduceMotion ? nil : Motion.hover, value: visible)
        .help(hasMenu ? "Name this voice, or pick one you know" : "Name this voice")
    }

    private var pen: some View {
        ZStack {
            Circle().fill(hovering ? Theme.marigold : Theme.marigoldPale)
            SolarIcon(name: Solar.pen, size: 11, color: Theme.marigoldInk)
        }
        .frame(width: 20, height: 20)
    }
}

private struct SuggestionChip: View {
    let name: String
    let accept: () -> Void
    let reject: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 7) {
            Text("Looks like \(name)")
                .font(Typo.font(11.5, 700))
                .foregroundColor(Theme.marigoldInk)

            Button { withAnimation(reduceMotion ? nil : Motion.feedback) { accept() } } label: {
                SolarIcon(name: Solar.check, size: 13, color: Theme.marigoldInk)
                    .frame(width: 26, height: 26)
            }
            .buttonStyle(.plain)
            .clickable()
            .help("Yes, that's \(name)")

            Button { withAnimation(reduceMotion ? nil : Motion.feedback) { reject() } } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundColor(Theme.marigoldInk)
                    .frame(width: 26, height: 26)
            }
            .buttonStyle(.plain)
            .clickable()
            .help("Not \(name)")
        }
        .padding(.horizontal, 9).padding(.vertical, 4)
        .background(Capsule().fill(Theme.marigoldPale))
    }
}
