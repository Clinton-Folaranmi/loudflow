import SwiftUI
import AppKit
import Combine

enum Tab: String, CaseIterable { case today, library, settings, receipts }

/// The Library's filter chips. A clip's kind is derived from how many voices are in it, so
/// these are just views onto the same list — there is no mode to switch on.
enum LibraryFilter: String, CaseIterable {
    case all, notes, meetings

    var label: String {
        switch self {
        case .all:      return "All"
        case .notes:    return "Notes"
        case .meetings: return "Meetings"
        }
    }

    func matches(_ clip: Clip) -> Bool {
        switch self {
        case .all:      return true
        case .notes:    return !clip.isConversation
        case .meetings: return clip.isConversation
        }
    }
}

struct Toast: Identifiable, Equatable {
    let id = UUID()
    var message: String
    var action: String = ""
    var kind: Kind = .plain
    enum Kind { case plain, fixLast }
}

/// The single source of truth. Mirrors the spec's state model and adds the real-world bits:
/// permissions, the API-key status, the offline queue, and the widget error states.
@MainActor
final class AppModel: ObservableObject {

    // MARK: Navigation
    @Published var showingOnboarding: Bool
    @Published var onboardingStep: Int = 0          // 0…3 (now four steps)
    @Published var tab: Tab = .today

    // MARK: Settings (mirrored to Preferences)
    @Published var trigger: TriggerMode { didSet { Preferences.trigger = trigger; hotkeys.setMode(trigger) } }
    @Published var retention: Retention { didSet { Preferences.retention = retention } }
    @Published var options: DictationOptions { didSet { Preferences.options = options } }
    @Published var provider: Provider { didSet { Preferences.provider = provider; rebuildTranscriber(); refreshKeyStatus() } }

    // MARK: Recording / widget
    @Published var widgetState: WidgetState = .idle
    @Published var elapsed: Int = 0

    // MARK: Clips
    @Published var clips: [Clip]
    @Published var selectedId: UUID?
    @Published var playingId: UUID?
    /// The playhead per clip (0…1). It belongs to the clip, not the player, so pausing keeps
    /// the position and the scrubber still shows it when nothing is playing.
    @Published var progressByClip: [UUID: Double] = [:]
    @Published var libraryFilter: LibraryFilter = .all
    /// Conversations are read by default; this is the `Edit transcript` / `Done editing` state.
    @Published var editingTranscript = false
    @Published var hoveredId: UUID?
    @Published var flashClipId: UUID?               // drives the editor fGlow when text lands
    @Published var transcribingIds: Set<UUID> = []  // clips currently being (re)transcribed

    // MARK: Feedback
    @Published var toast: Toast?
    @Published var displayName: String { didSet { Preferences.displayName = displayName } }

    // MARK: Voices
    /// Stored voice profiles. Naming a voice renames every turn it ever spoke.
    let voices = VoiceStore()
    /// Matches a new recording's speakers against voices you have already named, on-device.
    let recognizer = VoiceRecognizer()
    /// The voice whose two-second sample is playing in Settings, if any.
    @Published var playingVoiceId: Int?

    // MARK: Key / permissions status
    enum KeyStatus: Equatable { case missing, saved, checking, rejected }
    @Published var keyStatus: KeyStatus = .missing

    /// Set by the app layer so the model can bring the main window forward.
    var showMainWindow: (() -> Void)?

    // MARK: Plumbing
    private let recorder = AudioRecorder()
    private let player = AudioPlayer()
    /// Separate from `player` so auditioning a voice in Settings never stops a clip.
    private let samplePlayer = AudioPlayer()
    private var voiceObserver: AnyCancellable?
    private var recognizerObserver: AnyCancellable?
    private let hotkeys = HotkeyManager()
    private let queue = TranscriptionQueue()
    private var transcriber: Transcriber
    private var tickTimer: Timer?
    private var toastTimer: Timer?
    private var queuedRevertTimer: Timer?

    // Constants from the spec.
    let wpm = 184

