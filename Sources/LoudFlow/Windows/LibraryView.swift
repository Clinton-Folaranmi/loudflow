import SwiftUI

struct LibraryView: View {
    @ObservedObject var model: AppModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var contentFrame: CGRect = .zero
    @State private var viewportHeight: CGFloat = 0

    private static let listSpace = "library.list"

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Library").textStyle(.pageTitle).foregroundColor(Theme.ink)
                Text("\(model.clips.count) recordings").textStyle(.subtitle).foregroundColor(Theme.body)
            }
            .padding(.horizontal, 4)
            .padding(.top, 4)

            HStack(alignment: .center, spacing: 12) {
                filterChips
                Spacer(minLength: 12)
                librarySearch
            }

            TwoColumn(leftFr: 1, rightFr: 1.15, fillHeight: true) {
                listCard
            } right: {
                editorSide
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var filterChips: some View {
        HStack(spacing: 8) {
            ForEach(LibraryFilter.allCases, id: \.self) { filter in
                FilterChip(title: filter.label, active: model.libraryFilter == filter) {
                    withAnimation(reduceMotion ? nil : Motion.page) { model.setFilter(filter) }
                }
            }
        }
        .padding(.horizontal, 4)
    }

    private var librarySearch: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass").font(.system(size: 14, weight: .semibold)).foregroundColor(Theme.muted)
            ZStack(alignment: .leading) {
                if model.librarySearch.isEmpty {
                    Text("Search titles or transcripts")
                        .font(Typo.font(13, 600))
                        .foregroundColor(Theme.muted)
                        .allowsHitTesting(false)
                }
                TextField("", text: Binding(
                    get: { model.librarySearch },
                    set: { model.setLibrarySearch($0) }
                ))
                    .textFieldStyle(.plain)
                    .font(Typo.font(13, 600))
                    .foregroundColor(Theme.ink)
                    .accessibilityLabel("Search titles or transcripts")
            }
            if !model.librarySearch.isEmpty {
                Button { model.setLibrarySearch("") } label: {
                    Image(systemName: "xmark.circle.fill").foregroundColor(Theme.muted)
                }
                .buttonStyle(.plain)
                .clickable()
                .transition(.opacity)
            }
        }
        .padding(.horizontal, 11).padding(.vertical, 9)
        .frame(width: 230)
        .background(Capsule().fill(Theme.card))
        .overlay(Capsule().stroke(Theme.hairline, lineWidth: 1))
        .animation(reduceMotion ? nil : Motion.feedback, value: model.librarySearch.isEmpty)
    }

    private var listCard: some View {
        Card(padding: 14, fillHeight: true) {
            ScrollView(.vertical) {
                LazyVStack(spacing: 7) {
                    if model.filteredClips.isEmpty {
                        Text(model.librarySearch.isEmpty ? "No recordings yet." : "No matching recordings.")
                            .font(Typo.font(14, 400))
                            .foregroundColor(Theme.placeholder)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.vertical, 8)
                    } else {
                        ForEach(model.filteredClips) { clip in
                            ClipRowView(model: model, clip: clip, variant: .library)
                        }
                    }
                }
                .background(
                    GeometryReader { c in
                        Color.clear.preference(key: ListContentKey.self,
                                               value: c.frame(in: .named(Self.listSpace)))
                    }
                )
            }
            .coordinateSpace(name: Self.listSpace)
            .background(
                GeometryReader { v in
                    Color.clear.preference(key: ListViewportKey.self, value: v.size.height)
                }
            )
            .onPreferenceChange(ListContentKey.self) { contentFrame = $0 }
            .onPreferenceChange(ListViewportKey.self) { viewportHeight = $0 }
            .overlay(alignment: .top) {
                edgeFade(height: 18, top: true).opacity(fadeTop ? 1 : 0)
            }
            .overlay(alignment: .bottom) {
                edgeFade(height: 22, top: false).opacity(fadeBottom ? 1 : 0)
            }
            .animation(reduceMotion ? nil : Motion.feedback, value: fadeTop)
            .animation(reduceMotion ? nil : Motion.feedback, value: fadeBottom)
        }
    }

    private var fadeTop: Bool { contentFrame.minY < -1 }
    private var fadeBottom: Bool { contentFrame.maxY > viewportHeight + 1 }

    private func edgeFade(height: CGFloat, top: Bool) -> some View {
        LinearGradient(
            colors: top ? [Theme.card, Theme.card.opacity(0)] : [Theme.card.opacity(0), Theme.card],
            startPoint: .top, endPoint: .bottom
        )
        .frame(height: height)
        .allowsHitTesting(false)
    }

    @ViewBuilder private var editorSide: some View {
        if let clip = model.selectedClip {

            // Remount the local draft when selection or transcription state changes.
            EditorPane(model: model, clip: clip)
                .id("\(clip.id)-\(clip.needsTranscription)")
        } else {
            VStack {
                Text("Select a clip to see its transcript.")
                    .font(Typo.font(14, 400))
                    .foregroundColor(Theme.creamMuted)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            .background(RoundedRectangle(cornerRadius: Theme.Radius.card).fill(Theme.cream))
        }
    }
}

