# LoudFlow

A personal macOS dictation app. A small always-on-top widget floats over whatever app
you're using. Click it (or hold a key / double-tap Control), talk, and when you stop it
types the **raw transcript** straight into the field your cursor is in. Audio and transcript
are kept locally so you can open the app and fix a mis-heard name or number.

Three things are deliberate:

1. **No tone presets, no rewriting, no LLM cleanup.** Raw transcript plus optional
   punctuation (capitalize the first letter, add a full stop). Nothing else, ever.
2. **No live transcription while recording.** Just a waveform and a timer, then a brief
   "Writing it out…" state, then the text lands.
3. **Clips are stored on this Mac; transcription runs in the cloud** (Deepgram by default).
   This is an accuracy-over-privacy choice made on purpose. Audio is sent to the provider
   with a **zero-retention** request and nothing is kept there. The UI says "kept here,
   transcribed in the cloud" — there is intentionally **no** "never leaves your Mac" claim.

---

## Build & run

Prerequisites: macOS 13+, Xcode 15+, and [XcodeGen](https://github.com/yoneraiken/xcodegen)
(`brew install xcodegen`).

```bash
./scripts/fetch-assets.sh     # downloads Nunito + the Solar icons (one time)
xcodegen generate             # writes LoudFlow.xcodeproj
open LoudFlow.xcodeproj        # then run with ⌘R
```

> Don't want to install XcodeGen? Ask and a ready-made `.xcodeproj` can be provided instead.

### Permissions the app asks for
- **Microphone** — to record. Prompted on first record.
- **Accessibility** (System Settings → Privacy & Security → Accessibility) — required for the
  global hold/double-tap hotkeys and for typing the transcript into other apps. The app opens
  the pane for you and explains why. Without it, only "click the widget" + "clipboard only"
  work.

The app is intentionally **not sandboxed** — the sandbox blocks global hotkeys and cross-app
text insertion. See `Resources/LoudFlow.entitlements`.

### Transcription key
LoudFlow uses **Deepgram** by default. Onboarding step 3 asks for your API key (nothing
transcribes without one); you can change it later in **Settings → Transcription**. The key is
stored in the **macOS Keychain**, never in preferences. A pluggable `Transcriber` protocol
lets an OpenAI Whisper adapter slot in (`Sources/LoudFlow/Transcription/`).

---

## Architecture

```
Sources/LoudFlow/
  LoudFlowApp.swift        @main — menu-bar residency, main window, floating widget panel
  App/                     AppModel (central state), Persistence (JSON + audio), Keychain, Preferences
  Audio/                   AudioRecorder (→ .m4a on disk), AudioPlayer (progress)
  Transcription/           Transcriber protocol, DeepgramTranscriber, WhisperTranscriber, TranscriptionQueue
  Input/                   HotkeyManager (⌥Space hold / ⌃⌃ double-tap), TextInserter, Permissions
  Widget/                  WidgetPanel (borderless NSPanel), WidgetView (idle/recording/transcribing/error/queued)
  Windows/                 MainWindow, Sidebar, TodayView, LibraryView, SettingsView, ReceiptsView
  Onboarding/              OnboardingView (4 steps)
  DesignSystem/            Theme, Typography, SolarIcon, Components
Resources/                 Info.plist, entitlements, Assets.xcassets, Fonts
```

Data lives in `~/Library/Application Support/LoudFlow/` — `clips.json` (transcript index) plus
`audio/*.m4a`. Retention sweeps delete audio past the chosen window while **keeping
transcripts**.

### Two decisions the spec left to the implementer
- **Deleting a clip asks first.** Deletion removes both audio and transcript with no undo, so
  the Delete button flips to an inline "Delete / Cancel" confirm before it acts.
- **Retention sweeps run on launch, when the app becomes active, and every 6 hours.** Each
  sweep deletes audio older than the window (7 / 30 days) and keeps the transcript;
  "Forever" never sweeps. Provider-side deletion is immediate per transcription (zero
  retention), independent of this.

---

## Design fidelity

Colors, type, spacing, radii, shadows, and animation timings come verbatim from the design
handoff and live in `DesignSystem/Theme.swift`, `Typography.swift`, and `Components.swift`.
Copy is used verbatim. The only net-new copy — the widget error states and the onboarding
key step — is called out in the source and easy to change.
