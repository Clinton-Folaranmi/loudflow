# LoudFlow interaction and motion audit

8 October 2026 · app 1.5.0 (11), design 5 · review only

## Scope and evidence

Reviewed the installed app's Settings screen and accessibility tree, the current SwiftUI source for the main window, Today, Library, transcript editor, Receipts, Settings, onboarding, and floating widget, plus the launch film's interaction direction. The installed screen matches the source version. The UI automation session did not successfully switch tabs, so observations about the timing and feel of other live screens are source-based predictions, not measured playback. No app code or user data was changed.

The launch film gives a useful benchmark: one anchored object changes shape, color, and content together; the result lands with a brief glow and a nearby confirmation. The widget already uses much of that language. The main window mostly changes state immediately.

## Highest-priority findings

| Priority | Surface | Finding and evidence | User effect | Direction |
| --- | --- | --- | --- | --- |
| P0 | Transcript editing | The editor buffers text locally and saves only on **Save changes** or **Done editing**. Selecting another clip resets edit mode and remounts the pane; switching tabs also removes it. There is no dirty-state guard or save on exit. `LibraryView.swift:168-181, 505-522`, `AppModel.swift:814-823, 839-856`. | A normal navigation click can silently discard a correction. | Resolve the save/discard behavior before adding transitions. Show dirty state and provide a reliable commit path. |
| P1 | Widget dragging | The owner reports that dragging the floating widget clips and jumps. The drag callback repeatedly moves the NSPanel while its SwiftUI gesture is active, redraws and orders a full-screen snap-guide panel on every drag update, and can receive independent animated resize requests. These are plausible sources of discontinuity that need live reproduction. `WidgetView.swift:68-73`, `WidgetPanel.swift:140-184, 198-243`, `SnapGuide.swift:28-37`. | Moving the app's most frequent control feels unreliable. | Reproduce on each dock edge and during hover/state changes, keep the pointer-to-pill offset stable, update guides only when the target changes, and avoid competing frame animations during drag. |
| P1 | Sidebar and page navigation | Each selected row owns its own background, and taps assign `model.tab` directly; `MainWindow` swaps page trees with no explicit transition. `Sidebar.swift:83-103`, `MainWindow.swift:32-57`. | The selected pill appears in a new position rather than traveling with the user's action; the entire page jumps. | Use one shared selection shape that moves between rows. Give page content a restrained entrance while preserving the sidebar and scroll context. |
| P1 | Library search | Search changes `filteredClips`, but does not reconcile `selectedId`; the editor reads `selectedClip` from all clips. `LibraryView.swift:50-84, 129-145`, `AppModel.swift:798-823`. | Search can show a result list or empty state beside an unrelated transcript. | Make the visible selection follow results and explain the no-results state in both columns. |
| P1 | Library selection | Clip rows change fill and font weight immediately; the editor is recreated by clip ID. Hover color takes precedence over selected color. `ClipRowView.swift:31-36, 74-99`, `LibraryView.swift:129-145`. | Opening a clip has little continuity, and the selected state weakens under the pointer. | Keep a persistent selected treatment and bridge the row-to-editor change with a short content transition. |
| P1 | Keyboard and assistive access | Sidebar rows, clip rows, and transcript turn blocks are `onTapGesture` containers. In the installed app, sidebar entries appear as text in the accessibility tree, while the storage control appears as a button. The Receipts detail panel and “Where your audio goes” explanation are hover-only. `Sidebar.swift:83-103`, `ClipRowView.swift:93-99`, `TurnBlockView.swift:49-57`, `ReceiptsView.swift:121-132`, `TranscriptionCard.swift:90-112`. | The interaction model is unclear or unavailable from keyboard and VoiceOver. | Make actionable rows real controls with selection semantics; expose hover details on focus or click as well. |

## Surface-by-surface review

### Floating widget and recording flow

**Strong state transitions; drag needs separate work.** The pill uses a coherent spring for state and padding, animates the dot, anchors growth inward, delays hover exit to prevent edge flicker, and slides toasts from behind the pill. Its sounds and the transcription landing glow create a clear beginning and end to the recording action. `WidgetView.swift:40-97, 110-125, 166-188`, `WidgetPanel.swift:165-184`, `LibraryView.swift:562-567`.

