# LoudFlow — code changelog

What the app actually ships. Its counterpart is the design changelog in Claude Design, mirrored
at [`design/CHANGES.md`](design/CHANGES.md); [`design/SYNC.md`](design/SYNC.md) explains how the
two stay in step.

Each release names the **design version** it implements. That number is also compiled into the
build as `DesignVersion.current` and shown in the sidebar footer.

## 1.7.1 — 2026-10-31 — design 5

Fixes from the platform audit. Not a design update.

### Fixed

- **Playback no longer redraws the whole window 30 times a second.** The playhead moved into
  its own small object, so only the scrubber follows it, and the transcript redraws only when
  the highlighted turn changes. The sidebar's storage meter used to list the audio folder twice
  on every redraw; the size is now measured only when audio is added or removed.
- **The storage meter means something.** It was scaled to 12 MB from the original mockup, so
  any real library read 100%. It now shows recordings against the space left on this Mac, and
  the label switches to GB when it gets there.
- **Library saves happen off the main thread.** A burst of edits becomes one write, and the
  last one is flushed on quit. The library as it was at launch is kept as
  `clips.backup.json`, and a library file that can't be read is moved aside instead of being
  overwritten by an empty one.
- **Dictation no longer wipes images or files from the clipboard.** Every clipboard item and
  type is restored after the paste, not just plain text.
- **Speaker suggestions survive a relaunch**, along with the ones you turned down. Naming or
  reassigning a speaker clears its suggestion.
- **With "Keep the audio" off, voices are still learned.** The audio is cleared once voice
  matching has read it, instead of before.
- Unfinished recordings from a crash or force quit no longer leave raw tracks behind.

### Added

- **Call-audio status on meetings.** If another app was playing audio during a recording but
  none of it reached the call track, the meeting says so and links to the System Audio
  Recording setting. Meetings that did record the call say "call audio recorded".
- **A unit-test target** (`LoudFlowTests`) covering turn building, echo removal and Deepgram
  decoding. It compiles the transcription code directly rather than launching the app, so it
  never touches your library. Run it with `xcodebuild test -scheme LoudFlow`.

### Changed

- `Turn` and `Provider` moved into their own files so the tests can build without the app.
- Replaced the deprecated `onChange(of:perform:)` calls and fixed a Sendable warning; the app
  now builds with no warnings of its own.

## 1.7.0 — 2026-10-31 — design 5

Transcription accuracy and speaker identification. Not a design update.

### Changed

- **Deepgram moves from Nova-2 to Nova-3**, and diarization from `diarize=true` (which Deepgram
  pins to its v1 diarizer) to `diarize_model=latest`. If Deepgram rejects that parameter, the
  request is retried once with `diarize=true`.
- **OpenAI moves from `whisper-1` to `gpt-transcribe`.** `whisper-1` is deprecated and shuts down
  on 2027-02-26; it is only used now if a key can't use `gpt-transcribe`. The provider is labelled
  "OpenAI" rather than "OpenAI Whisper".
- **Speaker turns are cleaned up before they're shown.** A word or two of one sentence that the
  diarizer hands to another voice goes back to the voice around it, and a voice that appears for
  a word or two in a recording only one person spoke in is folded in, so a dictation no longer
  turns into a two-voice "meeting".
- **Two-track recordings drop the call's echo.** Without headphones the mic also hears the far
  side, so their words appeared twice, the second copy as you. Mic words that match the far side
  at the same moment are removed. Turns also interleave sentence by sentence instead of one long
  block per side.
- **Voice profiles average every confirmed sample** instead of keeping only the clip a voice was
  first named in. Naming a speaker, accepting a suggestion, or picking a named voice from the pen
  menu all count.
- **LoudFlow learns your voice** from your solo recordings (once a meeting has been recorded), so
  in a mic-only meeting it can suggest which "Speaker" is you. Suggestions stay suggestions.
- **Voice matching reads only what it needs.** It used to decode a whole recording into memory
  per speaker (about 330 MB per channel for an hour and a half); it now reads at most 30 s, skips
  pauses, and picks the speaker's longest turns, up to the 10 s the embedder actually hears.
- Turns store where their last word ends, for better voice samples and playback.

### Removed

- **The Vocabulary card.** Its terms went to Deepgram as `keywords` and to Whisper as a `prompt`;
  boosting can insert the boosted words where they weren't said. Saved terms are cleared.

