# Phase A2: Sun-Position (Solar) Wallpapers

Status: **solar format works on macOS 27: Dynamic label, correct sun-based frame, working Light/Dark (Still) without `apr`. Midday, sunset and lock-screen checks pending.**
Date: 2026-11-23 · Apple M5 Pro, macOS 27.2.1.

**Question:** can Gloaming export Apple's sun-position format (`apple_desktop:solar`), so a
wallpaper follows the real sun for the user's location and date? Does that format also give
working Light/Dark (Still), which the clock format (`h24`) can't (Phase A, A-5c)?

**Requirement (user decision):** Location Services must be on. macOS uses its own system
services to find the sun; Gloaming never reads location.

## Test files (`build/solar-test/`)

Generate with `build/Gloaming.app/Contents/MacOS/Gloaming --solar-test build/solar-test`
(size = current display).

| Frame | Sun position written | Palette |
|---|---|---|
| 0 Night | −30°, north (0°) | Aurora (purple) |
| 1 Dawn | 0°, east (100°) | Sunset (pink/orange) |
| 2 Morning | +25°, southeast (135°) | Spring (green) |
| 3 Noon | +45°, south (180°) | Ocean (blue) |
| 4 Afternoon | +25°, southwest (225°) | Desert (sand) |
| 5 Dusk | 0°, west (260°) | Ember (dark red) |

- `solar-a (solar only).heic`: `solar` tag with `ap = {l: 3 (Noon), d: 0 (Night)}`.
- `solar-b (solar + apr).heic`: the same plus a separate `apr` tag.

Metadata was read back with ImageIO: 6 images, tags present (solar-b also has `apr`), 6016×3384.
Round-trip test: `ExportTests.solarRoundTrip`.

## Manual results (pending)

| # | Check | solar-a | solar-b |
|---|---|---|---|
| S-1 | System Settings menu label (Dynamic / Automatic / other) | **Dynamic**: "This wallpaper changes throughout the day, based on your location." | **Dynamic** (same text) |
| S-2 | Frame shown now (expected around 9:30 AM on 2026-11-23: **Morning, green**) | **Green ✅** | **Green ✅** |
| S-3 | Light (Still) shows Noon (blue); Dark (Still) shows Night (purple) | **Works ✅** (dark = purple) | Works, behaves the same |
| S-4 | Lock screen matches the desktop | **Yes ✅** (green) | not checked |
| S-5 | Midday: Noon (blue) or Afternoon (sand) | | |
| S-6 | Around local sunset (~5 PM): Dusk (dark red), then Night (purple) after dark | | |
| S-7 | (Optional) Location Services off: what shows | | |

## Findings so far (2026-11-23)

- macOS honors solar files written by Gloaming and placed the sun correctly (the Morning frame at
  about 9:30 AM).
- **Unlike `h24`, the `solar` tag alone gives Dynamic *and* working Light/Dark (Still):** macOS
  uses the `ap` entry inside `solar`. Adding `apr` changed nothing (still "Dynamic", still
  follows the sun), so solar exports don't need it. Write solar only.

## Productized (2026-11-23): "Dynamic (follows the sun)", the default export type

- **Mapping** (`Core/Export/SunPath.swift`): frame *i* of N is rendered exactly like a clock
  export at clock time *i/N* × 24 h (same day arc). It's then tagged with the sun's position at
  that time on a **reference day**: latitude 40° N at an equinox (sunrise due east 06:00, noon
  50° due south, sunset due west 18:00, midnight −50° north). macOS shows whichever frame's
  reference position is closest to the real sun, so dawn and dusk colors follow real sunrise and
  sunset through the seasons.
- **File:** `solar` tag only (no `apr`), `ap` = frame nearest noon (light) and nearest midnight
  (dark). Light/Dark (Still) work (S-3).
- **Editor:** the export sheet lists "Dynamic (follows the sun)" first and selects it by default.
  Its description notes that Location Services are required. "Dynamic (follows the clock)"
  remains for people who keep Location Services off, and its description now says its
  Light/Dark stills don't work.
- **CLI:** `--export sun`.
- **Tests:** reference sun positions (sunrise/noon/sunset/midnight, east in the morning, west in
  the afternoon, bounds), the exported file (12 frames, solar only, noon frame at 50°/180°,
  `ap = {l: 6, d: 0}`), and the default type. 96 tests pass.
- **Real export:** `build/sun/Winter Dynamic.heic`, 6016×3384, 12 frames, 21 MB.

Still to confirm on screen: switching through the day (S-5, S-6) with the real export.

## Reference-path check (2026-11-23, afternoon)

At 1:21 PM the desktop showed an indigo frame. I first blamed the reference noon (50°) being
higher than the winter sun (~34° at ~36° N in late November) and tried a 55° N reference (35°
noon). A simulation of today's real sun at the user's approximate location, assuming macOS
picks the frame at the smallest angular distance, showed:

| | 40° N reference (kept) | 55° N reference (rejected) |
|---|---|---|
| Noon frame shown | 11:00–12:30 | 11:00–12:30 (same) |
| 1:21 PM | 2 PM frame (what was seen; correct) | 2 PM frame |
| Dusk frame after the ~4:55 PM sunset | from 5:00 PM | from 5:30 PM (late) |
| Night (8 PM) frame | from 7:00 PM | from 7:30 PM |

The diagnosis was wrong: azimuth keeps a low, due-south winter sun on the noon frame. The
indigo was the correct 2 PM frame. 40° N stays. The frame-selection rule is inferred from
observations, not documented by Apple.

**Morning check (2026-11-24, 7:57 AM, about an hour after sunrise):** the desktop showed the
Winter 8 AM frame (mauve, pink glow top center, dark lower right), matching the simulation
(7:00–8:30 → 8 AM frame). Sunset (S-6) is still to be checked.
