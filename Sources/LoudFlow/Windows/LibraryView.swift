import SwiftUI

struct LibraryView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Library").textStyle(.pageTitle).foregroundColor(Theme.ink)
                Text("\(model.clips.count) recordings").textStyle(.subtitle).foregroundColor(Theme.body)
            }
            .padding(.horizontal, 4)
            .padding(.top, 4)

            TwoColumn(leftFr: 1, rightFr: 1.15) {
                listCard
            } right: {
                editorSide
            }
        }
    }

    private var listCard: some View {
        Card(padding: 14) {
            VStack(spacing: 7) {
                if model.clips.isEmpty {
                    Text("No recordings yet.")
                        .font(Typo.font(14, 400))
                        .foregroundColor(Theme.placeholder)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 8)
                } else {
                    ForEach(model.clips) { clip in
                        ClipRowView(model: model, clip: clip, variant: .library)
                    }
                }
            }
        }
    }

    @ViewBuilder private var editorSide: some View {
        if let clip = model.selectedClip {
            // Keyed on the clip id so the editor fully remounts when the selection changes —
            // otherwise the previous clip's edited text would persist in the field.
            // Key on transcription-state too, so the field remounts (and picks up the text)
            // when a retry fills in a previously-empty transcript.
            EditorPane(model: model, clip: clip).id("\(clip.id)-\(clip.needsTranscription)")
        } else {
            VStack {
                Text("Select a clip to see its transcript.")
                    .font(Typo.font(14, 400))
                    .foregroundColor(Theme.creamMuted)
            }
            .frame(maxWidth: .infinity, minHeight: 420, alignment: .center)
            .background(RoundedRectangle(cornerRadius: Theme.Radius.card).fill(Theme.cream))
        }
    }
}

private struct EditorPane: View {
    @ObservedObject var model: AppModel
    let clip: Clip

    @State private var text: String
    @State private var flashBg: Color = Theme.card
    @State private var confirmingDelete = false

    init(model: AppModel, clip: Clip) {
        self.model = model
        self.clip = clip
        _text = State(initialValue: clip.text)
    }

    private var isPlaying: Bool { model.playingId == clip.id }
    private var fraction: Double { isPlaying ? model.progress : 0 }
    private var elapsedLabel: String {
        isPlaying ? Clip.formatSeconds(Int((Double(clip.seconds) * fraction).rounded())) : "0:00"
    }
    private var wordCount: Int { text.split(whereSeparator: { $0 == " " || $0 == "\n" }).count }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Metadata
            HStack(spacing: 10) {
                Text(clip.timeLabel); Text("·"); Text(clip.durationLabel); Text("·"); Text(clip.sizeLabel)
            }
            .font(Typo.font(12, 700))
            .tracking(0.04 * 12)
            .foregroundColor(Theme.marigoldInk)

            // Player
            HStack(spacing: 14) {
                Button { model.togglePlaySelected() } label: {
                    ZStack {
                        Circle().fill(Theme.marigold).frame(width: 44, height: 44)
                        SolarIcon(name: isPlaying ? Solar.pause : Solar.play, size: 19, color: Theme.creamInk)
                    }
                }
                .buttonStyle(.plain)

                VStack(spacing: 7) {
                    ProgressTrack(fraction: fraction, height: 8, track: Theme.creamLine, fill: Theme.sage)
                    HStack {
                        Text(elapsedLabel)
                        Spacer()
                        Text(clip.durationLabel)
                    }
                    .font(Typo.font(11.5, 700))
                    .foregroundColor(Theme.creamMuted)
                }
            }

            Rectangle().fill(Theme.creamLine).frame(height: 1)

            // Transcript — editable field, or a retry panel if it never transcribed.
            if clip.needsTranscription {
                retryPanel
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("TRANSCRIPT · EDITABLE")
                            .font(Typo.font(12, 700)).tracking(0.06 * 12)
                            .foregroundColor(Theme.creamMuted)
                        Spacer()
                        Text("\(wordCount) words")
                            .font(Typo.font(12, 700))
                            .foregroundColor(Theme.muted)
                    }