private struct ListContentKey: PreferenceKey {
    static var defaultValue: CGRect = .zero
    static func reduce(value: inout CGRect, nextValue: () -> CGRect) { value = nextValue() }
}

private struct ListViewportKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = nextValue() }
}

// MARK: - Editor

private struct EditorPane: View {
    @ObservedObject var model: AppModel
    let clip: Clip

    @State private var blocks: [String]
    @State private var savedBlocks: [String]
    @State private var flashBg: Color = Theme.card
    @State private var confirmingDelete = false
    @State private var renamingVoice: Int?
    @State private var justCopied = false
    @State private var justSaved = false
    @State private var meetingTitle: String
    @FocusState private var titleFocused: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(model: AppModel, clip: Clip) {
        self.model = model
        self.clip = clip
        let initialBlocks = clip.isConversation
            ? (clip.turns ?? []).map(\.text)
            : clip.sentences
        _blocks = State(initialValue: initialBlocks)
        _savedBlocks = State(initialValue: initialBlocks)
        _meetingTitle = State(initialValue: clip.title ?? "")
    }

    private var isPlaying: Bool { model.playingId == clip.id }
    private var fraction: Double { model.progress(for: clip.id) }
    private var elapsedLabel: String {
        Clip.formatSeconds(Int((Double(clip.seconds) * fraction).rounded()))
    }
    private var wordCount: Int {
        blocks.joined(separator: " ").split(whereSeparator: { $0 == " " || $0 == "\n" }).count
    }
    private var isDirty: Bool { blocks != savedBlocks }
    private var isTranscribing: Bool { model.transcribingIds.contains(clip.id) }

    private var editingConversation: Bool { clip.isConversation && model.editingTranscript }