    init() {
        let opts = Preferences.options
        let trig = Preferences.trigger
        let ret = Preferences.retention
        let prov = Preferences.provider

        self.showingOnboarding = !Preferences.onboarded
        self.options = opts
        self.trigger = trig
        self.retention = ret
        self.provider = prov
        self.clips = Persistence.shared.loadClips()
        self.displayName = Preferences.displayName ?? ""
        self.transcriber = TranscriberFactory.make(provider: prov)
        self.selectedId = clips.first?.id

        refreshKeyStatus()
        wireUp()
        sweepRetention()
        pruneVoices()
    }

    private func wireUp() {
        // The voice store is its own observable; republish so any view watching the model
        // redraws when a voice is named or forgotten.
        voiceObserver = voices.objectWillChange.sink { [weak self] _ in self?.objectWillChange.send() }
        recognizerObserver = recognizer.objectWillChange.sink { [weak self] _ in self?.objectWillChange.send() }

        player.onProgress = { [weak self] p in
            guard let self, let id = self.playingId else { return }
            self.progressByClip[id] = p
        }
        // Finishing leaves the playhead at the end rather than snapping back.
        player.onFinish = { [weak self] in self?.playingId = nil }

        samplePlayer.onFinish = { [weak self] in self?.playingVoiceId = nil }

        hotkeys.onHoldStart = { [weak self] in self?.startRecording() }
        hotkeys.onHoldStop = { [weak self] in self?.stopRecording() }
        hotkeys.onDoubleTapToggle = { [weak self] in self?.toggleRecording() }
        hotkeys.setMode(trigger)

        // When the network returns, retry anything still pending.
        queue.onNetworkRestored = { [weak self] in self?.retryPending() }
    }

    // MARK: - Key management

    var hasKey: Bool { Keychain.key(for: provider) != nil }

    func refreshKeyStatus() { keyStatus = hasKey ? .saved : .missing }

    func saveKey(_ raw: String) {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        Keychain.setKey(trimmed, for: provider)
        rebuildTranscriber()
        keyStatus = trimmed.isEmpty ? .missing : .saved
        // A saved key may unblock clips that failed for auth/credit reasons.
        if !trimmed.isEmpty { retryPending() }
    }

    func clearKey() {
        Keychain.clearKey(for: provider)
        rebuildTranscriber()
        keyStatus = .missing
    }

    /// Best-effort validation against the provider; updates `keyStatus`.
    func validateKey() {
        guard hasKey else { keyStatus = .missing; return }
        keyStatus = .checking
        Task {
            let ok = await transcriber.validateKey()
            await MainActor.run { self.keyStatus = ok ? .saved : .rejected }
        }
    }

    private func rebuildTranscriber() { transcriber = TranscriberFactory.make(provider: provider) }

    // MARK: - The core loop

    func toggleRecording() {
        if case .recording = widgetState { stopRecording() } else { startRecording() }
    }

    /// Stop recording and throw it away — no clip, no transcript, no upload.
    func cancelRecording() {
        stopTick()
        recorder.cancel()          // stops and deletes the file
        pendingAudio = nil
        elapsed = 0
        widgetState = .idle
        toast = Toast(message: "Discarded.")
        scheduleToastDismiss()
    }

    /// User explicitly chose a trigger. Only here do we prompt for Accessibility (for the
    /// hold/double hotkeys) — never on launch or activation.
    func selectTrigger(_ mode: TriggerMode) {
        trigger = mode
        if mode != .click { hotkeys.requestPermissionAndInstall() }
    }

    /// Widget hit targets, routed by trigger mode.
    func widgetClicked() { if trigger != .hold { toggleRecording() } }
    func widgetPressed() { if trigger == .hold { startRecording() } }
    func widgetReleased() { if trigger == .hold { stopRecording() } }
    func recordingPillTapped() { if trigger != .hold { stopRecording() } }