The owner's report of clipping and jumpiness during drag is a first-hand finding. The code clamps the *panel* to the screen while moving it, although the visible pill has a transparent shadow margin; the guide's `show` path sets a full-screen frame, replaces its root view, and calls `orderFrontRegardless()` on every movement. The panel's size can also animate independently while the drag is in flight. These are hypotheses for the mechanism, not a measured diagnosis. Validate slow and fast drags, crossing the screen midpoint, entering/leaving hover, dragging while the pill is recording, the snap preview, release at each edge, and behavior across displays. `WidgetPanel.swift:198-243`, `SnapGuide.swift:28-37`.

Polish gaps: the widget's actionable pill is still a tap gesture, and the cancel target is 22 pt. Hover expansion is a good pointer hint but cannot be the only way to understand the idle action. State pulses run without a Reduce Motion alternative. Keep this motion as the reference for the rest of the app; do not add a second, louder animation style.

### Sidebar and Today

- The sidebar hover fill and active fill switch immediately. A shared, spring-driven pill would make a Today → Library → Settings path feel connected. Animate count changes only when counts actually change; do not animate the whole sidebar when recording data updates.
- Today’s **Open library** link has no custom hover or press response. The recording rows do show play on hover and copy confirmation in place, which are good local responses. The icon changes and row fill are immediate, while Copy alone fades in over 0.14 s. `TodayView.swift:24-49`, `ClipRowView.swift:39-50, 93-149`.
- The Today's recordings card should use the same row selection language as Library when it opens a clip, so the destination feels related to the source.

### Library list, filters, search, and empty states

- Filter chips switch marigold fill immediately. The list then changes in one step; there is no visual account of which rows remain or leave. Prefer a brief selection movement/color transition and a calm list update. `Components.swift:249-275`, `LibraryView.swift:37-84`.
- Search's clear button appears/disappears immediately. Its feedback could be a short fade; the higher priority is keeping the editor synchronized with the result set. `LibraryView.swift:50-69`.
- The list edge fades are already animated over 0.15 s and correctly indicate more content. Preserve them. `LibraryView.swift:102-126`.
- Copy confirmation in rows is appropriately local, but the hidden-until-hover button is difficult to discover or focus. Show it for selected/focused rows too. `ClipRowView.swift:133-149`.
- Transcribing and retry states are understandable; the spinner is a useful ongoing signal. Transition between pending, retry, and completed content without moving surrounding controls unexpectedly. `ClipRowView.swift:111-132`, `LibraryView.swift:402-451`.

### Player, transcript, speaker controls, and actions