    private var transcriptLabel: String {
        editingConversation ? "TRANSCRIPT · EDITING" : "TRANSCRIPT"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if clip.isConversation { meetingTitleField }
            metadata

            if clip.audioDeleted {
                retentionStrip
            } else {
                player
            }

            Rectangle().fill(Theme.creamLine).frame(height: 1)

            if clip.needsTranscription {
                retryPanel
            } else {
                transcript
            }

            actions
        }
        .padding(22)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(RoundedRectangle(cornerRadius: Theme.Radius.card).fill(Theme.cream))
        .onAppear(perform: maybeFlash)
        .onChange(of: model.editingTranscript) { editing in
            if !editing && clip.isConversation { commitDraft() }
        }
        .onDisappear {
            commitDraft()
            saveMeetingTitle()
        }
    }

    private var meetingTitleField: some View {
        HStack(spacing: 8) {
            TextField("Name this meeting", text: $meetingTitle)
                .textFieldStyle(.plain)
                .font(Typo.font(18, 800))
                .foregroundColor(Theme.creamInk)
                .focused($titleFocused)
                .onSubmit(saveMeetingTitle)
                .onChange(of: titleFocused) { _, focused in
                    if !focused { saveMeetingTitle() }
                }
                .accessibilityLabel("Meeting title")
            SolarIcon(name: Solar.pen, size: 14, color: Theme.creamMuted)
                .allowsHitTesting(false)
        }
    }

    private func saveMeetingTitle() {
        guard clip.isConversation else { return }
        let trimmed = meetingTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        meetingTitle = trimmed
        model.renameMeeting(clip.id, to: trimmed)
    }

    private var metadata: some View {
        HStack(spacing: 10) {
            Text(clip.timeLabel); Text("·"); Text(clip.durationLabel); Text("·")
            Text(clip.audioDeleted ? "transcript only" : clip.sizeLabel)
        }
        .font(Typo.font(12, 700))
        .tracking(0.04 * 12)
        .foregroundColor(Theme.marigoldInk)
    }

    private var player: some View {
        HStack(spacing: 14) {
            Button { model.togglePlaySelected() } label: {
                ZStack {
                    Circle().fill(Theme.marigold).frame(width: 44, height: 44)
                    SolarIcon(name: isPlaying ? Solar.pause : Solar.play, size: 19, color: Theme.creamInk)
                }
            }
            .buttonStyle(PressFeedbackStyle())
            .clickable()

            VStack(spacing: 1) {
                Scrubber(fraction: fraction) { model.seek(clip, to: $0) }
                HStack {
                    Text(elapsedLabel)
                    Spacer()
                    Text(clip.durationLabel)
                }
                .font(Typo.font(11.5, 700))
                .foregroundColor(Theme.creamMuted)
            }

            Menu {
                ForEach([Float(0.75), 1, 1.25, 1.5, 2], id: \.self) { rate in
                    Button { model.playbackRate = rate } label: {
                        if rate == model.playbackRate {
                            Label(rateLabel(rate), systemImage: "checkmark")
                        } else {
                            Text(rateLabel(rate))
                        }
                    }
                }
            } label: {
                Text(rateLabel(model.playbackRate))
                    .font(Typo.font(12, 800))
                    .foregroundColor(Theme.creamBody)
                    .frame(minWidth: 40)
                    .padding(.horizontal, 8).padding(.vertical, 7)
                    .background(Capsule().fill(Theme.creamChip))
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .clickable()
            .help("Playback speed")
        }
    }

    private func rateLabel(_ rate: Float) -> String {
        rate == 1 ? "1×" : "\(rate.formatted())×"
    }

    private var retentionStrip: some View {
        HStack(spacing: 10) {
            SolarIcon(name: Solar.history, size: 17, color: Theme.creamMuted)
            Text("Audio cleared by retention. The transcript stays.")
                .font(Typo.font(12.5, 700))
                .foregroundColor(Theme.marigoldInk)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 15).padding(.vertical, 13)
        .background(RoundedRectangle(cornerRadius: Theme.Radius.editor).fill(Theme.creamChip))
    }

    private var transcript: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(transcriptLabel)
                    .font(Typo.font(12, 700)).tracking(0.06 * 12)
                    .foregroundColor(Theme.creamMuted)
                Spacer()
                Text("\(wordCount) words")
                    .font(Typo.font(12, 700))
                    .foregroundColor(Theme.muted)
            }

            ScrollViewReader { proxy in
                ScrollView(.vertical) {
                    if clip.isConversation {
                        turnBlocks
                    } else {
                        sentenceBlocks
                    }
                }
                .onChange(of: activeIndex) { index in
                    guard let index, !model.editingTranscript else { return }
                    if reduceMotion { proxy.scrollTo(index, anchor: .center) }
                    else { withAnimation(Motion.page) { proxy.scrollTo(index, anchor: .center) } }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .padding(.horizontal, 12).padding(.vertical, 11)
            .background(RoundedRectangle(cornerRadius: Theme.Radius.editor).fill(flashBg))
            .overlay(
                RoundedRectangle(cornerRadius: Theme.Radius.editor)
                    .stroke(Theme.creamLine2, lineWidth: 1.5)
            )
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var turns: [Turn] { clip.turns ?? [] }

    private var turnBlocks: some View {
        LazyVStack(alignment: .leading, spacing: 8) {
            ForEach(Array(turns.enumerated()), id: \.offset) { i, turn in
                TurnBlockView(
                    model: model,
                    clip: clip,
                    index: i,
                    turn: turn,
                    editing: editingConversation,
                    active: activeIndex == i,
                    text: binding(i),
                    renamingVoice: $renamingVoice
                )
                .id(i)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var sentenceBlocks: some View {
        LazyVStack(alignment: .leading, spacing: 2) {
            ForEach(Array(blocks.enumerated()), id: \.offset) { i, _ in
                TextField("", text: binding(i), axis: .vertical)
                    .textFieldStyle(.plain)
                    .font(Typo.font(14, 400))
                    .lineSpacing(14 * 0.5)
                    .foregroundColor(Theme.ink)
                    .padding(.horizontal, 6).padding(.vertical, 4)
                    .background(
                        RoundedRectangle(cornerRadius: 9)
                            .fill(activeIndex == i ? Theme.creamChip : .clear)
                    )
                    .id(i)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func binding(_ i: Int) -> Binding<String> {
        Binding(
            get: { i < blocks.count ? blocks[i] : "" },
            set: { if i < blocks.count { blocks[i] = $0 } }
        )
    }

    private var activeIndex: Int? {
        guard isPlaying else { return nil }
        if clip.isConversation { return model.activeTurnIndex(in: clip) }
        let now = fraction * Double(clip.seconds)
        return clip.sentenceRanges.lastIndex { $0.start <= now }
    }

    private var retryPanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("TRANSCRIPT")
                .font(Typo.font(12, 700)).tracking(0.06 * 12)
                .foregroundColor(Theme.creamMuted)
            VStack(spacing: 10) {
                if isTranscribing {
                    SpinRing(size: 18, lineWidth: 2.5)
                    Text("Transcribing…").font(Typo.font(14, 700)).foregroundColor(Theme.creamBody)
                } else {
                    Text("This recording didn't get transcribed.")
                        .font(Typo.font(15, 700)).foregroundColor(Theme.creamInk)

                    if clip.audioDeleted {
                        Text("The audio was cleared by retention before this one transcribed, so there's nothing left to send.")
                            .font(Typo.font(12.5, 400))
                            .foregroundColor(Theme.creamMuted)
                            .multilineTextAlignment(.center)
                            .lineSpacing(12.5 * 0.5)
                            .frame(maxWidth: 280)
                    } else {
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
                        .clickable()
                        .padding(.top, 2)
                    }
                }
            }
            .frame(maxWidth: .infinity, minHeight: 120)
            .padding(20)
            .background(RoundedRectangle(cornerRadius: Theme.Radius.editor).fill(Theme.card))
            .overlay(RoundedRectangle(cornerRadius: Theme.Radius.editor).stroke(Theme.creamLine2, lineWidth: 1.5))

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var actions: some View {
        HStack(spacing: 8) {
            if !clip.needsTranscription {
                if clip.isConversation {
                    Button(action: toggleConversationEditing) {
                        pill(icon: model.editingTranscript ? Solar.check : Solar.pen,
                             title: model.editingTranscript ? "Done editing" : "Edit transcript",
                             bg: Theme.ink, fg: Theme.cream, weight: 800)
                    }
                    .buttonStyle(PressFeedbackStyle())
                    .clickable()
                } else {
                    Button(action: saveTapped) {
                        pill(icon: Solar.check, title: justSaved ? "Saved" : "Save changes",
                             bg: Theme.ink, fg: Theme.cream, weight: 800)
                    }
                    .buttonStyle(PressFeedbackStyle())
                    .clickable()
                    .animation(reduceMotion ? nil : Motion.feedback, value: justSaved)
                    .disabled(!isDirty)
                    .opacity(isDirty || justSaved ? 1 : 0.6)
                }

                Button(action: copyTapped) {
                    pill(icon: justCopied ? Solar.check : Solar.copy,
                         title: justCopied ? "Copied" : "Copy",
                         bg: Theme.creamChip, fg: Theme.creamBody, weight: 700)
                }
                .buttonStyle(PressFeedbackStyle())
                .clickable()
                .animation(reduceMotion ? nil : Motion.feedback, value: justCopied)
            }

            Spacer()

            deleteControl
        }
    }

    private func copyTapped() {
        model.copySelected()
        justCopied = true
        Task {
            try? await Task.sleep(nanoseconds: 1_600_000_000)
            justCopied = false
        }
    }

    private func saveTapped() {
        commitDraft()
        justSaved = true
        Task {
            try? await Task.sleep(nanoseconds: 1_600_000_000)
            justSaved = false
        }
    }

    private func toggleConversationEditing() {
        if model.editingTranscript {
            commitDraft()
            model.editingTranscript = false
        } else {
            renamingVoice = nil
            model.editingTranscript = true
        }
    }

    private func commitDraft() {
        guard isDirty else { return }
        if clip.isConversation {
            model.saveTurns(blocks, for: clip.id)
        } else {
            model.saveEdit(blocks.joined(separator: " "), for: clip.id)
        }
        savedBlocks = blocks
    }

    @ViewBuilder private var deleteControl: some View {
        if confirmingDelete {
            HStack(spacing: 6) {
                Button { model.deleteSelected(); confirmingDelete = false } label: {
                    Text("Delete").font(Typo.font(13, 800)).foregroundColor(Theme.danger)
                }.buttonStyle(PressFeedbackStyle())
                .clickable()
                Text("·").foregroundColor(Theme.muted)
                Button { withAnimation(reduceMotion ? nil : Motion.feedback) { confirmingDelete = false } } label: {
                    Text("Cancel").font(Typo.font(13, 700)).foregroundColor(Theme.muted)
                }.buttonStyle(PressFeedbackStyle())
                .clickable()
            }
            .padding(.horizontal, 12).padding(.vertical, 10)
            .onExitCommand { confirmingDelete = false }
            .transition(.opacity)
        } else {
            Button { withAnimation(reduceMotion ? nil : Motion.feedback) { confirmingDelete = true } } label: {
                HStack(spacing: 7) {
                    SolarIcon(name: Solar.trash, size: 15, color: Theme.danger)
                    Text("Delete clip").font(Typo.font(13, 700)).foregroundColor(Theme.danger)
                }
                .padding(.horizontal, 12).padding(.vertical, 10)
            }
            .buttonStyle(PressFeedbackStyle())
            .clickable()
            .transition(.opacity)
        }
    }

    private func pill(icon: String, title: String, bg: Color, fg: Color, weight: CGFloat) -> some View {
        HStack(spacing: 7) {
            SolarIcon(name: icon, size: 15, color: fg)
            Text(title).font(Typo.font(13, weight)).foregroundColor(fg)
        }
        .padding(.horizontal, bg == Theme.ink ? 18 : 16)
        .padding(.vertical, 10)
        .background(Capsule().fill(bg))
    }

    private func maybeFlash() {
        guard model.flashClipId == clip.id else { flashBg = Theme.card; return }
        flashBg = Theme.marigoldFlash
        withAnimation(.easeOut(duration: 1.4)) { flashBg = Theme.card }
    }
}
