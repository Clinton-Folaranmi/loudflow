import SwiftUI
import AppKit

enum Tab: String, CaseIterable { case today, library, settings, receipts }

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
    @Published var progress: Double = 0             // 0…1 of the playing clip
    @Published var hoveredId: UUID?
    @Published var flashClipId: UUID?               // drives the editor fGlow when text lands
    @Published var transcribingIds: Set<UUID> = []  // clips currently being (re)transcribed

    // MARK: Feedback
    @Published var toast: Toast?
    @Published var displayName: String { didSet { Preferences.displayName = displayName } }

    // MARK: Key / permissions status
    enum KeyStatus { case missing, saved, checking, rejected }
    @Published var keyStatus: KeyStatus = .missing

    /// Set by the app layer so the model can bring the main window forward.
    var showMainWindow: (() -> Void)?

    // MARK: Plumbing
    private let recorder = AudioRecorder()
    private let player = AudioPlayer()
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
    }

    private func wireUp() {
        player.onProgress = { [weak self] p in self?.progress = p }
        player.onFinish = { [weak self] in self?.playingId = nil; self?.progress = 0 }

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
        let duration = recorder.stop()
        guard let audio = pendingAudio else { widgetState = .idle; return }
        pendingAudio = nil

        let secs = max(1, Int(duration.rounded()))
        let size = Persistence.shared.fileSize(fileName: audio.fileName)

        // The audio is a first-class citizen: persist the clip immediately, even before
        // (or if we never get) a transcript. It starts life pending.
        let clip = Clip(createdAt: Date(), seconds: secs, sizeBytes: size,
                        text: "", audioFileName: audio.fileName, status: .pending)
        clips.insert(clip, at: 0)
        persist()

        guard hasKey else {
            widgetState = .error(.missingKey)
            return
        }
        widgetState = .transcribing
        transcribe(clipID: clip.id, insertOnFinish: true)
    }

    /// Transcribe a clip. `insertOnFinish` = true only for a fresh recording (paste into the
    /// focused field + widget feedback); a retry from the library just fills in the transcript.
    private func transcribe(clipID: UUID, insertOnFinish: Bool) {
        guard let clip = clips.first(where: { $0.id == clipID }) else { return }
        let url = Persistence.shared.url(forAudio: clip.audioFileName)
        transcribingIds.insert(clipID)
        Task {
            do {
                let raw = try await transcriber.transcribe(url)
                await MainActor.run { self.finishTranscription(clipID: clipID, raw: raw, insert: insertOnFinish) }
            } catch let e as TranscriberError {
                await MainActor.run { self.handleTranscribeFailure(clipID: clipID, error: e, insert: insertOnFinish) }
            } catch {
                await MainActor.run { self.handleTranscribeFailure(clipID: clipID, error: .network, insert: insertOnFinish) }
            }
        }
    }

    private func finishTranscription(clipID: UUID, raw: String, insert: Bool) {
        transcribingIds.remove(clipID)
        // The ENTIRE post-processing pipeline: optional punctuation. No rephrasing, ever.
        let text = options.punct ? Self.punctuate(raw) : raw.trimmingCharacters(in: .whitespacesAndNewlines)

        guard let idx = clips.firstIndex(where: { $0.id == clipID }) else { return }
        clips[idx].text = text
        clips[idx].status = .done
        persist()

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

    // MARK: - Punctuation (the only text transform in the app)

    static func punctuate(_ raw: String) -> String {
        var s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let first = s.first else { return s }
        s.replaceSubrange(s.startIndex...s.startIndex, with: String(first).uppercased())
        if let last = s.last, !".!?".contains(last) { s.append(".") }
        return s
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

    func play(_ clip: Clip) {
        if playingId == clip.id { player.stop(); playingId = nil; progress = 0; return }
        guard !clip.audioDeleted else {
            toast = Toast(message: "That audio was cleared by retention. Transcript stays.")
            scheduleToastDismiss()
            return
        }
        player.play(url: Persistence.shared.url(forAudio: clip.audioFileName))
        playingId = clip.id
        progress = 0
    }

    func togglePlaySelected() { if let c = selectedClip { play(c) } }

    // MARK: - Clip actions

    var selectedClip: Clip? { clips.first(where: { $0.id == selectedId }) }
    var todayClips: [Clip] { clips.filter { $0.isToday } }

    func openClip(_ id: UUID) { selectedId = id; tab = .library }

    func copy(_ clip: Clip) {
        TextInserter.copyToClipboard(clip.text)
        toast = Toast(message: "Copied that transcript.")
        scheduleToastDismiss()
    }

    func copySelected() {
        guard let c = selectedClip else { return }
        TextInserter.copyToClipboard(c.text)
        toast = Toast(message: "Copied.")
        scheduleToastDismiss()
    }

    func saveEdit(_ text: String) {
        guard let idx = clips.firstIndex(where: { $0.id == selectedId }) else { return }
        clips[idx].text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        persist()
        toast = Toast(message: "Fixed. Audio untouched.")
        scheduleToastDismiss()
    }

    func deleteSelected() {
        guard let id = selectedId, let idx = clips.firstIndex(where: { $0.id == id }) else { return }
        let clip = clips[idx]
        if playingId == id { player.stop(); playingId = nil; progress = 0 }
        Persistence.shared.deleteAudio(fileName: clip.audioFileName)
        clips.remove(at: idx)
        selectedId = clips.first?.id
        persist()
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
    private let assumedTypingWPM = 41
    var minutesSaved: String { "\(Int((Double(wordsToday) / Double(assumedTypingWPM)).rounded())) min" }

    var wordsTodayLabel: String {
        let f = NumberFormatter(); f.numberStyle = .decimal
        return f.string(from: NSNumber(value: wordsToday)) ?? "\(wordsToday)"
    }

    /// Word totals for the last 7 days (oldest → today), each with its weekday label.
    struct DayWords: Identifiable { let id = UUID(); let label: String; let words: Int }
    var weekWords: [DayWords] {
        let cal = Calendar.current
        let fmt = DateFormatter(); fmt.dateFormat = "EEE"   // Mon, Tue, …
        let today = cal.startOfDay(for: Date())
        return (0..<7).reversed().map { back in
            let day = cal.date(byAdding: .day, value: -back, to: today)!
            let words = clips
                .filter { cal.isDate($0.createdAt, inSameDayAs: day) }
                .reduce(0) { $0 + $1.wordCount }
            return DayWords(label: fmt.string(from: day), words: words)
        }
    }

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
