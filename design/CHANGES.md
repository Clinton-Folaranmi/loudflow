# LoudFlow — design changelog

**Current design version: 4.** The app is at **2**, with parts of 3 already built.
Current prototype: `LoudFlow v4.dc.html` (open in a browser). `LoudFlow v3.dc.html` and
`LoudFlow.dc.html` are kept for history only — do not build from them.

## How to use this file

Work top-down through the two Pending versions: **v3 first, then v4.** Every section carries its
own status, because v3 was applied unevenly:

- **Built** — already in the codebase, verified against the Swift source. Skip it.
- **Not built** — do this.
- **Verify** — the behavior exists; check the values match and change only what differs.

Where v4 contradicts v3, v4 wins. Section values are final: hex codes, sizes, radii, and copy are
exact, same rule as `README.md`. Ask before deviating.

When you finish a version, set that section's `Applied:` line to the commit sha and bump the
stamp below.

### The version stamp (not yet in the codebase)

```swift
// Sources/LoudFlow/DesignSystem/DesignVersion.swift
enum DesignVersion {
    /// The design changelog version this build implements. Bump when a version is applied.
    static let current = 2
}
```

Show it next to the app version in the sidebar's footer line while the design is in flux —
`LoudFlow 1.0 (1) · design 2` — so a stale build is visible without opening Xcode.

### Audit — 2026-08-22

Read against `Sources/LoudFlow` at the time of writing:

- **v3 §1 retention-swept clips — not built.** `Clip.audioDeleted` exists and is set by
  `sweepRetention()` and honoured by `play()` / `retryTranscription()`, but no view reads it.
  The only way to discover the audio is gone is to press play and get a toast.
- **v3 §3 transcribing ring — not built.** `ClipRowView.swift:78` is still
  `ProgressView().controlSize(.small)`.
- **v3 §6 onboarding — not built.** `OnboardingView.swift` still carries the long step 3 and
  step 4 body copy, still renders `TriggerMode.desc` in the trigger rows, and has no fixed
  height on the step content.
- **v3 §2 snap rails, §4 empty states, §5 mic meter — built.** `SnapGuide.swift`,
  `LibraryView.swift:36/98`, and `LiveWaveBars` + the `Hearing you` switch are all present.
  Treat those three as **Verify**.
- **v4 — nothing built.** No diarization, no `turns`, no voice store, no earcons, no filter
  chips, no scrubber, no per-day hover, and no `DesignVersion.swift`.
- **v4 §8 is contradicted in code.** `DeepgramTranscriber.swift:13` requests
  `punctuate=false&smart_format=false` with a comment stating raw transcripts are wanted. That
  was the v1 intent; v4 reverses it deliberately. Change the request and the comment together.

---

## v4 — 2026-08-22 — **Pending**

Applied: _not yet_

Speaker identification, formatting, and a second kind of recording. This is the largest batch so
far and it changes the app's shape: LoudFlow is now two things — short dictation ("notes") and
recorded conversations ("meetings") — distinguished by **how many voices are in the recording**,
never by a mode the user sets.

Apply v3 first — parts of it are still missing. Where v4 contradicts v3, v4 wins. **Nothing in
v4 is built yet**; the per-section tags say which Swift files each one lands in.

### 1. Diarization and a second recording kind — **Not built**
`Clip.swift`, `Domain.swift`, `Transcription/`

- Request **diarization** from the provider (Deepgram `diarize=true`; the Whisper path needs an
  equivalent or the feature degrades to one voice). The response carries a speaker index per
  word; collapse consecutive words by the same speaker into **turns**.
- `Clip` gains `turns: [Turn]?` where `Turn = { speaker: Int, at: TimeInterval, text: String }`.
  `text` stays for single-voice clips. A clip is a **conversation** when it has turns and more
  than one distinct speaker; otherwise it is a **note**. Derive it — do not store a kind flag,
  and do not add a meeting mode to the widget.
- **Capture the other side of calls**: record the microphone and system audio as **two separate
  tracks**. Speaker 0 is always the mic, so "You" is never a guess; diarization only has to
  split the remote side. This is not a user setting — it is how recording works.

### 2. Voice profiles — **Not built**
new `App/Voices.swift`, `SettingsView.swift`

Voices persist **across recordings** via a stored voice profile, so a name given once is reused.