### Fixed

- **Recording from a multi-channel input (USB mics, audio interfaces) produced silence.** The mic
  file is mono and rejected stereo buffers; input is now mixed down first.
- **The far side of a call was shifted early.** The system-audio track starts a beat after the
  mic; the two are now aligned on their start times.
- **A recording over OpenAI's 25 MB limit retried forever.** It now fails with a clear message.
  Uploads also allow 10 minutes before timing out, so long meetings aren't cut off.
- Voice matching no longer assumes the embedder returns unit-length vectors.

## 1.6.1 — 2026-10-09 — design 5

### Interaction refinement

- Removed the Library's persistent selected-row fill and native blue focus effect.
- Tightened letter spacing for selected bold clip titles to reduce their width shift.
- Removed the slide and fade transition from the transcript panel when selecting a clip.

## 1.6.0 — 2026-10-08 — design 5

### Interaction polish

- The sidebar selection travels between tabs and page content settles into place; Library
  filters, clip selection, Settings options, onboarding steps, and local action feedback share
  a restrained motion vocabulary.
- The floating widget follows the pointer in screen coordinates while dragged, updates snap
  guides only when needed, and defers competing resize animations until the drag ends.
- Edited transcripts commit to their own clip when selection or tab changes. Library search
  keeps the transcript pane aligned with the visible result list.
- Clip rows and transcript turns can be activated from the keyboard, the scrubber supports
  arrow-key and accessibility adjustments, and chart details and transcription privacy copy
  are available by click or focus as well as hover.
- Reduce Motion stops repeating decorative animation and replaces large transitions with
  immediate state changes.

### Fixed

- **Conversation turns seek reliably from the text itself.** The transcript body previously
  enabled macOS text selection, which consumed its click before the turn's seek gesture could
  receive it. Clicking any read-only turn now jumps to its timestamp and starts playback; edit
  mode still gives the text field the click and caret.
- **Speaker correction is no longer hidden behind hover.** The speaker pen remains visually
  quiet when a turn is not hovered, but is always available to click. Transcript corrections
  remain local to that recording; Settings is still the deliberate global-profile surface.
- **The recording pill changes state as one motion.** Its state, padding, background and
  contents now use a shared damped spring rather than separately finishing ease-in-out
  animations, removing the visible shape/label mismatch while recording stops and
  transcription begins.

### Added

- **Library-wide transcript search.** Search filters the current library view by transcript
  content and named speakers, with an explicit empty state and clear control.
- **Playback speed control.** The editor transport now offers 0.75×, 1×, 1.25×, 1.5×, and 2×.
  The selected speed applies immediately, carries into the next clip, and is remembered across
  launches.

## 1.5.0 — 2026-09-04 — design 5

A week of real use, not a design update — no design v6 exists yet, so this ships as code first;
see [`design/SYNC.md`](design/SYNC.md) for the push-back that follows.

### Fixed

- **Pointing-hand cursor on every clickable control.** Nav rows, filter chips, clip rows, the
  scrubber, editor and settings buttons, voice pills, and the widget pill (while a click does
  something) now show it. Implemented as a cursor rect, not `NSCursor.push()/pop()` — push/pop
  drifts out of balance the moment a hovered view disappears out from under the mouse, which the
  morphing widget pill and hover-only Copy pill do constantly.
- **Receipts chart hover panel no longer draws behind the next bar.** Hover state moved from
  each bar up to the chart, so the hovered column's `zIndex` can be raised above its neighbours —
  an `HStack`'s children otherwise paint in source order, which is why the panel disappeared
  under whatever came after it.
- **Widget toast moves beside the pill instead of on top of it**, sliding out from behind it on
  the side the pill grows in, rather than dropping in from above. The toast's "Fix it" action is
  gone with it — the only thing it did was reopen the last clip, redundant with just clicking it
  in Library.
- **Today lists every recording for the day**, not just the first four.
- **"ON THIS MAC" opens the recordings folder** in Finder.
- **Audio cues (record start/stop, transcript landed) now reliably play.** They were rendered
  through one long-lived `AVAudioEngine`, which recording itself can silently disconnect —
  starting the mic engine, and (with system audio) `SystemAudioTap` building a private aggregate
  output device, both fire `AVAudioEngineConfigurationChange`. The engine restarted fine after
  that, so nothing surfaced an error, but its player node was no longer connected to anything.
  Each tone now plays through its own cached `AVAudioPlayer`, which re-establishes its own output
  across a device change instead of depending on one shared engine staying wired up.

