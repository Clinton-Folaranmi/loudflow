import SwiftUI

/// One speaker's turn in a conversation transcript.
///
/// A conversation is read by default, so a block is a **seek target**: clicking it jumps the
/// audio to that moment and plays. Only when the editor is put into edit mode does the text
/// become a field. The speaker name and the timestamp are never editable in either mode —
/// they belong to the audio.
///
/// The header row is a fixed 20pt tall so nothing reflows when the rename pen appears on hover.
struct TurnBlockView: View {
    @ObservedObject var model: AppModel
    let clip: Clip
    let index: Int
    let turn: Turn
    let editing: Bool
    let active: Bool
    @Binding var text: String

    /// Which voice is being renamed right now, hoisted so only one field is ever open.
    @Binding var renamingVoice: Int?

    @State private var hovering = false
    @State private var draft = ""
    @FocusState private var nameFocused: Bool

    private var voice: Voice? { model.voices.voice(turn.speaker) }
    private var ink: Color { voice?.ink ?? Theme.creamInk }
    private var label: String { clip.speakerLabel(turn.speaker, voices: model.voices.voices) }
    private var isRenaming: Bool { renamingVoice == turn.speaker }

    /// Hover and playback share one fill — no stroke, no second treatment.
    private var fill: Color { (active || hovering) ? Theme.creamChip : .clear }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            header
            if isFirstOccurrence, let suggested = suggestedVoice, let name = suggested.name {
                SuggestionChip(
                    name: name,
                    accept: { model.acceptSuggestion(for: turn.speaker, in: clip.id) },
                    reject: { model.rejectSuggestion(for: turn.speaker, in: clip.id) }
                )
            }
            body_text
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(RoundedRectangle(cornerRadius: 10).fill(fill))
        .contentShape(RoundedRectangle(cornerRadius: 10))
        .onHover { hovering = $0 }
        .onTapGesture {
            // Reading seeks; editing lets the field take the click and place the caret.
            guard !editing else { return }
            model.playTurn(clip, at: turn.at)
        }
        .clickable(if: !editing)
    }

    // MARK: Header — name · pen · … · timestamp

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

    /// 20pt circle, marigold-pale at rest and marigold on hover, shown only while the block is
    /// hovered so a still transcript stays quiet.
    ///
    /// Fixing a speaker here only ever touches this one recording — see `AppModel`'s per-clip
    /// correction API. The menu offers, in order: voices you've already named (re-linking
    /// someone the recogniser wasn't sure about is one click), **You** when this clip doesn't
    /// have a You speaker yet (a mono clip's local 0 isn't pinned to you — see
    /// `applyTranscript` — so this is how you claim it), typing a new name, and — only once
    /// this speaker already carries someone else's identity — undoing that.
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

    /// Voices worth offering as a reassignment target: named, not you, and not already
    /// speaking in this clip — the same person can't be two speakers in one conversation.
    ///
    /// Empty for You's own turn on a two-track clip: the mic/system split already guarantees
    /// local 0 is you there (see `applyTranscript`), so reassigning it isn't a correction — and
    /// doing it anyway would misroute `VoiceRecognizer`, which decides which channel to sample
    /// by checking `speaker == Voice.youID`, not by remembering where each turn's audio
    /// actually lives. On a mono clip there's only one channel, so no such risk — that's
    /// exactly the case a wrongly-assigned You needs to be fixable in.
    private var candidates: [PenButton.Candidate] {
        guard turn.speaker != Voice.youID || !clip.twoTrack else { return [] }
        let present = Set(clip.speakerIds)
        return model.voices.listed
            .filter { $0.isNamed && !$0.isYou && !present.contains($0.id) }
            .compactMap { v in v.name.map { PenButton.Candidate(id: v.id, name: $0) } }
    }

    // MARK: Recognizer suggestion

    private var suggestedVoice: Voice? {
        model.suggestions[clip.id]?[turn.speaker].flatMap { model.voices.voice($0) }
    }

    /// Only the first turn this speaker takes shows the chip, so a long transcript doesn't
    /// repeat the same suggestion on every one of their turns.
    private var isFirstOccurrence: Bool {
        guard let turns = clip.turns else { return false }
        return turns.firstIndex(where: { $0.speaker == turn.speaker }) == index
    }

    // MARK: Inline rename field

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
            .onExitCommand { renamingVoice = nil }        // Escape cancels
            .onAppear { nameFocused = true }
    }

    /// Names this speaker. For You, that's `displayName` (see its doc comment on `AppModel`) —
    /// everyone else goes through `nameSpeaker`, which only ever touches this recording unless
    /// the voice it names isn't shared with any other clip. An empty field keeps the old name
    /// rather than clearing it.
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

    // MARK: Turn text

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
                .textSelection(.enabled)
        }
    }
}

/// The rename affordance: an 11pt pen in a 20pt circle, marigold-pale at rest, marigold on
/// hover. Kept in the layout even when invisible so the header never reflows.
///
/// A plain button straight into the text field when there's nothing else to offer; a menu of
/// named voices, an optional **You**, typing a name, and an optional **Not this person**
/// otherwise — the common case (meeting someone brand new, nothing to pick from) stays a single
/// click instead of opening a menu with one item in it.
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
        .opacity(visible ? 1 : 0)
        .allowsHitTesting(visible)
        .animation(.easeInOut(duration: 0.12), value: visible)
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

/// A recogniser match offered, not applied — "Looks like Ada", with a one-click confirm and
/// dismiss. Accepting reassigns just this clip's speaker (`AppModel.acceptSuggestion`);
/// dismissing just makes the chip go away, this session (`AppModel.rejectSuggestion`).
private struct SuggestionChip: View {
    let name: String
    let accept: () -> Void
    let reject: () -> Void

    var body: some View {
        HStack(spacing: 7) {
            Text("Looks like \(name)")
                .font(Typo.font(11.5, 700))
                .foregroundColor(Theme.marigoldInk)

            Button(action: accept) {
                SolarIcon(name: Solar.check, size: 13, color: Theme.marigoldInk)
            }
            .buttonStyle(.plain)
            .clickable()
            .help("Yes, that's \(name)")

            Button(action: reject) {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundColor(Theme.marigoldInk)
            }
            .buttonStyle(.plain)
            .clickable()
            .help("Not \(name)")
        }
        .padding(.horizontal, 9).padding(.vertical, 4)
        .background(Capsule().fill(Theme.marigoldPale))
    }
}