    func startRecording() {
        guard recorder.isRecording == false else { return }
        clearErrorToast()
        Permissions.requestMic { [weak self] granted in
            guard let self else { return }
            Task { @MainActor in
                guard granted else {
                    self.toast = Toast(message: "Microphone access is off — turn it on in System Settings.")
                    self.scheduleToastDismiss()
                    return
                }
                let target = Persistence.shared.newAudioURL()
                do {
                    try self.recorder.start(to: target.url)
                    self.pendingAudio = target
                    self.widgetState = .recording
                    self.elapsed = 0
                    self.startTick()
                    Earcons.recordStart()
                } catch {
                    self.toast = Toast(message: "Couldn't start the mic. Try again.")
                    self.scheduleToastDismiss()
                }
            }
        }
    }

    private var pendingAudio: (url: URL, fileName: String)?

    func stopRecording() {
        guard recorder.isRecording else { return }
        stopTick()
        Earcons.recordStop()
        // Closing the system-audio stream and encoding the two tracks takes a moment; the
        // widget shows `Transcribing…` for that whole stretch rather than flickering to idle.
        widgetState = .transcribing
        Task { await finishRecording() }
    }

    private func finishRecording() async {
        let outcome = await recorder.stop()
        guard let audio = pendingAudio else { widgetState = .idle; return }
        pendingAudio = nil

        let secs = max(1, Int(outcome.duration.rounded()))
        let size = Persistence.shared.fileSize(fileName: audio.fileName)

        // The audio is a first-class citizen: persist the clip immediately, even before
        // (or if we never get) a transcript. It starts life pending.
        let clip = Clip(createdAt: Date(), seconds: secs, sizeBytes: size,
                        text: "", audioFileName: audio.fileName,
                        twoTrack: outcome.twoTrack, status: .pending)
        clips.insert(clip, at: 0)
        persist()

        guard hasKey else {
            widgetState = .error(.missingKey)
            return
        }
        transcribe(clipID: clip.id, insertOnFinish: true)
    }

    /// Transcribe a clip. `insertOnFinish` = true only for a fresh recording (paste into the
    /// focused field + widget feedback); a retry from the library just fills in the transcript.
    private func transcribe(clipID: UUID, insertOnFinish: Bool) {
        guard let clip = clips.first(where: { $0.id == clipID }) else { return }
        let url = Persistence.shared.url(forAudio: clip.audioFileName)
        let twoTrack = clip.twoTrack
        transcribingIds.insert(clipID)
        Task {
            do {
                let result = try await transcriber.transcribe(url, twoTrack: twoTrack)
                await MainActor.run { self.finishTranscription(clipID: clipID, result: result, insert: insertOnFinish) }
            } catch let e as TranscriberError {
                await MainActor.run { self.handleTranscribeFailure(clipID: clipID, error: e, insert: insertOnFinish) }
            } catch {
                await MainActor.run { self.handleTranscribeFailure(clipID: clipID, error: .network, insert: insertOnFinish) }
            }
        }
    }

