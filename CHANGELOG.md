# LoudFlow — code changelog

What the app actually ships. Its counterpart is the design changelog in Claude Design, mirrored
at [`design/CHANGES.md`](design/CHANGES.md); [`design/SYNC.md`](design/SYNC.md) explains how the
two stay in step.

Each release names the **design version** it implements. That number is also compiled into the
build as `DesignVersion.current` and shown in the sidebar footer.

## Unreleased

Nothing pending.

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
