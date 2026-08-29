# Design ↔ code sync

Two changelogs face each other, and they are the whole process:

| Where | File | Says |
|---|---|---|
| Claude Design | `design_handoff_loudflow/CHANGES.md` | what the design **should** be |
| This repo | [`design/CHANGES.md`](CHANGES.md) | the last snapshot pulled from there |
| This repo | [`../CHANGELOG.md`](../CHANGELOG.md) | what the app **actually** ships |

`design/CHANGES.md` is a byte copy of the design-side file at the last sync. It exists so that
`git diff` can answer "what changed in the design this week?" without re-reading the whole spec.

## The weekly loop

**Through the week** — edit the design in Claude Design. Add sections to the design changelog as
you go; nothing happens on this side.

**When you want to publish** — say *"sync the design"* in Claude Code. Then:

1. **Pull.** The design MCP fetches `design_handoff_loudflow/CHANGES.md` and overwrites
   `design/CHANGES.md`. `git diff design/CHANGES.md` is the week's work list — nothing else.
2. **Apply.** Implement the new and changed sections against the Swift source. Sections are
   worked in version order, oldest pending first; where a newer version contradicts an older
   one, the newer wins.
3. **Record.** Every shipped section gets a line in `CHANGELOG.md` under the release, naming
   the design version it came from.
4. **Stamp.** Bump `DesignVersion.current` in
   [`Sources/LoudFlow/DesignSystem/DesignVersion.swift`](../Sources/LoudFlow/DesignSystem/DesignVersion.swift)
   to the design version now fully applied. The sidebar footer reads `LoudFlow 1.4.0 (10) · design 4`,
   so a stale build is visible without opening Xcode.
5. **Build.** Bump `MARKETING_VERSION` (MINOR per feature batch, PATCH per fix) and
   `CURRENT_PROJECT_VERSION` in `project.yml`, then `./scripts/dev-build.sh`.

Steps 3–5 only happen for a design version that is **fully** applied. A partly-applied version
leaves the stamp where it is and leaves the sections marked in `CHANGELOG.md` under *Pending*.

## Rules that don't change

- Hex codes, sizes, radii, timings, and copy in the design changelog are **exact**. Ask before
  deviating.
- The design changelog outranks `README.md` wherever they disagree.
- `Applied:` in the design-side file gets the commit sha once a version ships, so the design
  project knows what landed.
