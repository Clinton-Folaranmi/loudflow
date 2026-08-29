import SwiftUI

/// A clip row, shared by Today and Library. Clicking the row opens the clip in Library;
/// the leading circle and the copy pill stop propagation so they don't also open it.
///
/// The leading circle says **what kind of recording this is** — a soundwave for a note, a group
/// for a meeting — and morphs to play on hover. That is the only place the two kinds are
/// announced, because the kind is derived from how many voices were heard, not chosen.
struct ClipRowView: View {
    enum Variant { case today, library }

    @ObservedObject var model: AppModel
    let clip: Clip
    var variant: Variant = .today

    @State private var hovering = false

    private var isPlaying: Bool { model.playingId == clip.id }
    private var isSelected: Bool { model.selectedId == clip.id }
    private var playSize: CGFloat { variant == .today ? 30 : 32 }
    private var rowGap: CGFloat { variant == .today ? 14 : 12 }
    private var hPad: CGFloat { variant == .today ? 13 : 12 }
    private var isTranscribing: Bool { model.transcribingIds.contains(clip.id) }
    private var previewText: String {
        if isTranscribing { return "Transcribing…" }
        if clip.needsTranscription { return "Transcription didn't finish" }
        return clip.preview(voices: model.voices.voices)
    }

    private var background: Color {
        if hovering { return Theme.rowHover }
        switch variant {
        case .today:   return Theme.row
        case .library: return isSelected ? Theme.rowSelected : .clear
        }
    }

    // MARK: Leading circle

    /// Rest shows the kind; hover offers to play it; playing offers to stop.
    private var leadingIcon: String {
        if isPlaying { return Solar.pause }
        if hovering { return Solar.play }
        return clip.isConversation ? Solar.speakers : Solar.today
    }

    private var circleFill: Color {
        if clip.audioDeleted { return Theme.sagePale2 }
        return isPlaying ? Theme.marigold : Theme.sagePale
    }

    private var circleInk: Color {
        if clip.audioDeleted { return Theme.playMuted }
        return isPlaying ? Theme.creamInk : Theme.sageDeep
    }

    var body: some View {
        HStack(spacing: rowGap) {
            // Play / pause — stops propagation so playback never opens the clip.
            Button { model.play(clip) } label: {
                ZStack {
                    Circle().fill(circleFill)
                    SolarIcon(name: leadingIcon,
                              size: variant == .today ? 14 : 15,
                              color: circleInk)
                }
                .frame(width: playSize, height: playSize)
            }
            .buttonStyle(.plain)
            .help(clip.audioDeleted ? "Audio cleared by retention" : "")

            VStack(alignment: .leading, spacing: 2) {
                Text(previewText)
                    .font(Typo.font(14, isSelected && variant == .library ? 700 : 400))
                    .foregroundColor(clip.needsTranscription ? Theme.muted : Theme.ink)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Text(clip.metadataLine)
                    .font(Typo.font(11.5, 600))
                    .foregroundColor(Theme.muted)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            trailingAction

            Text(clip.durationLabel)
                .font(Typo.font(12, 700))
                .foregroundColor(Theme.muted)
                .frame(width: 34, alignment: .trailing)
        }
        .padding(.horizontal, hPad)
        .padding(.vertical, 11)
        .background(RoundedRectangle(cornerRadius: Theme.Radius.rowInner).fill(background))
        .contentShape(RoundedRectangle(cornerRadius: Theme.Radius.rowInner))
        .onHover { hovering = $0 }
        .onTapGesture { model.openClip(clip.id) }
    }

    @ViewBuilder private var trailingAction: some View {
        if isTranscribing {
            // Copy and retry stay hidden while a row is transcribing — there is nothing to act
            // on yet.
            HStack(spacing: 7) {
                SpinRing()
                Text("Transcribing…").font(Typo.font(11.5, 700)).foregroundColor(Theme.muted)
            }
            .padding(.horizontal, 10).padding(.vertical, 6)
        } else if clip.needsTranscription {
            // Retry — always visible (it's an error to fix).
            Button { model.retryTranscription(clip.id) } label: {
                HStack(spacing: 6) {
                    SolarIcon(name: Solar.restart, size: 13, color: Theme.marigoldInk)
                    Text("Retry").font(Typo.font(11.5, 700)).foregroundColor(Theme.marigoldInk)
                }
                .padding(.horizontal, 12).padding(.vertical, 6)
                .background(Capsule().fill(Theme.marigoldPale))
            }
            .buttonStyle(.plain)
        } else {
            // Copy pill — hidden until hover. One button: a meeting copies with speaker names,
            // a note copies bare.
            Button { model.copy(clip) } label: {
                HStack(spacing: 6) {
                    SolarIcon(name: Solar.copy, size: 13, color: Theme.body)
                    Text("Copy").font(Typo.font(11.5, 700)).foregroundColor(Theme.body)
                }
                .padding(.horizontal, 12).padding(.vertical, 6)
                .background(Capsule().fill(Theme.sagePale))
            }
            .buttonStyle(.plain)
            .opacity(hovering ? 1 : 0)
            .allowsHitTesting(hovering)
            .animation(.easeInOut(duration: 0.14), value: hovering)
        }
    }
}
