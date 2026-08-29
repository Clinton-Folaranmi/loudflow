# Draft — design v5

Written from the code side, in the format of `CHANGES.md`, ready to paste in above the v4
section in Claude Design. Everything here is **already built** — v5 documents decisions taken
during implementation rather than ahead of it, which is why every section is tagged Built.

Once it's in, bump `DesignVersion.current` to 5. The `Applied:` sha is already filled in.

---

## v5 — 2026-08-22 — **Applied**

Applied: `c069ad9`

Two corrections to v4 that came out of building it. Both are about being able to keep v4's
promises rather than changing what it promised — the permission LoudFlow asks for, and whether
a named voice is really recognised next time.

### 1. System audio comes from a Core Audio tap, not ScreenCaptureKit — **Built**
new `Audio/SystemAudioTap.swift`, `Audio/AudioRecorder.swift`, `Resources/Info.plist`, `project.yml`

v4 §1 said to record system audio as its own track but not how. ScreenCaptureKit is the obvious
route and the wrong one: it is screen-recording-shaped. It asks for the **Screen Recording**
permission, lights the capture indicator in the menu bar, and gets re-consented periodically —
all for an app that never looks at a pixel. Asking for a permission broader than what you do is
the same failure as overclaiming in copy.

- Capture system audio with a **Core Audio process tap** (`AudioHardwareCreateProcessTap` /
  `CATapDescription`), riding a private aggregate device on the default output.
- The permission is audio-only, prompted once via `NSAudioCaptureUsageDescription`:
  `LoudFlow records the other side of your calls, so a conversation's transcript can say who said what.`
- The tap is **global minus LoudFlow's own process**, so the earcons can never land in a
  transcript. `muteBehavior` is `.unmuted` — you still hear the call while it records.
- Refusing the permission, or nothing playing, falls back to a mono clip. A note is still a note.
- This raises the deployment target from **macOS 13.0 to 14.2**, which is where taps arrive.

### 2. Voices are recognised on-device — **Built**
new `App/VoiceRecognizer.swift`, `App/Voices.swift`, `AppModel.swift`

v4 §2 said a named voice is recognised the next time it turns up. Nothing in the transcription
path can do that: a provider's diarization separates voices *within* one recording and has no
idea that today's speaker 1 is last Tuesday's. Left there, the Settings line would have been an
overclaim. So the app does it itself, locally.

- Each **named** voice keeps a 256-dimensional embedding — a voice fingerprint — computed on
  this Mac from up to 12 seconds of that speaker's turns in the recording it was named in.
- A later recording's unnamed speakers are embedded the same way and compared. The provider
  still says *when* each speaker spoke; only *who they are* is answered here, and no audio
  leaves the Mac for that step.
- **It refuses to guess.** A match must be within a cosine distance of **0.45** *and* beat the
  runner-up by **0.08**. Below that the voice stays `Speaker 2` for you to name. A wrong name
  written on a transcript is worse than no name, and the two thresholds are the whole difference
  between the two.
- One clip can never map two speakers onto the same voice.
- Nothing runs and nothing is fetched until at least one voice has been named — until then there
  is nobody to recognise.
- Models are pyannote segmentation plus a WeSpeaker embedder, as CoreML, via **FluidAudio**
  (Apache 2.0, pinned to 0.15.6). They download once on first use and are cached from then on.

### 3. The rename pen offers voices you already know — **Built**
`Windows/TurnBlockView.swift`

v4 §3's pen opens a text field. It still does, but when there are names to choose from it opens
a **menu of them** first, with `Type a name…` under a divider. Re-linking a voice the recogniser
wasn't sure about is one click instead of retyping a name you have typed before.

Voices already speaking in that clip are left out of the list — the same person can't be two
speakers in one conversation. With no named voices yet, the pen behaves exactly as v4 describes.

### 4. Speakers card says where the model comes from — **Built**
`Windows/SettingsView.swift`

Recognition runs on this Mac, but the model has to arrive from somewhere once, and the app says
so rather than quietly reaching for the network. Under the existing card copy, at 12px `#A08A5C`:

`Matching a voice to one you've named runs on this Mac. The model it needs downloads once, the first time you name someone.`

While fetching, that line reads `Fetching the voice model…`. If it fails:
`Couldn't fetch the voice model, so voices won't be recognised on their own yet. Naming one still works.`

The v4 §12 line — `Voices you've named are recognised the next time they turn up.` — is
**unchanged**, because as of §2 it is now true as written.
