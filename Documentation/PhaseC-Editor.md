# Phase C: Editor

Status: **implemented; 67 automated tests pass; app launches with its window on screen and the
preview rendering. Hands-on review by the user pending (checklist below).**
Date: 2026-11-20 · Apple M5 Pro, macOS 27.2.1.

## What changed

- **The app is now a regular windowed SwiftUI app** (Dock icon, one editor window). The
  live-wallpaper pieces are gone: the menu bar item, the reopen dialog, `Core/Desktop`, the
  desktop diagnostics, and `LSUIElement`. `Prototype/` remains as the Phase 1 reference.
- **Command-line modes still work** (`--export`, `--snapshot`, `--phase-a-test`). `main.swift`
  handles them before SwiftUI starts.

## Editor

| Area | Contents |
|---|---|
| Preview | The animated gradient at the export target's aspect ratio, rendered at **export fidelity** (field at ½ of native pixels; grain and dither per native pixel). It pauses automatically when the window is hidden or fully covered |
| Time bar | Play/pause (Space) and a scrubber (0–30 min of animation) to pick the moment for a still or the start of a sequence |
| Colors | (Phase D: the old palette picker was removed; presets are chosen in the sidebar.) Current palette name in the header, one row per color: `ColorPicker`, hex, move toward dark/light, remove. Add Color (2–8 colors), Shuffle Colors, and a ramp strip. Editing a preset makes it **Custom** |
| Movement | Speed, Complexity, Softness (blend) |
| Finish | Grain, Brightness, Saturation |
| Variation | Seed field and new-seed button ("same seed + settings = same wallpaper") |
| Toolbar | Play/Pause; **Randomize** (click = everything, ⌘R; menu: colors only ⇧⌘R, movement only ⌥⌘R); **Export…** (⌘E) |
| Export sheet | Type (Dynamic / Light & Dark / Still PNG / Still HEIC / Variations), **Name** (pre-filled: palette name + "Dynamic" or "Light-Dark"; edited palettes get "Custom <date>"; used as typed, with a number added only on a clash), Size (**current display**, i.e. the one the window is on, by default, with a **Use Current Display** reset button; other displays, presets, or a **custom** W × H up to 16384), Frames (8/12/16/24), Count, Folder (default `~/Pictures/Gloaming`, remembered). Afterwards: **Show in Finder** and **Open Wallpaper Settings** |

### Behavior details

- **Undo/redo** goes through the window's standard Edit menu (⌘Z / ⇧⌘Z), so text fields keep
  their own undo.
  - One step per gesture: sliders commit when released. A run of color-picker changes is
    one step, registered on the **first** change so ⌘Z works immediately, with later
    changes folded in until 0.6 s of inactivity.
  - The scrubber position isn't part of history, and undo never rewinds playback. Seed
    changes are undoable.
- **Live updates:** palette changes crossfade (0.25 s for color edits, 1.5 s when switching
  presets) and parameter changes ease in. **While paused**, changes apply instantly and the
  preview redraws a single frame.
- **Export uses the preview's current moment:** the preview clock is copied into the look
  right before rendering. Tested: the exported file equals, byte for byte, an offscreen
  render of the look at that moment. It isn't compared with the preview's own pixels, which
  differ in grain (re-seeded every frame) and, for up to 1.5 s after an edit, in mid-crossfade
  or easing states.
- **Playback doesn't churn the inspector:** the scrubber reads a separate `playhead` that's
  refreshed 10× a second. `look.time` is updated only on edits, pause and export.
- **Randomize** generates palettes that run dark to light with a real lightness spread, using
  harmonious hues (analogous, split-complementary or triadic), always within sRGB.
- Export runs on the main thread (0.5–4 s, measured in Phase B). The sheet shows "Exporting…"
  and disables Export until it finishes.

## Toolchain notes (Command Line Tools only)

- **`@State` can't be used.** In the macOS 27 SDK it's a compiler macro whose plugin ships
  only with full Xcode. Views store `State(initialValue:)` directly and use
  `.wrappedValue` / `.projectedValue`; the code comments where this is done. `@Bindable`,
  `@Environment` and `@Observable` work.
- **The macOS 27 SDK also has a type named `RGBColor`.** App code refers to ours as
  `WallpaperCore.RGBColor`.

## Tests (`./Scripts/test.sh`: 67 tests, 8 suites, all passing)

New in Phase C:
- **Randomizer:**
  - deterministic with a seed;
  - 40 seeds checked: 4–5 colors, strictly increasing lightness, spread > 0.4, all in gamut;
  - each randomize kind changes only what it says.
- **Editor model:**
  - a slider drag is one undo step, with redo;
  - undo doesn't rewind the scrubber, and scrubbing isn't recorded;
  - seed changes are undoable and move the phase;
  - a new edit clears redo;
  - color edits become Custom, values are clamped, and the 2–8 limit holds;
  - color-picker changes coalesce into one step;
  - moving colors works;
  - while paused, edits apply instantly and request a redraw;
  - **an export taken mid-playback equals an offscreen render of that moment**;
  - export settings persist;
  - **through a real `UndoManager`** (what the Edit menu uses): undo/redo of an edit, ⌘Z
    immediately after a color pick, and a color run after another edit undoing only the run;
  - playback moves the playhead without changing the look, and pausing folds the time in;
  - suggested export names, and exports using the typed name (trimmed), adding " 2" on a clash, or falling back when blank.

## Smoke run (measured)

`build/Gloaming.app --exit-after 9`: the window list shows the app's process with an
on-screen window "Gloaming", 1240×780. The preview measured **58 FPS** (first 4 s,
including startup), field 853×554 → output 1706×1108 px, and the app quit on schedule. The CLI
still exports. There are **no screenshots of the UI**: Screen Recording isn't granted to the
shell, so the layout needs a person.

## Hands-on checklist (user)

```bash
./Scripts/bundle.sh && open build/Gloaming.app
```

1. The window opens; the preview animates smoothly; Space pauses and plays.
2. Drag each slider: the preview responds live, with nothing jumpy.
3. Change a color with the picker; add, remove and reorder colors; the preset menu shows **Custom**.
4. Randomize a few times (⌘R, ⇧⌘R, ⌥⌘R): are the results pleasant?
5. Undo/redo (⌘Z / ⇧⌘Z) after a slider drag, a color edit and a randomize. Also type in the
   Seed field and check its own undo.
6. Scrub while paused: the preview follows the scrubber.
7. Export one of each type, and try a custom size. Check that **Open Wallpaper Settings** lands
   on the Wallpaper pane and that a Dynamic export shows "Dynamic".
8. **Light & Dark export** (never checked on screen; Phase A's A-3 and A-4 are open): apply it,
   switch Light ↔ Dark, and check the lock screen in both. System Settings should say "Automatic".
9. CPU in Activity Monitor: note it with the window **visible and playing**, then covered or
   minimized, where it should drop to near zero.
10. While dragging in the macOS color panel (try a vivid P3 color), watch for jitter or snapping
    in the preview or the color well.

## User feedback (2026-11-20)

- The UI "feels pretty good": color selector and randomizer called out.
- Requested and added: a name field for exports (the hard-coded `<Palette> Day` was unclear),
  and a way to reset the size to the current monitor.

## Not done / next

- **Phase D (presets):** mood, season and vibe presets that include day arcs; saving and
  sharing user presets; a browser with thumbnails.
- **Phase E:** Set as Wallpaper, app icon, README, CI, signing and notarization.
- Export blocks the UI briefly; moving rendering off the main thread is a possible polish item.
