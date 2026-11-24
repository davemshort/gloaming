# Phase B: Export Core

Status: **implemented; 48 automated tests pass; measured on one Mac. A real 12-frame export
shows as Dynamic in System Settings.**
Date: 2026-11-20 · Apple M5 Pro, macOS 27.2.1.

## What was built (`Gloaming/Core`)

| Piece | File | Notes |
|---|---|---|
| `Look` | `Models/Look.swift` | Palette, parameters, seed, time and day arc. Codable; it reproduces a wallpaper exactly |
| `DayArc` | `Models/DayArc.swift` | Brightness, saturation and optional palette keyframes over 24 h (smoothstep, wraps at midnight), plus motion across the day |
| `ExportSize` | `Export/ExportSize.swift` | Size presets (8K to MacBook Air 13″), connected-display sizes, `WxH` parsing, 16384 px limit |
| `FrameRenderer` | `Export/FrameRenderer.swift` | Renders at any size up to 16K, reusing GPU targets across frames |
| `ImageFiles` | `Export/ImageFiles.swift` | Atomic writes (temp file in the same folder, then move), unique names, still PNG/HEIC |
| `DynamicHEIC` | `Export/DynamicHEIC.swift` | Frames produced on demand; `h24` and `apr` tags (both by default); memory-bounded |
| `WallpaperExporter` | `Export/WallpaperExporter.swift` | Still, time-of-day, light/dark, variations, contact sheet |

Ramp-based initializers were added to `PaletteTransition` and `SceneState`, so day-arc palette
blends are mixed in OKLab at the ramp level.

## Formats

| Export | Output | Details |
|---|---|---|
| Still | `.png` or `.heic` | The look as designed |
| **Follows the sun** (default since 2026-11-23) | `.heic`, N frames (default 12) | Same frames as time of day, tagged with sun positions (`solar`). Works on desktop and lock screen; Light/Dark (Still) work. Needs Location Services. See PhaseA2-Solar.md |
| Time of day | `.heic`, N frames (default 12) | Frame *i* at clock time *i/N* × 24 h, rendered with the day arc. `h24` only, so System Settings shows **Dynamic** and it follows the clock. Light/Dark (Still) keep the current frame (macOS ignores `ap`); adding `apr` would make macOS ignore the clock (Phase A, A-5c) |
| Light/dark | `.heic`, 2 frames | Day arc at noon (light) and at midnight (dark) |
| Variations | N stills | Seeds spaced 7919 apart, for macOS's "rotate through folder" |
| Contact sheet | `.png` | Every time-of-day frame tiled with its clock time; for reviewing and tuning the arc |

## Decisions (with evidence)

- **Determinism.** Export scenes are built settled at an exact phase (never advanced), with no
  transition running, and grain seeded from the look. Test: two renders produce identical bytes;
  a different seed gives different bytes. Other GPUs may differ by a level or two.
- **HEIC quality 0.75.** Darkest regions of Monochrome and Ember at 3840×2160, PNG vs HEIC at
  0.9, 0.75 and 0.6, viewed with an 8× contrast stretch: **no banding at any quality**. The
  dither survives. Grain gets smeared at 0.6 and is intact at 0.75. 0.75 files are about 2.4×
  smaller than 0.9.
- **Memory.** ImageIO keeps every frame added to a HEIC until it finalizes, so render-on-demand
  alone didn't bound memory. Above 512 MB of raw frames, frames after the first go in as
  in-memory HEIC (frame 0 keeps the direct path because it carries the metadata). The cost is a
  second lossy encode on those frames: mean 0.2, max 5 levels (out of 255) versus direct.
- **Day arc tuning** was done from contact sheets. With motion 600 s, neighboring frames looked
  unrelated; 240 s (20 s apart for 12 frames) evolves visibly. Night brightness of 0.55 linear
  was barely visible; 0.3 gives a clear arc.

## Measured (single runs; peak = lifetime max `phys_footprint` of the process)

| Export | Size | Time | Peak memory | File |
|---|---|---|---|---|
| Time of day, 12 frames | 3600×2338 | 0.57 s | 631 MB | 11.8 MB |
| Time of day, 12 frames | 6016×3384 | 1.92 s | 646 MB | 28.1 MB |
| Time of day, 12 frames, before the memory fix | 6016×3384 | 1.13 s | 1463 MB | (q 0.9) 70.7 MB |
| Time of day, 16 frames | 7680×4320 | 3.76 s | 930 MB | 60.3 MB |
| Light/dark | 3600×2338 | 0.13 s | 278 MB | 1.9 MB |
| Still HEIC (q 0.9) / PNG | 7680×4320 | 0.18 s / 1.10 s | 667 / 444 MB | 9.6 / 36.6 MB |

The 8K 16-frame file reads back with 16 images, both tags, and 7680×4320, and decodes (first
and last frames in 0.26 s). The 12-frame display-size file reads back with 12 images and both tags.

## Tests (`./Scripts/test.sh`: 48 tests, 6 suites, all passing)

New in Phase B:
- **Day arc:** exact keyframes, smoothstep, wrap at midnight, empty or single keyframe, palette
  blending.
- **Look:** phase and seed math, Codable. **Export size:** parsing and limits.
- **Pipeline (needs a Metal device):**
  - determinism, and different seeds differ;
  - night darker than noon;
  - still PNG/HEIC size and sRGB;
  - time-of-day frame count, times *i/N*, `apr` = {l: 6, d: 0} for 12 frames;
  - light/dark: two frames, dark darker;
  - variations distinct;
  - no overwriting (`same 2.png`) and no partial files after a failed write;
  - oversized exports rejected.

## Command-line export (until the editor exists)

```bash
B=build/Gloaming.app/Contents/MacOS/Gloaming
$B --export time       --out ~/Desktop/test --size 3600x2338 --frames 12 --palette sunset --seed 5
$B --export appearance --out ~/Desktop/test --palette ocean
$B --export still      --out ~/Desktop/test --format heic --size 6016x3384
$B --export variations --out ~/Desktop/test --count 6
$B --export sheet      --out ~/Desktop/test --frames 12      # review the day sequence
```

Each run prints its time, peak memory and the files it wrote. `--size` defaults to the main
display's native resolution. Output never goes to `~/Pictures` unless you ask for it.

## Not done / next

- **Manual check (2026-11-20):** `build/phase-b2/Aurora Day.heic` (12 frames, time tag only) shows **Dynamic** in System Settings ✅. Earlier: apply `build/phase-b2/*.heic` (regenerated after A-5c) (12-frame Aurora/Sunset days, Ocean
  light/dark) and confirm the Dynamic / Light / Dark menu and the frame for the current time.
- **Phase C (editor)** will remove `Core/Desktop` and the live-wallpaper menu from the app.
- The sandboxed build will need the Pictures read/write entitlement for the default folder
  (Phase E).