- A voice has: id, optional name, a fill `color`, a text `ink`, and **two seconds of audio**
  kept from the recording it was named in, for playback.
- Voice 0 is always `You` and cannot be renamed or forgotten.
- Unnamed voices display as `Speaker {n}` (1-based) in transcripts and `Unnamed voice` in
  Settings.
- The three voice colors are separated by **hue**, not lightness, and each has a text-safe ink
  (all clear 4.5:1 on `#FDFBF6` and on a highlighted turn). Fills are for dots and chips only:

  | Voice | Fill | Ink (text) |
  |---|---|---|
  | You | `#7E9A82` | `#3F5943` |
  | Second voice | `#C2603A` | `#9E4620` |
  | Third / unnamed | `#6E7FA8` | `#465A85` |

  Marigold is **not** used for a speaker — it stays the playhead and selection color.

### 3. Conversation transcript — **Not built**
`LibraryView.swift`, new `Windows/TurnBlockView.swift`

A conversation renders as turn blocks; a note keeps the flowing sentence text from v3.

- Each block: a header row at a **fixed 20px height** (so nothing reflows when the hover icon
  appears), then the turn text at 16px/1.55 with no left indent.
- Header row: the speaker name at 12.5px/800 **in that voice's ink** (no dot — the name carries
  the color), then the rename pen, then a spacer, then the timestamp at 11.5px/700 `#A08A5C`,
  tabular, hard right.
- **Rename pen**: 20px circle on `#FBF3DC`, an 11px `solar:pen-bold-duotone` in `#8A6A08`,
  visible **on hover only**, hover fill `#E8B930`. Clicking it replaces the name with a text
  field (`#FBF3DC`, 1.5px `#E8B930` border, radius 6px) focused on open; Enter commits, Escape
  cancels, empty keeps the old name. Committing a name saves the **voice profile** and updates
  every turn by that speaker at once, then toasts `Saved. I'll know that voice next time.`
- **Hover and active use the same fill**, `#F1EBDA` — no stroke, no second treatment.
- **Read by default.** The primary button is `Edit transcript` (`solar:pen-bold-duotone`);
  while editing, the section label reads `TRANSCRIPT · EDITING` and the button becomes
  `Done editing` (`solar:check-circle-bold`), which commits. Notes keep fix-in-place editing
  and the `Save changes` button.
- Speaker and timestamp are **never** editable — they belong to the audio.
- Reading: clicking a turn seeks to it and plays (cursor `pointer`). Editing: clicking places
  the caret (cursor `text`). There is **no play button** inside the transcript.
- Playback highlights the current turn and auto-scrolls to keep it visible, never while the
  caret is in the field.

### 4. Notes transcript — remove per-sentence playback — **Not built**
`LibraryView.swift`

The gutter play handle, the hover tint, and click-to-seek are **removed** from note sentences —
a 14-second clip doesn't need them and the scrubber covers it. Sentences sit flush as plain
editable text. The active-sentence highlight during playback stays.

### 5. Scrubber — **Not built**
`LibraryView.swift`

The editor's progress track is now a real scrubber: a **16px** `#E8B930` knob with a 2px
`#FBF6EA` border, centered on the 8px track, in a 6px vertical hit-slop. Click or drag anywhere
on the track to seek. The position belongs to the clip, survives pausing, and resumes from where
it stopped; playing to the end leaves the knob at the end rather than snapping back.

### 6. Library rows and filters — **Not built**
`ClipRowView.swift`, `LibraryView.swift`

- The leading circle now shows **what kind of recording it is**, and morphs to play on hover:
  a note shows `solar:soundwave-bold-duotone`, a meeting `solar:users-group-rounded-bold-duotone`;
  on row hover either becomes `solar:play-bold`, and `solar:pause-bold` while playing. Same 30px
  (Today) / 32px (Library) circle and colors as before.
- A conversation row's preview is prefixed with the first speaker (`Ada: …`), still truncated at
  62 characters, and its metadata reads `{time} · {n} voices · {size} MB`.
- **Filter chips** above the Library list: `All` · `Notes` · `Meetings`. Active chip is
  marigold fill with `#2A2620` text; inactive is transparent with a 1.5px `#CBD6C7` border and
  `#5C6659` text. Switching filters keeps the selected clip if it is still in the list,
  otherwise selects the first, and leaves edit mode.

