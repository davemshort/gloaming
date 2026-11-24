# Phase A2: Sun-Position (Solar) Wallpapers

Status: **solar format works on macOS 27 (Dynamic label, Light/Dark stills, lock screen). macOS appears to select frames by altitude; mapping reworked to light-based altitudes on 2026-11-24, noon fix (afternoon entry for the noon frame) confirmed on screen; dusk check pending.**
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
  export at clock time *i/N* × 24 h (same day arc). *Originally* tagged with the sun position on a
  40° N equinox reference day; **replaced on 2026-11-24 by light-based altitudes** (see "Rework"
  below) after macOS turned out to select by altitude.
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

## Correction: macOS selects by altitude, not angular distance (2026-11-24)

Screenshots were matched against every frame of the applied `Winter Dynamic.heic` (48×27
downsample, center crop, RMSE in 8-bit levels):

| Time | Real sun (≈35.8° N, 90.7° W) | Frame shown (RMSE) | Angular-distance rule | Nearest altitude, same side of noon |
|---|---|---|---|---|
| 7:57 AM | 11.3°, az 126° | **08:00** (0.7) | 08:00 ✅ | 08:00 ✅ |
| 1:16 PM | 30.2°, az 204° | **16:00** (0.7; 14:00 was 33.7) | 14:00 ❌ | 16:00 ✅ |

So the "Reference-path check" above was wrong: the 1:21 PM indigo on 2026-11-23 was the
16:00 frame, not 14:00. The observations fit **nearest altitude among frames on the same side
of solar noon** (rising vs setting); azimuth only seems to decide the side. Still inferred from
two data points.

Consequence for the 40° N reference: frames are tagged 50° (noon) and 42° (10:00/14:00), which
a late-November sun at 36° N (max ≈ 34°) never reaches. Predicted today: 12:00 frame never
shows, 10:00 only 11:00–12:00, 14:00 only 12:00–13:00, 16:00 from 13:00, **dusk (18:00) from
about 16:00, before the ~16:55 sunset**, night (20:00) from about 18:00. The mapping needs
reworking around altitude: tag each frame with the altitude at which it should appear, chosen so midday frames are reachable in winter.

## Rework: light-based altitudes (2026-11-24)

`SunPath` now tags frames by the light each clock time represents, not by a reference latitude.
Altitudes for the morning half (afternoon mirrored), interpolated linearly for any frame count:

| Clock time | 00:00 | 02:00 | 04:00 | 06:00 | 08:00 | 10:00 | 12:00 |
|---|---|---|---|---|---|---|---|
| Altitude | −50° | −30° | −12° | −4° | +5° | +15° | +28° |

Azimuths still follow the 40° N equinox path; they only mark morning (< 180°) vs afternoon.
Frames switch halfway between neighboring tags, so dawn/dusk switch at +0.5° (just before sunset),
the blue hour starts at −8°, and the noon look appears above 21.5°.

Simulated with the nearest-altitude-per-side rule (dusk start vs sunset, hours of noon look):

| Location | Dec | Mar | Jun |
|---|---|---|---|
| Miami 26° N | −7 min, 3.3 h | −5 min, 4.3 h | −6 min, 5.1 h |
| Jonesboro 36° N | −8 min, 2.4 h | −7 min, 4.2 h | −8 min, 5.3 h |
| London 51° N | −11 min, 0 h | −8 min, 3.5 h | −12 min, 5.6 h |
| Oslo 60° N | −17 min, 0 h | −11 min, 2.7 h | −17 min, 5.8 h |
| Sydney 34° S | −7 min, 5.3 h | −6 min, 4.3 h | −7 min, 2.6 h |

The old 40° N tags gave dusk 50 min to 2.8 h before sunset under the same rule. Under a pure
angular-distance rule *no* fixed tag set works across seasons (sunrise azimuth swings ±30°), and
Apple's own solar wallpapers work worldwide, which also argues for the altitude rule.

Open questions:
- **The noon frame's side.** Its azimuth is exactly 180°. If macOS treats it as afternoon only, the
  noon look starts at solar noon and late morning stays on the 10:00 look (simulated above). A
  second `si` entry for the noon image at 179.9° might fix that; untested.
- Far north in winter the noon look never shows; an export option to tune for latitude could
  lower the midday tags. Not planned unless needed.

Export for testing: `build/sun/Winter Dynamic (light-based).heic` (tags read back: −50, −30, −12,
−4, 5, 15, 28, mirrored; `ap = {l: 6, d: 0}`). 97 tests pass.

Predictions for Jonesboro, 2026-11-25, with the new file (altitude rule / angular rule):
08:00–10:00 10:00 look (both); **10:30–11:30 10:00 / 12:00**; 12:00–13:00 noon (both);
**13:30–14:30 12:00 / 14:00**; 16:00–16:30 16:00 (both); **17:00–17:30 18:00 / 16:00**.

### Observation 3 and the noon fix (2026-11-24, 1:44 PM)

The light-based file was applied at 1:44 PM (Index.plist `LastSet` 19:44:43 UTC) and showed the
**14:00** frame (RMSE 0.8), not noon. Sun ≈ 27.5°, az ≈ 210°. All three observations fit
**nearest altitude on the same side of noon, with azimuth exactly 180° counted as morning**:
the noon frame (28°, 180°) wasn't a candidate after solar noon, leaving 14:00 (15°) as nearest.

Fix: frames at exactly noon/midnight get a second `si` entry on the afternoon side (181° / 359°,
same altitude). Test file: `build/sun/Winter Dynamic (noon fix).heic` (14 entries, 12 images).
Expected if macOS accepts repeated image indices: the noon look in the early afternoon (sun
above 21.5°, until ≈ 2:35 PM today), then 14:00, 16:00 from ≈ 3:45, dusk at ≈ 4:50.

**Result (1:50 PM):** the noon-fix file showed the **12:00** frame (RMSE 0.7; next best 34.9).
macOS accepts a repeated image index in `si`, and the afternoon entry makes noon reachable after
solar noon. Selection rule now supported by four observations. Remaining checks: dusk at
≈ 4:50 PM today, and tomorrow's morning (noon look from ≈ 9:00 AM).