    private func finishTranscription(clipID: UUID, result: TranscriptionResult, insert: Bool) {
        transcribingIds.remove(clipID)
        guard let idx = clips.firstIndex(where: { $0.id == clipID }) else { return }

        // No post-processing at all. Punctuation, paragraph breaks, and readable numbers are
        // the provider's own output; rewording is what the app refuses, and nothing here does
        // any. What does happen is bookkeeping: the provider's per-recording speaker indices
        // become stored voice ids, with the mic track pinned to you.
        applyTranscript(result, toClipAt: idx)
        clips[idx].status = .done
        persist()
        recogniseVoices(inClip: clipID)

        let text = clips[idx].text
        Earcons.transcriptLanded()

        guard insert else {
            // Retry from the library: just fill the transcript, don't paste or touch the widget.
            toast = Toast(message: "Transcribed.")
            scheduleToastDismiss()
            return
        }

        // Fresh recording: insert at the cursor, or fall back to the clipboard.
        var didType = false
        if options.insert {
            didType = TextInserter.insert(text)
            if !didType { Permissions.nudgeAccessibility() }   // trust missing → guide the user
        } else {
            TextInserter.copyToClipboard(text)
        }

        // If audio isn't being kept, drop the file now (transcript stays).
        if !options.keep {
            Persistence.shared.deleteAudio(fileName: clips[idx].audioFileName)
            clips[idx].audioDeleted = true
            persist()
        }

        selectedId = clipID
        flashClipId = clipID
        widgetState = .idle
        let message = (options.insert && didType) ? "Recording pasted." : "Copied."
        toast = Toast(message: message, action: "Fix it", kind: .fixLast)
        scheduleToastDismiss()

        DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) { [weak self] in
            if self?.flashClipId == clipID { self?.flashClipId = nil }
        }
    }

    private func handleTranscribeFailure(clipID: UUID, error: TranscriberError, insert: Bool) {
        transcribingIds.remove(clipID)
        // Keep the clip pending so it can be retried; audio stays.
        if let idx = clips.firstIndex(where: { $0.id == clipID }) { clips[idx].status = .pending; persist() }
        switch error {
        case .network, .server, .decoding: queue.enqueue(clipID)
        default: break
        }

        guard insert else {
            // Retry from the library: just tell the user, don't change the widget.
            let msg: String
            switch error {
            case .network, .server, .decoding: msg = "Still couldn't reach the service. Try again in a bit."
            case .missingKey:                  msg = "Add a transcription key in Settings."
            case .auth:                        keyStatus = .rejected; msg = "That key was rejected."
            case .credit:                      msg = "Transcription account is out of credit."
            }
            toast = Toast(message: msg)
            scheduleToastDismiss()
            return
        }

        switch error {
        case .network, .server, .decoding:
            widgetState = .queued
            queuedRevertTimer?.invalidate()
            queuedRevertTimer = Timer.scheduledTimer(withTimeInterval: 2.6, repeats: false) { [weak self] _ in
                Task { @MainActor in if case .queued = self?.widgetState { self?.widgetState = .idle } }
            }
        case .missingKey: widgetState = .error(.missingKey)
        case .auth:       keyStatus = .rejected; widgetState = .error(.rejectedKey)
        case .credit:     widgetState = .error(.outOfCredit)
        }
    }

    /// Retry a single clip's transcription (from Today / Library).
    func retryTranscription(_ id: UUID) {
        guard let clip = clips.first(where: { $0.id == id }), !transcribingIds.contains(id) else { return }
        guard !clip.audioDeleted else {
            toast = Toast(message: "Audio was cleared — can't retry."); scheduleToastDismiss(); return
        }
        guard hasKey else {
            toast = Toast(message: "Add a transcription key in Settings."); scheduleToastDismiss()
            tab = .settings; showMainWindow?(); return
        }
        transcribe(clipID: id, insertOnFinish: false)
    }

    /// Re-attempts every still-pending clip that still has its audio (offline queue drained).
    func retryPending() {
        guard hasKey else { return }
        let pending = clips.filter { $0.status == .pending && !$0.audioDeleted && $0.text.isEmpty }
        for clip in pending where !transcribingIds.contains(clip.id) {
            transcribe(clipID: clip.id, insertOnFinish: false)
        }
    }

    /// The widget error action word: route the user to fix the key.
    func handleWidgetErrorAction() {
        widgetState = .idle
        tab = .settings
        showMainWindow?()
    }

    // MARK: - Transcript → clip

    /// Writes a provider result onto a clip, turning the provider's **local** speaker indices
    /// into stored voice ids.
    ///
    /// Local 0 is the microphone track, so it maps straight to you and never needs guessing.
    /// Everyone else on the call gets a freshly minted voice; naming one later can merge it
    /// into a voice you have already met (see `VoiceStore.rename`).
    private func applyTranscript(_ result: TranscriptionResult, toClipAt idx: Int) {
        guard let localTurns = result.turns, !localTurns.isEmpty else {
            clips[idx].turns = nil
            clips[idx].text = result.text.trimmingCharacters(in: .whitespacesAndNewlines)
            return
        }

        var order: [Int] = []
        for t in localTurns where !order.contains(t.speaker) { order.append(t.speaker) }

        let remotes = order.filter { $0 != 0 }
        let minted = voices.mintVoices(count: remotes.count)
        var map: [Int: Int] = [0: Voice.youID]
        for (i, local) in remotes.enumerated() { map[local] = minted[i] }

        clips[idx].turns = localTurns.map {
            Turn(speaker: map[$0.speaker] ?? Voice.youID, at: $0.at, text: $0.text)
        }
        clips[idx].text = clips[idx].flattenedTurns
    }

    /// Asks the on-device recogniser whether any of this clip's new voices is someone already
    /// named, and folds them together when it is confident.
    ///
    /// Nothing runs — and no model is fetched — until there is at least one named voice with a
    /// fingerprint to compare against. Until you have named someone, there is nobody to
    /// recognise.
    private func recogniseVoices(inClip id: UUID) {
        guard let clip = clips.first(where: { $0.id == id }), clip.isConversation, !clip.audioDeleted
        else { return }

        let unknown = clip.speakerIds.filter { $0 != Voice.youID && !(voices.voice($0)?.isNamed ?? false) }
        guard !unknown.isEmpty,
              voices.voices.contains(where: { $0.isNamed && !$0.isYou && $0.embedding != nil })
        else { return }

        Task { [weak self] in
            guard let self else { return }
            // One clip can't have the same person as two different speakers.
            var claimed = Set(clip.speakerIds.compactMap { self.voices.voice($0)?.isNamed == true ? $0 : nil })
            for speaker in unknown {
                guard let current = self.clips.first(where: { $0.id == id }),
                      let embedding = await self.recognizer.embedding(forSpeaker: speaker, in: current),
                      let matched = self.recognizer.match(embedding, against: self.voices.voices),
                      !claimed.contains(matched)
                else { continue }
                claimed.insert(matched)
                self.repointTurns(from: speaker, to: matched)
                self.voices.forget(speaker)          // the minted stand-in is no longer needed
            }
            self.pruneVoices()
        }
    }

    /// Rewrites every turn spoken by `from` so it belongs to `to`, in every clip.
    private func repointTurns(from: Int, to: Int) {
        guard from != to else { return }
        var changed = false
        for i in clips.indices {
            guard var turns = clips[i].turns, turns.contains(where: { $0.speaker == from }) else { continue }
            for j in turns.indices where turns[j].speaker == from { turns[j].speaker = to }
            clips[i].turns = turns
            changed = true
        }
        if changed { persist() }
    }

    /// Drops voice profiles no clip refers to any more (a retry mints a new set).
    private func pruneVoices() {
        voices.prune(keeping: Set(clips.flatMap { $0.turns ?? [] }.map(\.speaker)))
    }

    // MARK: - Timers

    private func startTick() {
        stopTick()
        tickTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.elapsed += 1 }
        }
    }
    private func stopTick() { tickTimer?.invalidate(); tickTimer = nil }

    private func scheduleToastDismiss() {
        toastTimer?.invalidate()
        toastTimer = Timer.scheduledTimer(withTimeInterval: 3.2, repeats: false) { [weak self] _ in
            Task { @MainActor in self?.toast = nil }
        }
    }
    private func clearErrorToast() { if case .error = widgetState { widgetState = .idle } }

    // MARK: - Playback

    /// Where the playhead sits in a clip, 0…1. Survives pausing and selection changes.
    func progress(for id: UUID) -> Double { progressByClip[id] ?? 0 }

    func play(_ clip: Clip) {
        if playingId == clip.id { player.pause(); playingId = nil; return }
        guard !clip.audioDeleted else {
            toast = Toast(message: "That audio was cleared by retention. Transcript stays.")
            scheduleToastDismiss()
            return
        }
        player.play(url: Persistence.shared.url(forAudio: clip.audioFileName),
                    from: progress(for: clip.id))
        playingId = clip.id
    }

    /// Moves the playhead, whether or not the clip is currently playing — the scrubber works
    /// on a stopped clip too.
    func seek(_ clip: Clip, to fraction: Double) {
        let f = max(0, min(1, fraction))
        progressByClip[clip.id] = f
        if playingId == clip.id { player.seek(to: f) }
    }

    /// Clicking a turn while reading seeks to it and plays.
    func playTurn(_ clip: Clip, at seconds: TimeInterval) {
        guard clip.seconds > 0 else { return }
        let f = min(1, max(0, seconds / Double(clip.seconds)))
        if playingId == clip.id {
            seek(clip, to: f)
        } else {
            progressByClip[clip.id] = f
            play(clip)
        }
    }

    /// The turn the playhead is inside, for the playback highlight. Nil when nothing plays.
    func activeTurnIndex(in clip: Clip) -> Int? {
        guard playingId == clip.id, let turns = clip.turns, clip.seconds > 0 else { return nil }
        let now = progress(for: clip.id) * Double(clip.seconds)
        var active: Int?
        for (i, t) in turns.enumerated() where t.at <= now { active = i }
        return active
    }

    func togglePlaySelected() { if let c = selectedClip { play(c) } }

    // MARK: - Voices

    /// Names a voice from the transcript it was heard in. Every turn by that voice, in every
    /// clip, updates at once.
    func renameVoice(_ id: Int, to name: String, from clip: Clip?) {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, id != Voice.youID else { return }

        let resolved = voices.rename(id, to: trimmed)
        if resolved != id {
            // Merged into a voice already known by that name — repoint every turn.
            repointTurns(from: id, to: resolved)
        }

        if let clip, !clip.audioDeleted {
            let clipID = clip.id
            // Keep two seconds of this voice from the recording it was named in, so it can be
            // played back later to confirm the match.
            if let at = clips.first(where: { $0.id == clipID })?
                .turns?.first(where: { $0.speaker == resolved })?.at {
                voices.captureSample(for: resolved,
                                     from: Persistence.shared.url(forAudio: clip.audioFileName), at: at)
            }
            // And a fingerprint, so the next recording can recognise them without being told.
            Task { [weak self] in
                guard let self,
                      let current = self.clips.first(where: { $0.id == clipID }),
                      let embedding = await self.recognizer.embedding(forSpeaker: resolved, in: current)
                else { return }
                self.voices.setEmbedding(embedding, for: resolved)
            }
        }

        toast = Toast(message: "Saved. I'll know that voice next time.")
        scheduleToastDismiss()
    }

    func forgetVoice(_ id: Int) {
        guard id != Voice.youID else { return }
        if playingVoiceId == id { samplePlayer.stop(); playingVoiceId = nil }
        voices.forget(id)
    }

    /// Plays a named voice's two-second sample in Settings. Inert on an unnamed voice.
    func toggleVoiceSample(_ id: Int) {
        if playingVoiceId == id { samplePlayer.stop(); playingVoiceId = nil; return }
        guard let url = voices.sampleURL(for: id) else { return }
        samplePlayer.play(url: url)
        playingVoiceId = id
    }

    // MARK: - Clip actions

    var selectedClip: Clip? { clips.first(where: { $0.id == selectedId }) }
    var todayClips: [Clip] { clips.filter { $0.isToday } }

    /// The Library list under the current filter chip.
    var filteredClips: [Clip] { clips.filter { libraryFilter.matches($0) } }

    /// Switching filters keeps the selected clip when it survives the change, otherwise takes
    /// the first one, and always leaves edit mode.
    func setFilter(_ filter: LibraryFilter) {
        guard filter != libraryFilter else { return }
        libraryFilter = filter
        editingTranscript = false
        let list = filteredClips
        if let id = selectedId, list.contains(where: { $0.id == id }) { return }
        selectedId = list.first?.id
    }

    func openClip(_ id: UUID) { selectedId = id; editingTranscript = false; tab = .library }

    /// One Copy button, no variants: a meeting copies as labelled blocks, a note copies bare.
    /// Confirmation is the calling button's own state, not a toast — see `EditorPane.copyTapped`
    /// and `ClipRowView.copyTapped`.
    func copy(_ clip: Clip) {
        TextInserter.copyToClipboard(clip.copyText(voices: voices.voices))
    }

    func copySelected() {
        guard let c = selectedClip else { return }
        copy(c)
    }

    /// Confirmation is the Save changes button's own state, not a toast — see
    /// `EditorPane.saveTapped`.
    func saveEdit(_ text: String) {
        guard let idx = clips.firstIndex(where: { $0.id == selectedId }) else { return }
        clips[idx].text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        persist()
    }

    /// Commits edited conversation turns. Speaker and timestamp are untouched — they belong to
    /// the audio — so only the text of each turn comes back. Confirmation is the Done editing
    /// button's own label change, not a toast.
    func saveTurns(_ texts: [String]) {
        guard let idx = clips.firstIndex(where: { $0.id == selectedId }),
              var turns = clips[idx].turns else { return }
        for i in turns.indices where i < texts.count {
            turns[i].text = texts[i].trimmingCharacters(in: .whitespacesAndNewlines)
        }
        clips[idx].turns = turns
        clips[idx].text = clips[idx].flattenedTurns
        persist()
    }

    func deleteSelected() {
        guard let id = selectedId, let idx = clips.firstIndex(where: { $0.id == id }) else { return }
        let clip = clips[idx]
        if playingId == id { player.stop(); playingId = nil }
        Persistence.shared.deleteAudio(fileName: clip.audioFileName)
        clips.remove(at: idx)
        progressByClip[id] = nil
        editingTranscript = false
        selectedId = filteredClips.first?.id
        persist()
        pruneVoices()
        toast = Toast(message: "Clip and audio deleted.")
        scheduleToastDismiss()
    }

    func fixLast() {
        tab = .library
        selectedId = clips.first?.id
        toast = nil
        showMainWindow?()
    }

    // MARK: - Onboarding

    static let onboardingLastStep = 3   // four steps: 0…3

    func onboardingNext() {
        if onboardingStep >= Self.onboardingLastStep {
            finishOnboarding()
        } else {
            onboardingStep += 1
        }
    }
    func onboardingBack() {
        if onboardingStep == 0 { finishOnboarding() }   // "Skip all this"
        else { onboardingStep -= 1 }
    }
    private func finishOnboarding() {
        Preferences.onboarded = true
        showingOnboarding = false
        onboardingStep = 0
    }
    func replayOnboarding() { onboardingStep = 0; showingOnboarding = true }

    // MARK: - Retention sweep

    func sweepRetention() {
        guard let days = retention.days else { return }   // Forever: never sweep
        let cutoff = Calendar.current.date(byAdding: .day, value: -days, to: Date()) ?? Date()
        var changed = false
        for i in clips.indices where !clips[i].audioDeleted && clips[i].createdAt < cutoff {
            Persistence.shared.deleteAudio(fileName: clips[i].audioFileName)
            clips[i].audioDeleted = true      // transcript stays
            changed = true
        }
        if changed { persist() }
    }

    // MARK: - Derived values for the UI

    /// The macOS account's first name — the default greeting name.
    var systemFirstName: String {
        let full = NSFullUserName().trimmingCharacters(in: .whitespaces)
        let first = full.split(separator: " ").first.map(String.init) ?? full
        return first.isEmpty ? NSUserName() : first
    }

    /// What the greeting calls you: your chosen name, else the macOS account first name.
    var userFirstName: String {
        let chosen = displayName.trimmingCharacters(in: .whitespaces)
        return chosen.isEmpty ? systemFirstName : chosen
    }

    var greeting: String {
        let h = Calendar.current.component(.hour, from: Date())
        let part = h < 5 ? "Still up" : h < 12 ? "Good morning" : h < 18 ? "Good afternoon" : "Good evening"
        return "\(part), \(userFirstName)."
    }
    var subline: String { "\(todayClips.count) recordings today." }

    var totalMB: Double { Double(Persistence.shared.totalAudioBytes()) / 1_000_000 }
    var storageFraction: Double { min(1.0, totalMB / 12) }   // 12 MB meter, per the reference
    var storageLabel: String { String(format: "%.1f MB · %d clips", totalMB, clips.count) }

    // MARK: Dynamic insights (all derived from real clips)

    /// Words dictated today = sum of word counts across today's clips. Updates live as you
    /// dictate, edit, or delete.
    var wordsToday: Int { todayClips.reduce(0) { $0 + $1.wordCount } }

    /// Minutes of typing avoided today, at an assumed typing speed. (Speaking rate `wpm`
    /// is shown in the captions.)
    let assumedTypingWPM = 41
    var minutesSaved: String { "\(Int((Double(wordsToday) / Double(assumedTypingWPM)).rounded())) min" }

    var wordsTodayLabel: String {
        let f = NumberFormatter(); f.numberStyle = .decimal
        return f.string(from: NSNumber(value: wordsToday)) ?? "\(wordsToday)"
    }

    /// One day of the Receipts chart: the bar's height, and the detail behind it on hover.
    struct DayWords: Identifiable {
        let id = UUID()
        let label: String
        let words: Int
        let recordings: Int
        let meetings: Int
        let longest: Int          // seconds of the day's longest single take

        /// `{n} min of typing avoided`, at the assumed typing speed.
        func minutesSaved(typingWPM: Int) -> Int {
            Int((Double(words) / Double(typingWPM)).rounded())
        }

        /// `6 recordings` — with ` · 2 meetings` appended only when the day had any.
        var recordingsLine: String {
            let base = "\(recordings) recording\(recordings == 1 ? "" : "s")"
            return meetings > 0 ? base + " · \(meetings) meeting\(meetings == 1 ? "" : "s")" : base
        }

        var longestLine: String { "Longest \(Clip.formatSeconds(longest))" }
    }

    /// The last 7 days (oldest → today).
    var weekWords: [DayWords] {
        let cal = Calendar.current
        let fmt = DateFormatter(); fmt.dateFormat = "EEE"   // Mon, Tue, …
        let today = cal.startOfDay(for: Date())
        return (0..<7).reversed().map { back in
            let day = cal.date(byAdding: .day, value: -back, to: today)!
            let onDay = clips.filter { cal.isDate($0.createdAt, inSameDayAs: day) }
            return DayWords(
                label: fmt.string(from: day),
                words: onDay.reduce(0) { $0 + $1.wordCount },
                recordings: onDay.count,
                meetings: onDay.filter(\.isConversation).count,
                longest: onDay.map(\.seconds).max() ?? 0
            )
        }
    }

    /// Exposed so the Receipts panel can show the same "typing avoided" figure as Today.
    var typingWPM: Int { assumedTypingWPM }

    /// Caption for the "Saved today" card — the loudest day this week, from real data.
    var weekCaption: String {
        let week = weekWords
        guard let peak = week.max(by: { $0.words < $1.words }), peak.words > 0 else {
            return "No recordings this week yet. The widget's bottom-right."
        }
        if let quiet = week.filter({ $0.words > 0 }).min(by: { $0.words < $1.words }), quiet.words != peak.words {
            return "\(dayName(peak.label)) is your loudest day. \(dayName(quiet.label)) you said \(quiet.words) word\(quiet.words == 1 ? "" : "s")."
        }
        return "\(dayName(peak.label)) is your loudest day so far."
    }

    /// Caption for the Receipts "Words per day" card — your longest single recording.
    var longestCaption: String {
        guard let longest = clips.max(by: { $0.seconds < $1.seconds }) else {
            return "No recordings yet — click the widget and talk."
        }
        return "Your longest single recording was \(Clip.formatSeconds(longest.seconds))."
    }

    private func dayName(_ abbrev: String) -> String {
        switch abbrev {
        case "Mon": return "Monday";    case "Tue": return "Tuesday"
        case "Wed": return "Wednesday"; case "Thu": return "Thursday"
        case "Fri": return "Friday";    case "Sat": return "Saturday"
        default:    return "Sunday"
        }
    }

    func startHotkeys() { hotkeys.setMode(trigger) }

    private func persist() { Persistence.shared.saveClips(clips) }
}