                    TextEditor(text: $text)
                        .font(Typo.font(17.5, 400))
                        .foregroundColor(Theme.ink)
                        .scrollContentBackground(.hidden)
                        .padding(EdgeInsets(top: 14, leading: 16, bottom: 14, trailing: 16))
                        .frame(minHeight: 120)
                        .background(RoundedRectangle(cornerRadius: Theme.Radius.editor).fill(flashBg))
                        .overlay(
                            RoundedRectangle(cornerRadius: Theme.Radius.editor)
                                .stroke(Theme.creamLine2, lineWidth: 1.5)
                        )
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            // Actions
            HStack(spacing: 8) {
                if !clip.needsTranscription {
                    Button { model.saveEdit(text) } label: {
                        pill(icon: Solar.check, title: "Save changes",
                             bg: Theme.ink, fg: Theme.cream, weight: 800)
                    }
                    .buttonStyle(.plain)

                    Button { model.copySelected() } label: {
                        pill(icon: Solar.copy, title: "Copy",
                             bg: Theme.creamChip, fg: Theme.creamBody, weight: 700)
                    }
                    .buttonStyle(.plain)
                }

                Spacer()

                deleteControl
            }
        }
        .padding(22)
        .frame(maxWidth: .infinity, minHeight: 420, alignment: .topLeading)
        .background(RoundedRectangle(cornerRadius: Theme.Radius.card).fill(Theme.cream))
        .onAppear(perform: maybeFlash)
    }

    private var isTranscribing: Bool { model.transcribingIds.contains(clip.id) }

    // Shown in place of the editor when a clip has audio but no transcript yet.
    private var retryPanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("TRANSCRIPT")
                .font(Typo.font(12, 700)).tracking(0.06 * 12)
                .foregroundColor(Theme.creamMuted)
            VStack(spacing: 10) {
                if isTranscribing {
                    ProgressView()
                    Text("Transcribing…").font(Typo.font(14, 700)).foregroundColor(Theme.creamBody)
                } else {
                    Text("This recording didn't get transcribed.")
                        .font(Typo.font(15, 700)).foregroundColor(Theme.creamInk)
                    Text("Your audio is safe — retry when you're back online.")
                        .font(Typo.font(12.5, 400)).foregroundColor(Theme.creamMuted)
                    Button { model.retryTranscription(clip.id) } label: {
                        HStack(spacing: 7) {
                            SolarIcon(name: Solar.restart, size: 15, color: Theme.cream)
                            Text("Retry transcription").font(Typo.font(13, 800)).foregroundColor(Theme.cream)
                        }
                        .padding(.horizontal, 18).padding(.vertical, 11)
                        .background(Capsule().fill(Theme.ink))
                    }
                    .buttonStyle(.plain)
                    .padding(.top, 2)
                }
            }
            .frame(maxWidth: .infinity, minHeight: 120)
            .padding(20)
            .background(RoundedRectangle(cornerRadius: Theme.Radius.editor).fill(Theme.card))
            .overlay(RoundedRectangle(cornerRadius: Theme.Radius.editor).stroke(Theme.creamLine2, lineWidth: 1.5))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // Delete asks first (irreversible: removes audio + transcript, no undo).
    @ViewBuilder private var deleteControl: some View {
        if confirmingDelete {
            HStack(spacing: 6) {
                Button { model.deleteSelected(); confirmingDelete = false } label: {
                    Text("Delete").font(Typo.font(13, 800)).foregroundColor(Theme.danger)
                }.buttonStyle(.plain)
                Text("·").foregroundColor(Theme.muted)
                Button { confirmingDelete = false } label: {
                    Text("Cancel").font(Typo.font(13, 700)).foregroundColor(Theme.muted)
                }.buttonStyle(.plain)
            }
            .padding(.horizontal, 12).padding(.vertical, 10)
        } else {
            Button { confirmingDelete = true } label: {
                HStack(spacing: 7) {
                    SolarIcon(name: Solar.trash, size: 15, color: Theme.danger)
                    Text("Delete clip").font(Typo.font(13, 700)).foregroundColor(Theme.danger)
                }
                .padding(.horizontal, 12).padding(.vertical, 10)
            }
            .buttonStyle(.plain)
        }
    }

    private func pill(icon: String, title: String, bg: Color, fg: Color, weight: CGFloat) -> some View {
        HStack(spacing: 7) {
            SolarIcon(name: icon, size: 15, color: fg)
            Text(title).font(Typo.font(13, weight)).foregroundColor(fg)
        }
        .padding(.horizontal, title == "Save changes" ? 18 : 16)
        .padding(.vertical, 10)
        .background(Capsule().fill(bg))
    }

    /// fGlow: flash the field when text has just landed in this clip, then settle to base.
    private func maybeFlash() {
        guard model.flashClipId == clip.id else { flashBg = Theme.card; return }
        flashBg = Theme.marigoldFlash
        withAnimation(.easeOut(duration: 1.4)) { flashBg = Theme.card }
    }
}