### 7. Copy follows the clip — **Not built**
`LibraryView.swift`, `ClipRowView.swift`

One `Copy` button, no variants. A meeting copies as `{Speaker}: {text}` blocks separated by
blank lines; a note copies the bare words. Toasts: `Copied with speaker names.` for a meeting,
`Copied.` for a note.

### 8. Formatting is not a setting — **Not built, and contradicted in code**
`SettingsView.swift`, `DeepgramTranscriber.swift`, `Domain.swift`

Punctuation, paragraph breaks at natural pauses, and number/date/currency formatting are
**always on** — they are the ASR model's own output, not a rewrite, so there is nothing to opt
out of. Remove the `Add punctuation` toggle. Request smart formatting from the provider
(Deepgram: `punctuate`, `paragraphs`, `smart_format`).

The v1 principle stands and should be restated as **"no rewording, ever"** — no tone presets, no
LLM cleanup. Formatting is not rewording.

### 9. Editor pane fills its height — **Not built**
`LibraryView.swift`

The transcript scrolled early because it was capped at a fixed height. The editor card is
`calc(100vh - 260px)` (min 420px) and the transcript fills the remaining space, scrolling only
once the text passes the bottom. In SwiftUI terms: no fixed `maxHeight` on the transcript — let
it take the remaining space in the column.

### 10. The widget is one morphing pill — **Not built**
`WidgetView.swift`, `WidgetPanel.swift`

Today each state is its own pill and they slide in and out of view. Replace that with **one
container** that morphs: background and padding animate over **0.22s ease**, the leading dot
animates its fill and size, and only the labels swap. Nothing translates vertically — remove the
`fRise` transition between widget states (it stays for the toast and the onboarding modal).

Per state — background, padding, dot size, dot fill, dot icon, label:

| State | Pill | Padding | Dot | Icon | Label |
|---|---|---|---|---|---|
| Idle | `#FDFBF6` | `6px`, `8px 12px` hovered | 24px `#7E9A82` | `microphone-3-bold` | hidden until hover |
| Recording | `#2A3129` | `8px 10px` | 22px `#E8B930`, `fPulse` 1.5s | `stop-bold` | `Listening  {m:ss}` marigold |
| Transcribing | `#FDFBF6` | `8px 12px` | 24px `#E8B930`, `fPulse` 1.1s | `text-square-bold` | `Transcribing…` `#3F5943` |
| Queued | `#2A3129` | `8px 12px` | 22px `#EAF0E7` | `history-bold-duotone` | `No network — saved it to try later.` |
| Error | `#2A3129` | `8px 12px` | 22px `#E8B930` | `danger-triangle-bold` | failure message + marigold action |

Clicking the pill: idle starts (except in hold mode), recording stops, error opens Settings. The
✕ discard button shows only while recording.

### 11. Sounds — **Not built**
new `Audio/Earcons.swift`

Three short synthesized tones, no audio files:

- **Record starts** — 784 Hz, 70ms.
- **Record stops** — 523 Hz, 70ms.
- **Transcript lands** — 1046 Hz then 1318 Hz, 50ms and 80ms, 55ms apart.

Each is a **triangle** wave with a 4ms linear attack, a linear decay to true zero, and a lowpass
at 3× the fundamental. Peak gain 0.3 for record/stop, 0.22/0.26 for the chime. (An exponential
decay tail reads as an echo — keep it linear.) No setting; sounds are on.

### 12. Settings copy and structure — **Not built**
`SettingsView.swift`, `Domain.swift`

- `Keep the audio, not just the text` → **`Keep the audio`**.
- Remove the `Add punctuation` toggle (see 8) and the sounds toggle (see 11). Two switches
  remain: `Type it into whatever field I'm in` and `Keep the audio`.
- Retention note: `Transcripts stay.` → **`Transcripts remain.`**
- The `Conversations` card becomes **`Speakers`** (`solar:users-group-rounded-bold-duotone`).
  It has no toggle — two-track capture is how the app works, not a preference. Copy: `When a recording has more than one voice, LoudFlow labels each one. Voices you've named are
  recognised the next time they turn up.`
