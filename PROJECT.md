# Project: Open-Source Gradient Wallpaper Generator for macOS (v2)

> **v2, 2026-11-20.** The direction changed from a continuously animated desktop wallpaper
> to a **generator** that exports native macOS wallpapers. The v1 spec is archived at
> `Documentation/archive/PROJECT-v1.md`, and the reasons are in "Why the change" below.
> **Name: Gloaming** (renamed from the working title "DynamicWallpaper" on 2026-11-20; web search found no conflicting Mac app or software trademark; confirm with a USPTO search before release).

## Objective

Build a native, open-source macOS app where people design fluid, atmospheric gradient
wallpapers with a live animated preview, then export them as **wallpapers macOS uses
natively, on the desktop and the lock screen**:

- **Still wallpapers:** a single full-resolution image.
- **Dynamic wallpapers:** a `.heic` that macOS changes **through the day** or with
  **light/dark appearance**. The gradient's movement becomes a sequence of frames.

The app must be an original implementation, not a reproduction of another app's code,
shaders or visual assets.

## Why the change

Phases 1 and 2 showed that a live desktop wallpaper is feasible with public APIs (a window at
the desktop level). The approach has hard limits, though:
- The lock screen, login window and Mission Control thumbnails always show the **system**
  wallpaper.
- It needs a background process, power management, occlusion handling and display
  hot-plug handling.
- Menu bar managers can hide its only control surface.

Exporting native wallpapers puts the result everywhere macOS shows a wallpaper, needs no
background process, and keeps the movement as time-of-day change. The Phase 1 window code is
**shelved**: kept in `Prototype/` for reference and not part of the product.

## 1. Technology Stack

- **Language:** Swift 6
- **Interface:** SwiftUI, AppKit where necessary
- **Rendering:** Metal and Metal Shading Language (engine from Phase 2)
- **Export:** ImageIO (PNG, HEIC, multi-image HEIC with metadata)
- **Persistence:** user presets as JSON files in Application Support; preferences in UserDefaults
- **Build:** Swift Package Manager. Must build and test with the **Command Line Tools alone**.
  Shaders compile at runtime; tests run via `Scripts/test.sh`.
- **Minimum macOS:** 14 (Sonoma)
- **Distribution:** direct download (Developer ID + notarization). Keep the app
  sandbox-compatible so a Mac App Store build stays possible.
- **License:** MIT

No third-party dependencies, no Electron or web views, no analytics.

## 2. Rendering Engine (done in Phase 2, keep)

The Phase 2 engine in `Gloaming/Core/Rendering` is the basis. It has:
- periodic, domain-warped gradient noise, with no loops and no seams;
- OKLab palette ramps and crossfades;
- two passes (reduced-resolution field, then a full-resolution composite with B-spline
  upsampling, grain and dither);
- an extensible `FieldPass` list.

The animation clock maps directly onto export: **time in the preview = position in the
exported sequence.**

Additional requirements for export:
- Render at arbitrary output sizes, up to at least 6K (6016×3384) and preferably 8K, without
  blowing GPU memory (tile if needed).
- Exports must be deterministic: the same preset, seed and time give the same pixels.
- Grain and dither are applied at output resolution.

## 3. Editor

A single main window, built in SwiftUI.

- **Live preview** of the animated gradient at the aspect ratio of the chosen target display.
- **Playback controls:** play/pause, speed, and a **time scrubber** to choose the frame for a
  still or the start of a dynamic sequence.
- **Adjustments:**
  - sliders for speed, complexity, blend softness, grain, brightness, saturation, and
    later warp/scale;
  - **color pickers** for each palette color (`ColorPicker`), with add, remove and reorder
    (2–8 colors);
  - randomize: whole look, colors only, or movement only;
  - a seed control, so a look can be reproduced and shared.
- **Undo/redo** for adjustments.
- Every change updates the preview immediately and smoothly; the Phase 2 transitions are
  reused.

## 4. Presets

- Built-in presets grouped by **mood**, **season** and **vibe** (e.g. Calm, Focus, Energize;
  Winter, Spring, Summer, Autumn; Aurora, Sunset, Ocean, Ember, Forest, Monochrome).
- A preset is a complete look: palette, parameters, seed, and for dynamic exports a
  **day arc** (how colors and brightness shift from morning to night).
- Users can save, rename, duplicate and delete their own presets. Presets are stored as
  versioned JSON so they can be shared as files.