### Speaker labelling reworked

The reported bug — wrong-person attribution, and "I can't edit my own voice" — traced to
`applyTranscript` pinning provider-local speaker 0 to `You` on **every** clip, when the mic/system
track split (which is what actually guarantees that) only exists on a two-track recording. On a
mono clip (in-person meeting, the system-audio permission declined, nothing playing) whoever
diarization heard first became "You" — permanently, since `You` couldn't be renamed, reassigned,
or reconsidered.

- **Mono clips no longer default a speaker to You.** Every local speaker index gets its own
  voice, exactly as remote speakers already did on a two-track clip, leaving attribution to the
  user (or a confirmed suggestion) instead of a guess baked in at transcription time.
- **You can be renamed.** Its name is `AppModel.displayName` — the same one the greeting uses —
  editable from its own Settings pill or from a transcript's rename menu. It still can't be
  merged into another voice or forgotten; it's defined by the microphone track, not by a name.
- **Fixing a speaker from a transcript now touches only that recording.** A new per-clip API
  (`reassignSpeaker` / `detachSpeaker` / `nameSpeaker`) repoints one clip's turns without
  renaming the shared voice profile everywhere it appears; the transcript's pen menu now offers
  named voices, **You** (when the clip doesn't have one), typing a new name, and — once a speaker
  already carries an identity — "Not this person" to split it back off. Renaming a voice from
  Settings remains the global path, on purpose: that's the one place a name is meant to apply
  everywhere.
- **The recogniser suggests instead of silently repointing.** A confident match now shows as a
  dismissible "Looks like Ada" chip on the transcript instead of rewriting the turn (and forgetting
  the stand-in voice) on its own — a wrong guess used to be unrecoverable and could silently
  rewrite a name across the library. Accepting or dismissing is always the user's call.

### Added

- **Vocabulary bank.** A Settings card for names, jargon, and spellings the transcriber tends to
  mangle, sent along as a decoding hint — Deepgram's `keywords` parameter, or Whisper's `prompt`
  field for the OpenAI path. Every named voice is included automatically, so naming someone helps
  their own transcript without retyping the name.

## 1.4.0 — 2026-08-22 — design 5

Applies design versions **3**, **4**, and **5** in full. Two kinds of recording, speaker names
that persist, provider-side formatting, and two corrections made while building v4.

### Design v4

- **Diarization and conversations.** Deepgram is asked for `diarize=true`; per-word speaker
  indices are collapsed into turns. `Clip` gains `turns: [Turn]?`. A clip is a conversation when
  it has turns from more than one speaker — derived, never a stored flag or a mode the user
  sets. The Whisper path has no diarization and degrades to a single voice. *(design v4 §1)*
- **Two-track capture.** The microphone and system audio are recorded as separate tracks, so
  speaker 0 is always you rather than a guess. Declining the permission falls back to mic-only.
  *(design v4 §1)*
- **Voice profiles.** Voices are global, not per-clip: naming one renames every turn it ever
  spoke, in every clip, and the profile keeps a two-second audio sample so you can play it back
  and confirm the match. Voice 0 is `You` — guaranteed by the mic being its own track — and
  can't be renamed or forgotten. Typing a name that matches a voice you've already named
  **merges** the two onto one profile. *(design v4 §2)*
- **Conversation transcript.** Turn blocks with per-voice ink, an inline rename pen, and
  read-by-default editing (`Edit transcript` / `Done editing`). Speaker and timestamp are never
  editable. *(design v4 §3)*
- **Notes transcript.** Per-sentence play handles, hover tint, and click-to-seek removed; the
  playback highlight stays. *(design v4 §4)*
- **Scrubber.** The editor's progress track seeks on click and drag, and the position belongs to
  the clip across pause and resume. *(design v4 §5)*
- **Library rows and filters.** The leading circle shows the recording's kind and morphs to play
  on hover; conversation rows are prefixed with the first speaker and count voices instead of
  showing a size. `All` / `Notes` / `Meetings` filter chips above the list. *(design v4 §6)*
- **Copy follows the clip.** One Copy button: meetings copy as labelled blocks, notes copy bare.
  *(design v4 §7)*
- **Formatting is not a setting.** Punctuation, paragraphs, and smart formatting are requested
  from the provider and always on; the `Add punctuation` toggle and the local punctuation pass
  are gone. No rewording, ever — formatting is not rewording. *(design v4 §8)*
- **Editor fills its height.** The transcript takes the remaining space in the column and
  scrolls only once the text passes the bottom. *(design v4 §9)*
- **One morphing widget pill.** A single container animates background, padding, and dot across
  all five states over 0.22s instead of swapping pills. *(design v4 §10)*
- **Earcons.** Three synthesized triangle-wave tones for record start, record stop, and
  transcript landing. No setting. *(design v4 §11)*
- **Settings restructure.** `Speakers` card with voice pills, the provider key link, the
  `Where your audio goes` hover popover, and two remaining toggles. Toggle labels are literal
  strings in the view now; trigger names, keycaps, retention labels, and provider names stay on
  their enums, because the widget and onboarding render the same strings and duplicating them
  would be a way to make them disagree. *(design v4 §12)*
- **Receipts per-day detail.** Hovering a bar in `Words per day` shows words, typing avoided,
  recordings and meetings, and the day's longest take. *(design v4 §13)*

### Design v5

- **System audio moved from ScreenCaptureKit to a Core Audio process tap.** ScreenCaptureKit can
  reach system audio, but it is screen-recording-shaped: it asks for the Screen Recording
  permission, lights the menu-bar capture indicator, and gets periodically re-consented — for an
  app that never looks at a pixel. A process tap (`AudioHardwareCreateProcessTap`, macOS 14.2+)
  is the audio-only route: one prompt via `NSAudioCaptureUsageDescription`, no indicator. The
  tap excludes LoudFlow's own process so the earcons never land in a transcript. Deployment
  target raised from macOS 13.0 to 14.2 to get it. *(design v5 §1)*
- **Voices are recognised on-device, for real.** Each named voice keeps a 256-dimensional
  embedding computed locally (pyannote segmentation + WeSpeaker, via CoreML). A later
  recording's speakers are matched against it, so a voice you named once is labelled without
  being asked again. Deepgram still says *when* each speaker spoke; only *who they are* is
  answered here, and no audio leaves the Mac for that step. It refuses to guess: a match has to
  clear a cosine distance of 0.45 *and* beat the runner-up by 0.08, or the voice stays
  `Speaker 2`. *(design v5 §2)*
- **The rename pen offers voices you already know.** With named voices to choose from, the pen
  opens a menu of them first, `Type a name…` under a divider, so re-linking one the recogniser
  wasn't sure about is a click instead of retyping a name you've typed before. *(design v5 §3)*
- **Speakers card says where the model comes from.** `Matching a voice to one you've named runs
  on this Mac. The model it needs downloads once, the first time you name someone.` — with
  fetching and failure states — instead of quietly reaching for the network. *(design v5 §4)*

### Design v3

- **Retention-swept clips are visible.** Rows, editor metadata, the player strip, and the retry
  panel all say the audio is gone and the transcript stays, instead of only finding out by
  pressing play. *(design v3 §1)*
- **In-row transcribing ring.** A 12px spinning ring replaces the indeterminate
  `ProgressView()`. *(design v3 §3)*
- **Onboarding is a constant height.** Each step's content block reserves 192px, and steps 3 and
  4 are one line of body copy each. Trigger rows drop `TriggerMode.desc`. *(design v3 §6)*
- **Widget snapping matches the design.** Verified against the prototype: the rails were already
  right, but the snap inset was 2pt where the design says 26pt (measured to the visible pill, so
  the widget's transparent shadow margin is subtracted back off), and the cross-axis position
  wasn't clamped — a widget dropped in a corner jammed against both edges. *(design v3 §2)*
- Verified unchanged against the prototype: library empty states and list edge fades *(§4)*, the
  onboarding mic meter *(§5)*.

### Also

- Design and code changelogs paired, with `DesignVersion.current` compiled into the build and
  shown next to the app version in the sidebar footer. See [`design/SYNC.md`](design/SYNC.md).

## 1.3.0 — design 2

The first shipped build. Four-step onboarding with a required API key, the Settings
`Transcription` card, widget `queued` and `error` states, per-clip retry, the display-name
field, delete confirmation, the icon-only widget that expands on hover, and the recording pill's
discard button.
