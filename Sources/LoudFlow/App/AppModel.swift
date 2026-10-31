import SwiftUI
import AppKit
import Combine

enum Tab: String, CaseIterable { case today, library, settings, receipts }

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
}

@MainActor
final class AppModel: ObservableObject {

    @Published var showingOnboarding: Bool
    @Published var onboardingStep: Int = 0
    @Published var tab: Tab = .today

    @Published var trigger: TriggerMode { didSet { Preferences.trigger = trigger; hotkeys.setMode(trigger) } }
    @Published var retention: Retention { didSet { Preferences.retention = retention } }
    @Published var options: DictationOptions { didSet { Preferences.options = options } }
    @Published var provider: Provider { didSet { Preferences.provider = provider; rebuildTranscriber(); refreshKeyStatus() } }

    @Published var widgetState: WidgetState = .idle
    @Published var elapsed: Int = 0

    @Published var clips: [Clip]
    @Published var selectedId: UUID?
    @Published var playingId: UUID?
    let playback = PlaybackProgress()
    @Published var libraryFilter: LibraryFilter = .all
    @Published var librarySearch = ""
    @Published var playbackRate: Float { didSet { Preferences.playbackRate = playbackRate; player.setRate(playbackRate) } }
    @Published var editingTranscript = false
    @Published var hoveredId: UUID?
    @Published var flashClipId: UUID?
    @Published var transcribingIds: Set<UUID> = []

    @Published var toast: Toast?
    @Published var displayName: String {
        didSet {
            Preferences.displayName = displayName
            voices.rename(Voice.youID, to: userFirstName)
        }
    }

    let voices = VoiceStore()
    let recognizer = VoiceRecognizer()
    @Published var playingVoiceId: Int?

    enum KeyStatus: Equatable { case missing, saved, checking, rejected }
    @Published var keyStatus: KeyStatus = .missing

    var showMainWindow: (() -> Void)?

    private let recorder = AudioRecorder()
    private let player = AudioPlayer()
    private let samplePlayer = AudioPlayer()
    private var voiceObserver: AnyCancellable?
    private var recognizerObserver: AnyCancellable?
    private let hotkeys = HotkeyManager()
    private let queue = TranscriptionQueue()
    private var transcriber: Transcriber
    private var tickTimer: Timer?
    private var toastTimer: Timer?
    private var queuedRevertTimer: Timer?

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
        self.playbackRate = Preferences.playbackRate
        self.transcriber = TranscriberFactory.make(provider: prov)
        self.selectedId = clips.first?.id
        loadSuggestions()

        voices.rename(Voice.youID, to: userFirstName)
        Preferences.removeRetiredKeys()

