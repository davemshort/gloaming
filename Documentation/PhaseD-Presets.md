# Phase D: Presets

Status: **implemented; 89 automated tests pass; built-in library reviewed visually; day strip
verified against a real export; app icon added. Remaining hands-on items in the checklist.**
Date: 2026-11-20 · Apple M5 Pro, macOS 27.2.1.

## Built-in library (19 presets, defined in code)

| Group | Presets | Notes |
|---|---|---|
| Moods | Calm, Focus, Energize, Dreamy | Each sets its own speed, complexity, softness and grain (e.g. Focus: slow and muted; Energize: fast and vivid) |
| Seasons | Winter, Spring, Summer, Autumn | **Palette keyframes** for night, morning and evening. Noon has no override, so the preview and stills match the noon frame of a Dynamic export |
| Vibes | Aurora, Sunset, Ocean, Ember, Forest, Monochrome, **Spooky, Neon, Nebula, Desert, Pastel** | The original six palettes, plus five added after review (new entries are appended so existing indices stay stable). Neon and Pastel were retuned after the first render: Pastel's high softness hid its pinks, and Neon rarely reached its cyan |

Every palette, keyframe palettes included, runs dark to light (tested), because the shader
maps its noise field onto the palette in order. Built-in IDs are stable across launches.
Review sheets are generated with
`Gloaming --export presets --out <dir>`: all built-ins as stills, plus each season's
12-frame day. Winter, for example, goes navy at midnight → rose at dawn → icy blue at noon →
violet in the evening.

## Preset files (`.gloamingpreset`, versioned JSON)

```json
{ "formatVersion": 1, "id": "…", "name": "Frost", "category": "mine",
  "look": { "palette": {…}, "parameters": {…}, "seed": 101, "time": 0, "dayArc": {…} } }
```

**Treated as untrusted input**, since presets are meant to be shared:
- Missing fields fall back to defaults, at every level (look, palette, parameters, day arc,
  keyframes, colors).
- A newer `formatVersion` is **refused** with "made with a newer version of the app…", never
  half-loaded.
- Everything is sanitized:
  - parameters clamped (non-finite values → defaults);
  - colors clamped to 0–1;
  - 2–8 colors kept;
  - names capped at 80 characters;
  - at most 24 keyframes, with motion clamped;
  - files over 1 MB rejected before parsing.

## Storage

`~/Library/Application Support/Gloaming/Presets/<UUID>.gloamingpreset`:
- The folder is created on the first save.
- Files are named by UUID with the name inside, so renaming doesn't touch the filesystem and
  names can't collide.
- Writes are atomic; **Delete moves the file to the Trash**.
- Unreadable files are skipped and logged, never deleted.
- **Import** assigns a new ID if the file's ID already exists (including a built-in's), so
  importing never overwrites.

## Editor

- **Sidebar:** Moods / Seasons / Vibes / My Presets, each row with a rendered thumbnail. Season
  rows say "Dawn · Day · Dusk", and the current preset shows "Edited" once you change it.
  Selecting a row applies it with a 1.5 s crossfade. **A run of selections (clicking or
  arrowing through the list) is one undo step**, and undo also restores which preset was current.
- **Context menu:** Duplicate to My Presets, Rename… (yours), Export Preset File…, Move to
  Trash (yours).
- **Presets toolbar menu:** Save Changes to "…" (⌘S, your presets only), Save as New Preset…
  (⇧⌘S, suggested name such as "My Winter"), Import Preset File… (⌘O), Export "…" as File….
- **Window title** shows the preset's name, with "Edited" when modified.
- **Through the Day** inspector section: six frames (00, 04, 08, 12, 16, 20 h) of what a Dynamic
  export shows, rendered with the exporter's own scenes (tested equal) and refreshed 200 ms
  after edits settle.
- **Color edits on a season preset** remove its dawn, dusk and night palettes but keep the
  brightness curve, so the whole Dynamic export uses your colors. The day strip shows this
  immediately, and the section footer explains it. Parameter edits keep the season palettes.
- Export names default to the preset name, e.g. "Winter Dynamic".

## Tests (`./Scripts/test.sh`: 89 tests, 12 suites, all passing)

New in Phase D:
- **Built-ins:**
  - coverage by group, unique IDs and names, stable IDs;
  - **every palette dark to light** (all 14 presets, keyframe palettes included);
  - season noon has no override;
  - every built-in round-trips through the file format.
