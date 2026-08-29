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
    /// When there are voices you have already named, the pen offers them as a pick list first —
    /// re-linking someone the recogniser wasn't sure about is one click rather than retyping a
    /// name you have typed before.
    private var renamePen: some View {
        PenButton(visible: hovering && turn.speaker != Voice.youID,
                  candidates: candidates,
                  pick: { model.renameVoice(turn.speaker, to: $0, from: clip) },
                  type: {
                      draft = voice?.name ?? ""
                      renamingVoice = turn.speaker
                      nameFocused = true
                  })
    }

    /// Voices worth offering: named, not you, and not already speaking in this clip — the same
    /// person can't be two speakers in one conversation.
    private var candidates: [String] {
        let present = Set(clip.speakerIds)
        return model.voices.listed
            .filter { $0.isNamed && !$0.isYou && !present.contains($0.id) }
            .compactMap(\.name)
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
            .onExitCommand { renamingVoice = nil }        // Escape cancels
            .onAppear { nameFocused = true }
    }

    /// Naming a voice saves the profile and updates every turn by that speaker at once.
    /// An empty field keeps the old name rather than clearing it.
    private func commitName() {
        defer { renamingVoice = nil }
        let name = draft.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        model.renameVoice(turn.speaker, to: name, from: clip)
    }

    // MARK: Turn text

    @ViewBuilder private var body_text: some View {
        if editing {
            TextField("", text: $text, axis: .vertical)
                .textFieldStyle(.plain)
                .font(Typo.font(16, 400))
                .lineSpacing(16 * 0.55)
                .foregroundColor(Theme.creamInk)
                .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            Text(turn.text)
                .font(Typo.font(16, 400))
                .lineSpacing(16 * 0.55)
                .foregroundColor(Theme.creamInk)
                .frame(maxWidth: .infinity, alignment: .leading)
                .textSelection(.enabled)
        }
    }
}

/// The rename affordance: an 11pt pen in a 20pt circle, marigold-pale at rest, marigold on
/// hover. Kept in the layout even when invisible so the header never reflows.
///
/// With no names to pick from it is a plain button straight into the text field. With names, it
/// is a menu of them — because the common case is meeting someone you have already labelled.
private struct PenButton: View {
    let visible: Bool
    let candidates: [String]
    let pick: (String) -> Void
    let type: () -> Void

    @State private var hovering = false

    var body: some View {
        Group {
            if candidates.isEmpty {
                Button(action: type) { pen }.buttonStyle(.plain)
            } else {
                Menu {
                    ForEach(candidates, id: \.self) { name in
                        Button(name) { pick(name) }
                    }
                    Divider()
                    Button("Type a name…", action: type)
                } label: {
                    pen
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .frame(width: 20, height: 20)
            }
        }
        .onHover { hovering = $0 }
        .opacity(visible ? 1 : 0)
        .allowsHitTesting(visible)
        .animation(.easeInOut(duration: 0.12), value: visible)
        .help(candidates.isEmpty ? "Name this voice" : "Name this voice, or pick one you know")
    }

    private var pen: some View {
        ZStack {
            Circle().fill(hovering ? Theme.marigold : Theme.marigoldPale)
            SolarIcon(name: Solar.pen, size: 11, color: Theme.marigoldInk)
        }
        .frame(width: 20, height: 20)
    }
}