- Playback swaps play/pause icons with no explicit symbol transition. The scrubber tracks real progress and supports click/drag, but has no hover/drag engagement state or keyboard adjustment. Playback speed is a native menu and should stay native; the trigger chip can acknowledge the new rate in place. `LibraryView.swift:240-285`, `Components.swift:277-325`.
- Active transcript turns do get a fill and auto-scroll over 0.2 s. Seeking a turn, however, changes the highlight immediately, and hover uses the same fill as playback. Distinguish a quiet hover from a clear current-playback state. `TurnBlockView.swift:32-57`, `LibraryView.swift:327-340`.
- The speaker pen becomes more opaque on hover over 0.12 s, and the menu uses native behavior. The suggestion chip appears/disappears immediately after accept/reject. Give that local result a brief closure animation and expose the actions to keyboard focus. `TurnBlockView.swift:193-291`.
- Save and Copy replace their own labels with **Saved**/**Copied**, a good pattern. Only the label state has an animation; the buttons do not acknowledge press, and Save is available even when nothing changed. The delete control swaps to inline Delete/Cancel without a transition; its confirmation is appropriate for an irreversible action. `LibraryView.swift:453-550`.

### Receipts

The bar color animates on hover over 0.12 s, but the detail panel is inserted/removed instantly and only on hover. A short fade and small vertical settle would connect panel to bar. Offer the same detail on focus/click for non-pointer use. Stat values and bars update without an explicit value transition; if a recording arrives while this page is open, those changes should read as one restrained update, not a page-wide celebration. `ReceiptsView.swift:21-83, 110-151`, `Components.swift:170-199`.

### Settings and menus

- The custom toggle knob slides over 0.16 s; this is one of the few main-window controls with a complete state change. Its full row is clickable. Preserve that behavior. `SettingsView.swift:72-97`, `Components.swift:138-157`.
- Trigger cards, retention pills, and provider chips change borders/fills immediately. These are mutually exclusive selections; one consistent selected-state transition would make them feel like a family. `SettingsView.swift:48-56, 101-120, 440-487`, `TranscriptionCard.swift:18-32`.
- Vocabulary pills and voice pills reflow immediately when added, renamed, removed, or forgotten. The 18–20 pt action circles are small. Give the changed item a local entrance/exit and let neighboring pills settle; enlarge effective hit areas without making the visuals heavier. `SettingsView.swift:190-266, 287-380`.
- The transcription status changes among missing, checking, saved, and rejected. Color and text provide feedback; a small in-place status transition would clarify the async validation. The audio destination tooltip should be reachable by click/focus and dismiss predictably. `TranscriptionCard.swift:34-79, 90-134`.
- The playback-rate and speaker-assignment menus use native macOS menus. Their menu animation should remain system-owned; polish the trigger, selection acknowledgment, and focus return rather than replacing the menus.

### Onboarding

The dialog has a consistent footprint and four progress segments. The modal enters with a rise, and step changes receive a general 0.2 s animation, but the step content is switched without a directional transition. A subtle forward/back content move and progress fill would strengthen orientation. Trigger, provider, and retention options should share the main app's selection behavior. The mic meter is useful live feedback. `OnboardingView.swift:34-115, 119-217`.

## Motion direction for implementation

1. **One continuity cue per action.** The sidebar selection travels; page content settles in; clip selection holds steady while the editor changes. Avoid animating the entire window for every click.
2. **Keep controls close to their feedback.** Copy/Save, retry, voice suggestions, and provider validation should resolve where the click happened. Reserve the widget toast for recording outcomes.
3. **Use a small timing vocabulary.** About 90–140 ms for hover/press, 160–220 ms for selection/content change, and a restrained 250–320 ms spring only for a moving shared shape. These are proposed timings to prototype, not measurements of the current app.
4. **Separate meaning.** Hover is an invitation; selected is persistent; playing is active; pending is ongoing; success is brief. They should not all rely on the same pale fill.
5. **Honor Reduce Motion.** Replace travel, pulses, and auto-scroll animation with state changes that keep all information visible. Preserve native menu behavior.

## Suggested work order

1. Protect edits and fix search/selection consistency.
2. Establish accessible row controls and keyboard/focus behavior.
3. Fix and test widget dragging and snapping, including the visual guide and panel resize interaction.
4. Prototype the sidebar traveling selection and page transition on Today, Library, Settings, and Receipts.
5. Polish Library selection, player, transcript states, and local action feedback.
6. Apply the same selection and feedback rules to Settings, Receipts, and onboarding; then validate normal and Reduce Motion paths in the built app.
7. Give the finished build a new version/build number, verify one final release, place it at `/Applications/LoudFlow.app`, then remove superseded LoudFlow app bundles and stale build products. Keep personal clip data and preferences intact.

## App bundle inventory and final cleanup

Six bundles currently resolve under the same `com.loudflow.app` identifier:

| Path | Bundle version | Last modified | Note |
| --- | --- | --- | --- |
| `/Applications/LoudFlow.app` | 1.5.0 (11) | 4 Sep 2026 | Installed copy; executable matches the Release build below. Intended final location. |
| `~/Library/Developer/Xcode/DerivedData/LoudFlow-cgajwsyceyvmuhguorjwymranlzq/Build/Products/Debug/LoudFlow.app` | 1.5.0 (11) | 5 Oct 2026 | Newest timestamp; distinct debug executable. |
| `~/Library/Developer/Xcode/DerivedData/LoudFlow-hkrmeomusjqqludppifxzctglurr/Build/Products/Debug/LoudFlow.app` | 1.5.0 (11) | 4 Oct 2026 | Distinct debug executable. |
| `~/Library/Mobile Documents/com~apple~CloudDocs/Shared/LoudFlow.app` | 1.1.0 (4) | 13 Aug 2026 | Old shared copy; check whether anyone else uses the shared folder before removal. |
| `~/Loudflow/build/dd/Build/Products/Debug/LoudFlow.app` | 1.4.0 (10) | 22 Aug 2026 | Old local debug build. |
| `~/Loudflow/build/dd/Build/Products/Release/LoudFlow.app` | 1.5.0 (11) | 13 Aug 2026 | Duplicate executable of `/Applications/LoudFlow.app`. |

The version number alone does not identify the newest code: four bundles all claim 1.5.0 (11), but the two debug bundles have different executables from the installed/Release pair and from each other. After the interaction work, verify the final build's content and behavior, replace the `/Applications` bundle, then clean stale app bundles. Do not treat `~/Library/Application Support/LoudFlow/` as an app copy; it contains the user's recordings and transcripts.

This report is a review artifact. It does not change implementation.