        refreshKeyStatus()
        wireUp()
        sweepRetention()
        pruneVoices()
        Persistence.shared.removeScratchRecordings()
        refreshStorage()
    }

    private func wireUp() {
        voiceObserver = voices.objectWillChange.sink { [weak self] _ in self?.objectWillChange.send() }
        recognizerObserver = recognizer.objectWillChange.sink { [weak self] _ in self?.objectWillChange.send() }

        player.onProgress = { [weak self] p in
            guard let self, let id = self.playingId else { return }
            self.playback.set(p, for: id)
        }
        player.onFinish = { [weak self] in self?.playingId = nil }

        samplePlayer.onFinish = { [weak self] in self?.playingVoiceId = nil }

        hotkeys.onHoldStart = { [weak self] in self?.startRecording() }
        hotkeys.onHoldStop = { [weak self] in self?.stopRecording() }
        hotkeys.onDoubleTapToggle = { [weak self] in self?.toggleRecording() }
        hotkeys.setMode(trigger)

        queue.onNetworkRestored = { [weak self] in self?.retryPending() }
    }

    var hasKey: Bool { Keychain.key(for: provider) != nil }

    func refreshKeyStatus() { keyStatus = hasKey ? .saved : .missing }

    func saveKey(_ raw: String) {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        Keychain.setKey(trimmed, for: provider)
        rebuildTranscriber()
        keyStatus = trimmed.isEmpty ? .missing : .saved
        if !trimmed.isEmpty { retryPending() }
    }

    func clearKey() {
        Keychain.clearKey(for: provider)
        rebuildTranscriber()
        keyStatus = .missing
    }

    func validateKey() {
        guard hasKey else { keyStatus = .missing; return }
        keyStatus = .checking
        Task {
            let ok = await transcriber.validateKey()
            await MainActor.run { self.keyStatus = ok ? .saved : .rejected }
        }
    }

    private func rebuildTranscriber() { transcriber = TranscriberFactory.make(provider: provider) }

    func toggleRecording() {
        if case .recording = widgetState { stopRecording() } else { startRecording() }
    }

    func cancelRecording() {
        stopTick()
        recorder.cancel()
        pendingAudio = nil
        elapsed = 0
        widgetState = .idle
        toast = Toast(message: "Discarded.")
        scheduleToastDismiss()
    }

    func selectTrigger(_ mode: TriggerMode) {
        trigger = mode
        if mode != .click { hotkeys.requestPermissionAndInstall() }
    }

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
                    Earcons.recordStart()
                    try self.recorder.start(to: target.url)
                    self.pendingAudio = target
                    self.widgetState = .recording
                    self.elapsed = 0
                    self.startTick()
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
        widgetState = .transcribing
        Task { await finishRecording() }
    }

    private func finishRecording() async {
        let outcome = await recorder.stop()
        guard let audio = pendingAudio else { widgetState = .idle; return }
        pendingAudio = nil

        let secs = max(1, Int(outcome.duration.rounded()))
        let size = Persistence.shared.fileSize(fileName: audio.fileName)

        var clip = Clip(createdAt: Date(), seconds: secs, sizeBytes: size,
                        text: "", audioFileName: audio.fileName,
                        twoTrack: outcome.twoTrack, status: .pending)
        if outcome.callAudioMissed { clip.callAudioMissed = true }
        clips.insert(clip, at: 0)
        persist()
        refreshStorage()

        guard hasKey else {
            widgetState = .error(.missingKey)
            return
        }
        transcribe(clipID: clip.id, insertOnFinish: true)
    }

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

        applyTranscript(result, toClipAt: idx)
        clips[idx].status = .done
        persist()
        let voiceWork = recogniseVoices(inClip: clipID)

        let text = clips[idx].text
        Earcons.transcriptLanded()

        guard insert else {
            toast = Toast(message: "Transcribed.")
            scheduleToastDismiss()
            return
        }

        var didType = false
        if options.insert {
            didType = TextInserter.insert(text)
            if !didType { Permissions.nudgeAccessibility() }
        } else {
            TextInserter.copyToClipboard(text)
        }

        // Voice learning reads the audio, so it's cleared once that's done.
        if !options.keep {
            Task { [weak self] in
                await voiceWork?.value
                self?.clearAudio(of: clipID)
            }
        }

        selectedId = clipID
        flashClipId = clipID
        widgetState = .idle
        let message: String
        if options.insert && text.isEmpty {
            message = "Transcription was empty."
        } else if options.insert && !didType {
            message = Permissions.pastePermissionMessage
        } else if clips[idx].isConversation && clips[idx].callAudioMissed == true {
            message = "Call audio wasn't recorded. The clip in Library says how to fix it."
        } else {
            message = options.insert ? "Recording pasted." : "Copied."
        }
        toast = Toast(message: message)
        scheduleToastDismiss()

        DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) { [weak self] in
            if self?.flashClipId == clipID { self?.flashClipId = nil }
        }
    }

    private func handleTranscribeFailure(clipID: UUID, error: TranscriberError, insert: Bool) {
        transcribingIds.remove(clipID)
        if let idx = clips.firstIndex(where: { $0.id == clipID }) { clips[idx].status = .pending; persist() }
        switch error {
        case .network, .server, .decoding: queue.enqueue(clipID)
        default: break
        }

        guard insert else {
            let msg: String
            switch error {
            case .network, .server, .decoding: msg = "Still couldn't reach the service. Try again in a bit."
            case .missingKey:                  msg = "Add a transcription key in Settings."
            case .auth:                        keyStatus = .rejected; msg = "That key was rejected."
            case .credit:                      msg = "Transcription account is out of credit."
            case .tooLarge:                    msg = tooLargeMessage
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
        case .tooLarge:   widgetState = .error(.tooLarge)
        }
    }

    private func clearAudio(of clipID: UUID) {
        guard let idx = clips.firstIndex(where: { $0.id == clipID }), !clips[idx].audioDeleted else { return }
        if playingId == clipID { player.stop(); playingId = nil }
        Persistence.shared.deleteAudio(fileName: clips[idx].audioFileName)
        clips[idx].audioDeleted = true
        persist()
        refreshStorage()
    }

    private var tooLargeMessage: String {
        provider == .whisper
            ? "Over OpenAI's 25 MB upload limit. Deepgram takes long recordings."
            : "That recording is too large to upload."
    }

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

    func retryPending() {
        guard hasKey else { return }
        let pending = clips.filter { $0.status == .pending && !$0.audioDeleted && $0.text.isEmpty }
        for clip in pending where !transcribingIds.contains(clip.id) {
            transcribe(clipID: clip.id, insertOnFinish: false)
        }
    }

    func handleWidgetErrorAction() {
        widgetState = .idle
        tab = .settings
        showMainWindow?()
    }

    private func applyTranscript(_ result: TranscriptionResult, toClipAt idx: Int) {
        guard let localTurns = result.turns, !localTurns.isEmpty else {
            clips[idx].turns = nil
            clips[idx].text = result.text.trimmingCharacters(in: .whitespacesAndNewlines)
            return
        }

        var order: [Int] = []
        for t in localTurns where !order.contains(t.speaker) { order.append(t.speaker) }

        let twoTrack = clips[idx].twoTrack

        // Only a two-track recording proves local speaker 0 came from the mic.
        let toMint = twoTrack ? order.filter { $0 != 0 } : order
        let minted = voices.mintVoices(count: toMint.count)
        var map: [Int: Int] = twoTrack ? [0: Voice.youID] : [:]
        for (i, local) in toMint.enumerated() { map[local] = minted[i] }

        clips[idx].turns = localTurns.map {
            Turn(speaker: map[$0.speaker] ?? Voice.youID, at: $0.at, text: $0.text, end: $0.end)
        }
        clips[idx].text = clips[idx].flattenedTurns
    }

    @discardableResult
    private func recogniseVoices(inClip id: UUID) -> Task<Void, Never>? {
        guard let clip = clips.first(where: { $0.id == id }), !clip.audioDeleted else { return nil }
        guard clip.isConversation else { return learnYourVoice(fromSolo: clip) }

        return Task { [weak self] in
            guard let self else { return }
            if clip.twoTrack, clip.speakerIds.contains(Voice.youID) {
                await self.reinforce(Voice.youID, in: id, confirmed: false)
            } else if self.voices.voice(Voice.youID)?.embedding == nil {
                await self.bootstrapYourVoice()
            }
            await self.suggestVoices(inClip: id)
        }
    }

    // Matches are suggestions; a person is never assigned automatically.
    private func suggestVoices(inClip id: UUID) async {
        guard let clip = clips.first(where: { $0.id == id }), clip.isConversation, !clip.audioDeleted
        else { return }

        // Only a mic-only recording can still have you hiding under a "Speaker" label.
        let youOpen = !clip.speakerIds.contains(Voice.youID)
        let unknown = clip.speakerIds.filter {
            $0 != Voice.youID && !(voices.voice($0)?.isNamed ?? false)
                && !rejectedSuggestions.contains(Self.suggestionKey(id, $0))
        }
        let anyKnown = voices.voices.contains { $0.isNamed && $0.embedding != nil && (youOpen || !$0.isYou) }
        guard !unknown.isEmpty, anyKnown else { return }

        var proposals: [(speaker: Int, voice: Int, distance: Float)] = []
        for speaker in unknown {
            guard let current = clips.first(where: { $0.id == id }),
                  let embedding = await recognizer.embedding(forSpeaker: speaker, in: current),
                  let matched = recognizer.match(embedding, against: voices.voices, includingYou: youOpen)
            else { continue }
            proposals.append((speaker, matched.id, matched.distance))
        }

        // Closest pairs first, so a weaker match can't take a voice from a stronger one.
        var claimed = Set(clip.speakerIds.filter { voices.voice($0)?.isNamed == true })
        var found: [Int: Int] = [:]
        for p in proposals.sorted(by: { $0.distance < $1.distance })
        where !claimed.contains(p.voice) && found[p.speaker] == nil {
            claimed.insert(p.voice)
            found[p.speaker] = p.voice
        }
        guard !found.isEmpty else { return }
        var forClip = suggestions[id] ?? [:]
        for (speaker, matched) in found { forClip[speaker] = matched }
        suggestions[id] = forClip
    }

    // Solo dictation is almost always you, so it teaches LoudFlow your voice for meetings.
    private static let soloSamplesWanted = 12

    private func learnYourVoice(fromSolo clip: Clip) -> Task<Void, Never>? {
        guard let you = voices.voice(Voice.youID),
              (you.embeddingCount ?? 0) < Self.soloSamplesWanted,
              you.embedding != nil || clips.contains(where: \.isConversation)
        else { return nil }
        return Task { [weak self] in
            guard let self,
                  let current = self.clips.first(where: { $0.id == clip.id }),
                  let embedding = await self.recognizer.embedding(ofSoloClip: current)
            else { return }
            self.learnYou(embedding, confirmed: false)
        }
    }

    private func bootstrapYourVoice() async {
        let recent = clips
            .filter { !$0.isConversation && !$0.audioDeleted && $0.status == .done && $0.seconds >= 3 }
            .prefix(3)
        for clip in recent {
            if let embedding = await recognizer.embedding(ofSoloClip: clip) {
                learnYou(embedding, confirmed: false)
            }
        }
    }

    private func learnYou(_ embedding: [Float], confirmed: Bool) {
        guard let you = voices.voice(Voice.youID) else { return }
        // A settled profile ignores an unconfirmed sample that doesn't sound like you.
        if !confirmed, (you.embeddingCount ?? 0) >= 3, !recognizer.isConsistent(embedding, with: you) { return }
        voices.learn(embedding, for: Voice.youID)
    }

    private func reinforce(_ voice: Int, in clipID: UUID, confirmed: Bool) async {
        guard let clip = clips.first(where: { $0.id == clipID }), !clip.audioDeleted,
              let embedding = await recognizer.embedding(forSpeaker: voice, in: clip)
        else { return }
        if voice == Voice.youID {
            learnYou(embedding, confirmed: confirmed)
        } else {
            voices.learn(embedding, for: voice)
        }
    }

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

    private func pruneVoices() {
        voices.prune(keeping: Set(clips.flatMap { $0.turns ?? [] }.map(\.speaker)))
    }

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

    func progress(for id: UUID) -> Double { playback.fraction(for: id) }

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

    func seek(_ clip: Clip, to fraction: Double) {
        let f = max(0, min(1, fraction))
        playback.set(f, for: clip.id)
        if playingId == clip.id { player.seek(to: f) }
    }

    func playTurn(_ clip: Clip, at seconds: TimeInterval) {
        guard clip.seconds > 0 else { return }
        let f = min(1, max(0, seconds / Double(clip.seconds)))
        if playingId == clip.id {
            seek(clip, to: f)
        } else {
            playback.set(f, for: clip.id)
            play(clip)
        }
    }

    func activeTurnIndex(in clip: Clip) -> Int? {
        guard playingId == clip.id, let turns = clip.turns, clip.seconds > 0 else { return nil }
        let now = progress(for: clip.id) * Double(clip.seconds)
        var active: Int?
        for (i, t) in turns.enumerated() where t.at <= now { active = i }
        return active
    }

    func togglePlaySelected() { if let c = selectedClip { play(c) } }

    func renameVoice(_ id: Int, to name: String, from clip: Clip?) {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, id != Voice.youID else { return }
        guard !isYouName(trimmed) else {
            toast = Toast(message: "That's your own name — a different voice can't share it.")
            scheduleToastDismiss()
            return
        }

        let resolved = voices.rename(id, to: trimmed)
        if resolved != id {
            repointTurns(from: id, to: resolved)
        }

        if let clip, !clip.audioDeleted {
            captureSampleAndEmbedding(for: resolved, in: clip.id)
        }

        toast = Toast(message: "Saved. I'll know that voice next time.")
        scheduleToastDismiss()
    }

    func forgetVoice(_ id: Int) {
        guard id != Voice.youID else { return }
        if playingVoiceId == id { samplePlayer.stop(); playingVoiceId = nil }
        voices.forget(id)
    }

    private func isYouName(_ name: String) -> Bool {
        let key = name.trimmingCharacters(in: .whitespaces).lowercased()
        guard !key.isEmpty else { return false }
        return (voices.voice(Voice.youID)?.name ?? "").trimmingCharacters(in: .whitespaces).lowercased() == key
    }

    private func captureSampleAndEmbedding(for voice: Int, in clipID: UUID) {
        guard let clip = clips.first(where: { $0.id == clipID }), !clip.audioDeleted else { return }
        let longest = clip.turns?.filter { $0.speaker == voice }.max { $0.text.count < $1.text.count }
        if let at = longest?.at {
            voices.captureSample(for: voice, from: Persistence.shared.url(forAudio: clip.audioFileName), at: at)
        }
        Task { [weak self] in await self?.reinforce(voice, in: clipID, confirmed: true) }
    }

    func reassignSpeaker(_ speaker: Int, in clipID: UUID, to voice: Int, learn: Bool = true) {
        guard speaker != voice,
              let idx = clips.firstIndex(where: { $0.id == clipID }),
              var turns = clips[idx].turns, turns.contains(where: { $0.speaker == speaker })
        else { return }
        for i in turns.indices where turns[i].speaker == speaker { turns[i].speaker = voice }
        clips[idx].turns = turns
        clips[idx].text = clips[idx].flattenedTurns
        suggestions[clipID]?[speaker] = nil
        persist()
        pruneVoices()
        // Picking a named voice confirms it, so this recording sharpens that voice's profile.
        if learn, voices.voice(voice)?.isNamed == true {
            Task { [weak self] in await self?.reinforce(voice, in: clipID, confirmed: true) }
        }
    }

    @discardableResult
    func detachSpeaker(_ speaker: Int, in clipID: UUID) -> Int? {
        guard let idx = clips.firstIndex(where: { $0.id == clipID }),
              var turns = clips[idx].turns, turns.contains(where: { $0.speaker == speaker })
        else { return nil }
        let fresh = voices.mintVoices(count: 1)[0]
        for i in turns.indices where turns[i].speaker == speaker { turns[i].speaker = fresh }
        clips[idx].turns = turns
        clips[idx].text = clips[idx].flattenedTurns
        suggestions[clipID]?[speaker] = nil
        persist()
        pruneVoices()
        return fresh
    }

    func nameSpeaker(_ speaker: Int, in clipID: UUID, to name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, speaker != Voice.youID else { return }
        guard !isYouName(trimmed) else {
            toast = Toast(message: "That's your own name — use “You” instead if this really is you.")
            scheduleToastDismiss()
            return
        }

        suggestions[clipID]?[speaker] = nil
        let sharedElsewhere = clips.contains { c in
            c.id != clipID && (c.turns ?? []).contains { $0.speaker == speaker }
        }
        // A transcript correction must not rename this voice in other clips.
        let target = sharedElsewhere ? (detachSpeaker(speaker, in: clipID) ?? speaker) : speaker

        let resolved = voices.rename(target, to: trimmed)
        if resolved != target {
            reassignSpeaker(target, in: clipID, to: resolved, learn: false)
        }
        captureSampleAndEmbedding(for: resolved, in: clipID)

        toast = Toast(message: "Saved. I'll know that voice next time.")
        scheduleToastDismiss()
    }

    @Published var suggestions: [UUID: [Int: Int]] = [:] { didSet { saveSuggestions() } }

    private var rejectedSuggestions: Set<String> = [] { didSet { saveSuggestions() } }

    private func loadSuggestions() {
        let saved = Persistence.shared.loadSuggestions()
        let known = Set(clips.map(\.id))
        var loaded: [UUID: [Int: Int]] = [:]
        for (key, bySpeaker) in saved.suggestions {
            guard let id = UUID(uuidString: key), known.contains(id) else { continue }
            loaded[id] = Dictionary(uniqueKeysWithValues: bySpeaker.compactMap { speaker, voice in
                Int(speaker).map { ($0, voice) }
            })
        }
        suggestions = loaded
        rejectedSuggestions = Set(saved.rejected)
    }

    private func saveSuggestions() {
        let byClip = Dictionary(uniqueKeysWithValues: suggestions.compactMap { id, bySpeaker in
            bySpeaker.isEmpty ? nil : (id.uuidString, Dictionary(uniqueKeysWithValues: bySpeaker.map { (String($0), $1) }))
        })
        Persistence.shared.saveSuggestions(.init(suggestions: byClip, rejected: rejectedSuggestions.sorted()))
    }

    private static func suggestionKey(_ clipID: UUID, _ speaker: Int) -> String { "\(clipID):\(speaker)" }

    func acceptSuggestion(for speaker: Int, in clipID: UUID) {
        guard let voice = suggestions[clipID]?[speaker] else { return }
        reassignSpeaker(speaker, in: clipID, to: voice)
        suggestions[clipID]?[speaker] = nil
    }

    func rejectSuggestion(for speaker: Int, in clipID: UUID) {
        rejectedSuggestions.insert(Self.suggestionKey(clipID, speaker))
        suggestions[clipID]?[speaker] = nil
    }

    func toggleVoiceSample(_ id: Int) {
        if playingVoiceId == id { samplePlayer.stop(); playingVoiceId = nil; return }
        guard let url = voices.sampleURL(for: id) else { return }
        samplePlayer.play(url: url)
        playingVoiceId = id
    }

    var selectedClip: Clip? { clips.first(where: { $0.id == selectedId }) }
    var todayClips: [Clip] { clips.filter { $0.isToday } }

    var filteredClips: [Clip] {
        let query = librarySearch.trimmingCharacters(in: .whitespacesAndNewlines)
        return clips.filter { clip in
            guard libraryFilter.matches(clip) else { return false }
            guard !query.isEmpty else { return true }
            let speakers = clip.speakerIds.compactMap { voices.voice($0)?.name }.joined(separator: " ")
            return ((clip.title ?? "") + " " + clip.text + " " + speakers)
                .localizedCaseInsensitiveContains(query)
        }
    }

    func setFilter(_ filter: LibraryFilter) {
        guard filter != libraryFilter else { return }
        libraryFilter = filter
        let list = filteredClips
        if let id = selectedId, list.contains(where: { $0.id == id }) { return }
        editingTranscript = false
        selectedId = list.first?.id
    }

    func setLibrarySearch(_ query: String) {
        librarySearch = query
        let list = filteredClips
        if let id = selectedId, list.contains(where: { $0.id == id }) { return }
        editingTranscript = false
        selectedId = list.first?.id
    }

    func openClip(_ id: UUID) { selectedId = id; editingTranscript = false; tab = .library }

    func renameMeeting(_ id: UUID, to name: String) {
        guard let idx = clips.firstIndex(where: { $0.id == id }),
              clips[idx].isConversation else { return }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let title = trimmed.isEmpty ? nil : trimmed
        guard clips[idx].title != title else { return }
        clips[idx].title = title
        persist()
        if !filteredClips.contains(where: { $0.id == selectedId }) {
            editingTranscript = false
            selectedId = filteredClips.first?.id
        }
    }

    func copy(_ clip: Clip) {
        TextInserter.copyToClipboard(clip.copyText(voices: voices.voices))
    }

    func copySelected() {
        guard let c = selectedClip else { return }
        copy(c)
    }

    func saveEdit(_ text: String, for clipID: UUID) {
        guard let idx = clips.firstIndex(where: { $0.id == clipID }) else { return }
        clips[idx].text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        persist()
    }

    func saveTurns(_ texts: [String], for clipID: UUID) {
        guard let idx = clips.firstIndex(where: { $0.id == clipID }),
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
        refreshStorage()
        playback.clear(id)
        suggestions[id] = nil
        editingTranscript = false
        selectedId = filteredClips.first?.id
        persist()
        pruneVoices()
        toast = Toast(message: "Clip and audio deleted.")
        scheduleToastDismiss()
    }

    static let onboardingLastStep = 3

    func onboardingNext() {
        if onboardingStep >= Self.onboardingLastStep {
            finishOnboarding()
        } else {
            onboardingStep += 1
        }
    }
    func onboardingBack() {
        if onboardingStep == 0 { finishOnboarding() }
        else { onboardingStep -= 1 }
    }
    private func finishOnboarding() {
        Preferences.onboarded = true
        showingOnboarding = false
        onboardingStep = 0
    }
    func replayOnboarding() { onboardingStep = 0; showingOnboarding = true }

    func sweepRetention() {
        guard let days = retention.days else { return }
        let cutoff = Calendar.current.date(byAdding: .day, value: -days, to: Date()) ?? Date()
        var changed = false
        for i in clips.indices where !clips[i].audioDeleted && clips[i].createdAt < cutoff {
            Persistence.shared.deleteAudio(fileName: clips[i].audioFileName)
            clips[i].audioDeleted = true
            changed = true
        }
        if changed { persist(); refreshStorage() }
    }

    var systemFirstName: String {
        let full = NSFullUserName().trimmingCharacters(in: .whitespaces)
        let first = full.split(separator: " ").first.map(String.init) ?? full
        return first.isEmpty ? NSUserName() : first
    }

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

    @Published private(set) var audioBytes: Int64 = 0
    private var freeBytes: Int64 = 0

    // Measured when audio is added or removed, never during a redraw.
    func refreshStorage() {
        audioBytes = Persistence.shared.totalAudioBytes()
        freeBytes = Persistence.shared.availableBytes()
    }

    var totalMB: Double { Double(audioBytes) / 1_000_000 }

    // The share of this Mac's remaining space that recordings take up. A sliver stays
    // visible so the meter doesn't read as empty.
    var storageFraction: Double {
        guard audioBytes > 0 else { return 0 }
        let share = Double(audioBytes) / Double(audioBytes + max(0, freeBytes))
        return min(1, max(0.02, share))
    }

    var storageLabel: String {
        "\(ByteCountFormatter.string(fromByteCount: audioBytes, countStyle: .file)) · \(clips.count) clips"
    }

    var wordsToday: Int { todayClips.reduce(0) { $0 + $1.wordCount } }

    let assumedTypingWPM = 41
    var minutesSaved: String { "\(Int((Double(wordsToday) / Double(assumedTypingWPM)).rounded())) min" }

    var wordsTodayLabel: String {
        let f = NumberFormatter(); f.numberStyle = .decimal
        return f.string(from: NSNumber(value: wordsToday)) ?? "\(wordsToday)"
    }

    struct DayWords: Identifiable {
        let id = UUID()
        let label: String
        let words: Int
        let recordings: Int
        let meetings: Int
        let longest: Int

        func minutesSaved(typingWPM: Int) -> Int {
            Int((Double(words) / Double(typingWPM)).rounded())
        }

        var recordingsLine: String {
            let base = "\(recordings) recording\(recordings == 1 ? "" : "s")"
            return meetings > 0 ? base + " · \(meetings) meeting\(meetings == 1 ? "" : "s")" : base
        }

        var longestLine: String { "Longest \(Clip.formatSeconds(longest))" }
    }

    var weekWords: [DayWords] {
        let cal = Calendar.current
        let fmt = DateFormatter(); fmt.dateFormat = "EEE"
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

    var typingWPM: Int { assumedTypingWPM }

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