- **Untrusted files:** missing fields → defaults; clamping and bounds (500 keyframes, 20 colors,
  a 500-character name, out-of-range values); newer format refused; garbage, no-version and
  oversized files rejected; an old look without a day arc still decodes.
- **Store:**
  - save, rename, duplicate (user and built-in), delete, reload;
  - files named by UUID;
  - corrupt files skipped, reported and kept;
  - export then import gets a new identity on conflict, including for a built-in;
  - in-memory mode.
- **Editor:**
  - apply sets the look and current preset;
  - a run of selections is one undo step, and undo restores the current preset;
  - edits mark the preset modified;
  - export name uses the preset;
  - color edits drop season palettes but keep brightness, while parameter edits keep them;
  - save as new, then save changes;
  - built-ins can't be overwritten or deleted, and deleting the current preset clears it;
  - day-strip thumbnails equal the export's scenes.

## Hands-on checklist (user)

```bash
./Scripts/bundle.sh && open build/Gloaming.app
```

1. Browse the sidebar with the mouse and the arrow keys; check that thumbnails appear and
   crossfades are smooth. Then ⌘Z once: it should go back to where you started.
2. Edit a preset and check that "Edited" shows in the row and the title. Then Save as New
   (⇧⌘S), rename it, duplicate it, and move it to the Trash.
3. Export a preset file, then import it again (⌘O). It should appear in My Presets.
4. Choose **Winter**, look at Through the Day, then export Dynamic and compare it in System
   Settings with the strip. Change a color and check that the strip switches to your colors
   all day.
5. Carried over from Phase C: check the Light & Dark export in both appearances and on the lock
   screen (Phase A's A-3 and A-4).

## User feedback (2026-11-20)

- The inspector still had Phase C's palette picker, labelled "Preset" but listing only the six
  palettes, which conflicted with the sidebar. **Removed:** the section is now **Colors**, with
  the palette's name in its header; presets are chosen only in the sidebar (the six palettes
  are the Vibes).

## Completion checks (2026-11-20)

- **Day strip vs. real export:** `--export time --preset winter --frames 12 --size 3600x2338`
  was compared frame by frame with the app's own render of the same hours, downscaled to the
  same size. Mean absolute difference was **1.2–1.3 levels (of 255) for all 12 frames**
  (grain and HEIC compression), so the strip shows what the export contains.
- **Day strip aspect ratio** now follows the export target (current display or chosen size)
  instead of a fixed 16:9, so its framing matches the export.
- `--preset NAME` added to command-line export (built-in presets by name).

## App icon

"Orb", chosen by the user from four variants. It's a warm Sunset gradient with a soft glowing
sun, rendered by the app's own engine (`Gloaming --icon DIR --icon-variant orb`):
- an 824 pt continuous-corner squircle on the 1024 macOS icon grid;
- drop shadow, top highlight and a hairline edge;
- no grain, which turns to noise at small sizes.

The variant sheet shows each one at 128/64/32/16 px; Orb was the only one recognizable at 16 px.
`Gloaming/Resources/AppIcon.icns` (10 sizes) and `AppIcon-1024.png` are committed
assets, and `Scripts/bundle.sh` copies the icon in and sets `CFBundleIconFile`.

Not done: a macOS 26+ Icon Composer (`.icon`, Liquid Glass) version needs full Xcode. Recent
macOS may draw this classic `.icns` with a system frame; check how it looks in the Dock.

## Name research (2026-11-20, web search only; not legal clearance)

| Name | What turned up |
|---|---|
| **Gloaming** | No Mac app or GitHub project found. An iOS kids' storybook app, *Gloaming Tales*; a US mark **GLOAM** in Class 42 (CRM/event software, a different word and field); a UK **Gloaming** mark for footwear. No GLOAMING software (Class 9) mark found |
| **Sundial** | Crowded: several App Store apps (*Sundial Solar & Lunar Time*, *Sundial Mobile Punch*, other Mac listings), a Product Hunt *Sundial* app, and live US **SUNDIAL** registrations including one in Class 9 (Reg. 6412381) |

Gloaming looks far clearer than Sundial. Before release, confirm with a USPTO Trademark Search
(Class 9 and 42) and an App Store name check. Related apps in the same space: Equinox,
Dynaper and 24 Hour Wallpaper (dynamic wallpaper creators).

## Deferred

- Double-click to open `.gloamingpreset` files (document type and UTI registration) → Phase E.
- A keyframe editor for day arcs (edit dawn, dusk and night colors directly).