- Voices are **pills**, not full-width rows: `#FDFBF6`, 1.5px `#EFE6D2` border (marigold while
  renaming), radius 99px, uniform **5px** padding, 6px gap. Each pill is
  **play · name · pen · Forget**:
  - **Play** — a 20px circle, `#EAF0E7` with a 10px `solar:play-bold` in `#3F5943`; marigold
    with a pause icon while playing. Plays the voice's stored two-second sample so you can
    confirm the match. Inert on an unnamed voice (tooltip `Name this voice to keep a sample`).
  - **Pen** — 20px circle on `#F1EBDA`, hover marigold; opens an inline field pre-filled and
    selected, Enter commits, Escape cancels.
  - **Forget** — a text link at 11.5px/700 `#A08A5C`, shown only for a **named** voice that
    isn't You. Never an unlabeled ✕.
- Transcription card: the no-key line reads
  `No key yet — recordings wait until there is one.` followed by a link
  **`Get a {provider} key`** (Deepgram → `console.deepgram.com/signup`, OpenAI →
  `platform.openai.com/api-keys`), also shown when a key was rejected.
- The standing privacy paragraph becomes an affordance: `solar:info-circle-bold-duotone` at 15px
  plus `Where your audio goes` at 12.5px/700 `#A08A5C`, revealing the sentence on hover in a
  280px `#2A3129` popover (radius 14px, 12px/14px padding) above the trigger. The text itself is
  unchanged and must stay honest about the cloud round trip.