- A preset browser shows live or cached thumbnails.

## 5. Export

Default location: `~/Pictures/<App Name>/`. It can be changed and is remembered.

**Target size:** auto-detected from connected displays (offered per display), plus common
presets (5K, 6K, 4K, laptop sizes) and custom. Export at the display's native pixel
resolution.

**Formats:**
1. **Still:** PNG (lossless) or HEIC (smaller), sRGB, with optional Display P3 later.
2. **Dynamic: time of day.** A multi-image HEIC with time-based metadata. N frames (default
   8–16) sampled along the animation and the preset's day arc, assigned to times of day.
3. **Dynamic: light/dark.** A two-image HEIC that switches with system appearance.
4. **Variations:** N stills with different seeds or times into one folder, for macOS's
   "rotate through folder" feature.

**Set as Wallpaper:** an optional button that applies the exported file to selected displays
using the public `NSWorkspace.setDesktopImageURL`. It runs only when the user clicks it.

**Undocumented format, stated plainly:** dynamic HEIC wallpapers use Apple's
`apple_desktop` XMP metadata (`h24` for time of day, `apr` for appearance, `solar` for sun
position). Writing it uses only public ImageIO APIs, but the metadata schema is undocumented
(reverse-engineered, stable since macOS 10.14). The app must:
- isolate this in one module with tests that round-trip the metadata;
- document it in the README and in the app's export help;
- fall back gracefully, so stills always work;
- be checked on every new macOS release (manual checklist item).

Prefer time-of-day (`h24`) over sun-position (`solar`), which would need location.

## 6. Privacy and Security

- No network access at all in v2 (no weather and no update checks in the first release).
- No location. Time-of-day wallpapers use clock times, not sun position.
- No analytics, accounts or telemetry. Everything stays local.
- Writes only to the chosen export folder and the app's own Application Support folder.
- Document every permission. Expected: none beyond user-selected file access.

## 7. Project Structure

```text
Package.swift
Gloaming/
├── App/                  SwiftUI app, windows, commands
└── Core/                 WallpaperCore library (unit-tested)
    ├── Models/           Palette, RenderParameters, Preset, DayArc
    ├── Rendering/        Engine from Phase 2 (Metal, Shaders, Effects)
    ├── Export/           Still, dynamic HEIC (metadata isolated here), variations
    ├── Presets/          Built-ins and user preset storage
    └── Diagnostics/
Tests/WallpaperCoreTests/
Scripts/                  bundle.sh, test.sh
Documentation/
Prototype/                Shelved Phase 1 desktop-window prototype (reference only)
```

`Core/Desktop` (the live desktop windows) is removed from the product when the editor lands.

## 8. Testing

Automated (Swift Testing, `Scripts/test.sh`):
- preset and palette serialization, versioning and migration;
- deterministic rendering (same inputs give the same pixels);
- export dimensions, color space and file validity;
- **dynamic HEIC metadata round trip** (write, read back, decode `h24` and `apr`);
- day-arc frame and time assignment;
- the existing engine tests (layout reflection, seamless wraps, crossfades).

Manual checklist on each macOS release:
- exported still on desktop and lock screen;
- dynamic time-of-day file: correct frame for the current time, switching, and lock screen;
- dynamic light/dark file: switches with appearance, and lock screen;
- "rotate through folder" with variations;
- multi-display "Set as Wallpaper";
- large exports (6K/8K) on Retina and non-Retina screens.

## 9. Phases

- **Phase A (now): feasibility of native formats.** Generate test files (still, dynamic
  time-of-day, dynamic light/dark). Verify on macOS 27 that each one is applied through
  System Settings and shows on the desktop **and lock screen**, and that dynamic switching
  works. Document the results.
- **Phase B: export core.** Still, dynamic and variations writers; day arc; deterministic
  high-resolution rendering; tests.
- **Phase C: editor.** SwiftUI window, live preview, sliders, color pickers, scrubber,
  randomize, undo.
- **Phase D: presets.** Built-in mood/season/vibe library, user presets, browser,
  thumbnails.
- **Phase E: polish and release.** Set as Wallpaper, export help, README, screenshots,
  GitHub Actions build and test, signing and notarization docs.

Development expectations from v1 still apply:
- correctness and native behavior first;
- no fabricated metrics;
- never claim something was tested unless it was;
- explain tradeoffs and recommend an option.