- **All Settings labels are literal strings in the view, not generated** — trigger names,
  keycaps, toggle labels, retention pills, provider names. (In the prototype, generated text
  can't be edited in place; in the app this just means no needless indirection.)

### 13. Receipts — per-day detail on hover — **Not built**
`ReceiptsView.swift`, `AppModel.swift`

Hovering a bar in `Words per day` turns it marigold and shows a `#2A3129` panel, radius 14px,
padding `11px 13px`, width 184px, with four lines:

1. `{n} words` — 15px/800 `#E8B930`
2. `{n} min of typing avoided` — 12px/700 `#F2F5F0`
3. `{n} recordings` + ` · {n} meetings` when the day had any — 12px `#A9BCAB`
4. `Longest {m:ss}` — 12px `#A9BCAB`

The panel is anchored to the **bar**, 8px above it, so it tracks each day's height; the first and
last columns pin their panel to the card's left and right edge instead of centering, so it never
leaves the card. The chart reserves 112px of headroom so the tallest bar's panel doesn't cover
the heading.

The static `Your longest single recording was {m:ss}.` caption is now redundant with line 4 —
leave it for now; it is being reconsidered.

---

## v3 — 2026-08-22 — **Pending** (partly built — see the per-section status)

Applied: _not yet_

Six changes. The first two are the substantial ones; the rest close gaps between the shipped
app and the design.

### 1. Retention-swept clips need a visible state — **Not built**
`ClipRowView.swift`, `LibraryView.swift`

`Clip.audioDeleted` is set by `sweepRetention()` and read by `play()` and
`retryTranscription()`, but nothing in the UI shows it. Today the only way to discover the
audio is gone is to press play and get a toast. Design now covers it:

- **Clip row, play button**: background `#F1F4EF`, icon `#A8B0A6` (instead of `#EAF0E7` /
  `#3F5943`). Same size and icon. Tooltip: `Audio cleared by retention`.
- **Clip row, metadata**: `{time} · transcript only` replaces `{time} · {size} MB`.
- **Editor metadata line**: third segment reads `transcript only` instead of the file size.
- **Editor, in place of the 44px player row**: a strip on `#F1EBDA`, radius 14px, padding
  `13px 15px`, gap 10px — `solar:history-bold-duotone` at 17px in `#A08A5C`, then
  `Audio cleared by retention. The transcript stays.` at 12.5px/700 `#8A6A08`.
  (v4 renames this to `Transcripts remain.` wording elsewhere; this strip's copy is unchanged.)
  The player, progress track, and elapsed/total row are not rendered for these clips.
- **Retry panel** (pending clip whose audio was already swept): keep the
  `This recording didn't get transcribed.` heading, drop the retry button, and show
  `The audio was cleared by retention before this one transcribed, so there's nothing left to send.`
  at 12.5px `#A08A5C`, max-width 280px, line-height 1.5.
- Existing toasts are unchanged and still correct
  (`That audio was cleared by retention. Transcript stays.` / `Audio was cleared — can't retry.`).

### 2. Widget drag and edge snapping — **Verify**
`WidgetPanel.swift`, `SnapGuide.swift`, `WidgetView.swift`

The behavior is already implemented; this pins the visuals the prototype now shows, so the two
match. Verify against the prototype and change only what differs:

- Snap rails: inactive `#7E9A82` at 40% opacity, 4px thick; the target rail `#E8B930`, 6px.
  Left/right rails are 55% of screen height, centered, 8px from the edge; the bottom rail is
  50% of screen width, centered, 8px up.
- Rails appear only once the drag passes the 6pt threshold, and hide on release.
- Snap inset is 26px on every edge; the cross-axis position is clamped to 26px from both ends.
- Docked left flips the pill contents to `row` (icon leads); right and bottom stay
  `row-reverse`, so content always unfurls inward. Toast alignment follows the dock.

### 3. In-row transcribing pill — **Not built**
`ClipRowView.swift`

Replace the indeterminate `ProgressView()` with a 12px ring: 2px border `#EAF0E7`, top edge
`#7E9A82`, spinning 0.7s linear infinite. Gap 7px to the label `Transcribing…` at
11.5px/700 `#8A9188`, padding `6px 10px`, no background fill. Copy and retry pills stay hidden
while a row is transcribing.

### 4. Library empty states and list edge fades — **Verify** (strings already present)
`LibraryView.swift`

Note: v4 adds filter chips above this list and changes the row's leading icon — build v4's
version of the row, not this one, if you are applying both in the same pass.

- Empty list: `No recordings yet.` at 14px `#A8B0A6`, padding `8px 0`, left-aligned.
- Nothing selected (e.g. after deleting the last clip): cream pane, min-height 420px, centered
  `Select a clip to see its transcript.` at 14px `#A08A5C`.
- Edge fades: 18px at the top, 22px at the bottom, `#FDFBF6` → transparent, inset to the card's
  14px padding, 0.15s opacity fade, each shown only when there is list left in that direction.
  This matches the existing implementation — confirm the fades sit inside the card's radius.

### 5. Onboarding mic meter — **Built**
`OnboardingView.swift`, `Components.swift`

Matches `LiveWaveBars` as built (12 bars, gap 3, height 30, center-weighted, min scale 0.12)
and the label switch at level > 0.1 (`Hearing you` / `Say something…`). No change expected —
listed so the prototype and app can be diffed on it.

### 6. Onboarding modal height and copy — **Not built**
`OnboardingView.swift`

The modal currently grows and shrinks as you step through it. Fix the two variable blocks so
the card height is constant across all four steps:

- Body copy block: no reserved height — every step's body is one line.
- Step content block: min-height 192px on **each step's own section**, content centered, so the
  section fills the block instead of the wrapper padding it.

Step 3 and step 4 body copy are shortened to one line each so no step needs reserved space:

- Step 3: `Nothing transcribes without your {provider} key.`
  (was "LoudFlow uses {provider} to turn your voice into text. Paste your key to continue —
  nothing works without it.")
- Step 4: `Kept on this Mac. Transcribed in the cloud, then deleted.`
  (was "Recordings stay on this Mac. Audio is sent to {provider} to transcribe, then deleted
  there.") The cloud round trip is still named — the provider is named on step 3 and in
  Settings, so it isn't repeated here. Do not soften this further.

Also: the onboarding trigger rows no longer show `TriggerMode.desc`. Each row is
icon · keycap · name, with the name filling the remaining width so the keycap sits at the right
edge. The descriptions still appear on the Settings trigger cards.

---

## v2 — **Applied** (shipped in the current codebase)

Applied: current `main`

Recorded for history — everything here is already built. It covers the work that came out of
implementation: the four-step onboarding with the required API key, the Settings
`Transcription` card, the widget `queued` and `error` states, per-clip retry, the
`What should I call you?` name field, the delete confirm step, the icon-only widget that
expands on hover, and the recording pill's cancel (✕) button.

## v1 — **Applied** (the original handoff)

`README.md` plus `LoudFlow.dc.html`. Note that the README still describes v1 behavior in a few
places — the three-step onboarding, the waveform inside the recording pill, and
`Writing it out…` as the transcribing label. Where the README and this changelog disagree, this
changelog wins.
