# Phase 2: Rendering Engine

Status: **implemented; 28 automated tests pass; measured on one Mac. Visual sign-off from the
user is pending.**
Date: 2026-11-19 · Test machine: Apple M5 Pro, macOS 27.2.1, LG HDR 4K at 3008×1692 pt (2×),
60 Hz.

## What was built

| PROJECT.md item | Where | Notes |
|---|---|---|
| Metal rendering pipeline | `Core/Rendering/Metal/` | Shared device, queue and pipelines; per-display view and display link; two passes |
| Initial fluid gradient shader | `Core/Rendering/Shaders/WallpaperShaders.swift` | Periodic gradient noise, two-level domain warp, OKLab palette ramps |
| Animation timing | `Core/Rendering/AnimationClock.swift` | Seamless over unlimited uptime (see below) |
| Palette interpolation | `Core/Models/Palette.swift`, `OKLab.swift`, `Core/Rendering/PaletteTransition.swift` | Six built-in palettes; OKLab ramps; 3 s crossfades that can be interrupted without a jump |
| Adjustable animation parameters | `Core/Models/RenderParameters.swift`, `SceneState` | Speed, complexity, blend, grain, brightness, saturation; changes ease in over ~0.6 s |
| Basic performance measurements | `Core/Diagnostics/` | FPS, frame interval, CPU encode, GPU wall time, CPU %, memory footprint, resolutions, display count, paused state |

## Code layout

```text
Package.swift                 SwiftPM; builds with the Command Line Tools alone
Gloaming/
├── App/                      Thin executable: launch options, menu, reopen dialog, snapshot mode
└── Core/                     WallpaperCore library (unit-tested)
    ├── Desktop/              Desktop-level windows per screen (from Phase 1), coordinator
    ├── Diagnostics/          Event log, frame stats, process metrics, report
    ├── Models/               RGBColor, OKLab, Palette, RenderParameters
    └── Rendering/
        ├── AnimationClock, PaletteTransition, SceneState
        ├── Effects/          FieldPass protocol (extension point) + GradientFieldPass
        ├── Metal/            RenderContext, FrameEncoder, WallpaperView, Snapshot
        └── Shaders/          MSL source (compiled at runtime) + Swift uniform mirrors
Tests/WallpaperCoreTests/     Swift Testing (XCTest isn't available with the Command Line Tools)
Scripts/bundle.sh             Builds build/Gloaming.app (ad-hoc signed)
```

**Deviation from §12:** SwiftPM targets can't share or nest directories. So `Desktop/`,
`Rendering/`, `Models/` and the rest sit under `Gloaming/Core/` as one library target,
and `App/` is a separate target. `Services/` (time, weather, power) will be added in later phases.

## Frame pipeline

```text
display link (per screen) ─► SceneState.advance(timestamp)      [once per timestamp, shared]
                         ─► Field pass   → rgba16Float, ¼ backing resolution, linear sRGB
                         │     FieldPass list: [GradientFieldPass, … future effects]
                         ─► Composite    → drawable, 1 px per point
                               cubic B-spline upsample · brightness · saturation
                               → sRGB encode → grain → TPDF dither (±1 LSB)
```

- **Banding:** the field is half-float. Dithering happens after sRGB encoding, at output
  resolution.
- **Grain** is added at output resolution, never upscaled, and changes every frame.
- **Effects seam:** a new effect implements `FieldPass` and is appended to `SceneState.passes`.
  The frame loop doesn't change. Composite stays a single fixed pass.

## Animation timing: no loops, no jumps, no precision loss

- `phase` is a `Double` that integrates `dt × speed`. Changing speed changes the rate, never the
  position.
- The shader never sees `phase`. It gets six 2-D drift offsets, each `phase × velocity` wrapped
  into `[0, 256)` in Double. Every noise lookup is exactly periodic with period 256:
  - lattice coordinates are masked before hashing;
  - octave frequencies are integer powers of two;
  - only integer constant offsets are added;
  - layer rotations apply to the spatial coordinate, never to the offsets.

  So wrapping an offset is invisible, and Float precision stays constant forever.
- The twelve offset components move at different, incommensurate rates. Each one wraps every 3–18
  hours at speed 1, at different times, so the combined pattern has no practical repeat period.
- **Each frame advances by at most 0.25 s.** After a pause, sleep or a hitch, motion resumes
  where it was instead of leaping ahead.
- **Several displays can share one clock:** it ignores timestamps that are not newer than the
  last one it used.

Verified by test: rendering frames 0.5 s apart **across** a wrap boundary differs by 0.8–1.4
levels (out of 255). An ordinary 0.5 s step elsewhere differs by 1.0–1.4 levels. That means
there's no seam.

## Palettes

Aurora, Sunset, Ocean, Ember, Forest and Monochrome, each with 5 colors. Colors are interpolated
in OKLab into a 256-stop ramp. Crossfades mix the old and new ramps in OKLab in the shader with
smoothstep easing over 3 s. Each palette change gets fresh ramp textures, so frames in flight
are never touched. Custom palettes, randomize, and saved presets are Phase 3.

## Resolution and cost (measured)

All runs: one display, about 20 s each, values from the app's own diagnostics.

| FPS | Field (gradient) | Output (composite) | CPU encode | GPU wall* | CPU (process) | Memory footprint |
|---|---|---|---|---|---|---|
| 30 | 1504×846 (¼) | **3008×1692 (1 px/pt, default)** | 0.26 ms | **2.3 ms** | **3.0 %** | **145 MB** |
| 30 | 1504×846 (¼) | 6016×3384 (native) | 0.27 ms | 5.4 ms | 3.1 % | 359 MB |
| 30 | 3008×1692 (½) | 6016×3384 (native) | 0.25 ms | 6.6 ms | 3.0 % | 309 MB |
| 60 | 1504×846 (¼) | 6016×3384 (native) | 0.21 ms | 3.9 ms | 4.8 % | 359 MB |
| 15 | 1504×846 (¼) | 6016×3384 (native) | 0.24 ms | 5.1 ms | 1.6 % | 280 MB |

\* `gpuEndTime − gpuStartTime` per command buffer. **Not GPU utilization**; it is affected by GPU
clock state (note that 60 FPS shows *lower* per-frame time than 30). No public per-process GPU
utilization API exists, so none is reported. CPU % is measured with `getrusage` (100 % = one
core). Memory is `phys_footprint` (the "Memory" column in Activity Monitor), which includes the
Metal drawables.

**Decision: composite at one pixel per point by default.** On a 2× display, native-resolution
drawables cost about 214 MB more and roughly double GPU time. The gradient itself is rendered at
¼ resolution either way. The only visible difference is grain size, which is 2 physical pixels
instead of 1. `--output-scale 1.0` restores native output. Non-Retina screens get full resolution
under the default.

## Diagnostics

Every 10 s the app writes a report to `~/Library/Logs/Gloaming/events.log`. The same
report appears in the menu's **Diagnostics** submenu and in the reopen dialog:

```text
Displays: 1
Display 4: 30.0 FPS measured · frame interval 33.3 ms · CPU encode 0.26 ms · GPU wall 2.28 ms (not utilisation)
  Render 1504×846 → output 3008×1692
CPU: 3.0 % of one core (measured)
Memory: 145 MB footprint (measured)
GPU utilisation: not available (no public per-process API)
```

## Tests (`./Scripts/test.sh`; 28 tests, all passing on 2026-11-19)

- **Models:** hex parsing; palette and parameter Codable round trips; built-ins match the spec;
  OKLab round trip for every built-in color (< 1e-6) and known values; ramps with 0, 1, 2 or 7
  colors; clamping.
- **Timing:** clock priming; ignoring stale timestamps (multi-display); clamping large gaps;
  speed changes without jumps; wrap range; offsets after 30 days of uptime; wrap-boundary math;
  frame-rate-independent smoothing; crossfade duration, interruption without a jump, and instant
  switching.
- **Renderer (needs a Metal device, skipped otherwise):** shaders compile and pipelines build;
  **both uniform structs match Metal reflection member by member**; frames vary across the
  screen; animation moves; **seamless offset wraps** (4 components); palette crossfade is
  gradual, with no quarter-second step doing more than 35 % of the change; parameter changes
  ease in.

Not covered by tests: visual quality, real display-link behavior, and multi-display. Those need
a person or real hardware.

## Running

```bash
./Scripts/test.sh                         # unit tests (see note below)
./Scripts/bundle.sh                       # → build/Gloaming.app
open build/Gloaming.app
```

Options (pass them to the binary at `build/Gloaming.app/Contents/MacOS/Gloaming`):
`--palette`, `--speed`, `--complexity`, `--blend`, `--grain`, `--brightness`, `--saturation`,
`--fps`, `--render-scale`, `--output-scale`, `--start-phase`, `--exit-after`, `--snapshot PATH.png`,
`--snapshot-size WxH`. See `Gloaming/App/LaunchOptions.swift`.

**Snapshots** render one frame offscreen with the real pipeline. They need no Screen Recording
permission and work for README screenshots:

```bash
build/Gloaming.app/Contents/MacOS/Gloaming --snapshot ~/Desktop/sunset.png --palette sunset --snapshot-size 2560x1440
```

**Controls:** a menu bar item with Pause, Palette, Speed, Complexity, Grain, Frame Rate, Render
Resolution, Diagnostics and Quit. If a menu bar manager hides the icon, opening the app again
shows a dialog with diagnostics and Pause/Quit.

## Known limitations and follow-ups

- **Visual tuning was judged from offscreen snapshots only.** It needs a human look at motion on
  the real desktop.
- **No persistence:** settings come from launch options and reset on quit. Persistence is
  Phase 3.
- **One shared scene for all displays.** Per-display scenes are Phase 4. The scene model already
  supports several instances.
- **No power management or occlusion pausing yet** (Phase 4). The Phase 1 finding still applies:
  occlusion works but needs a debounce.
- **Command Line Tools test quirk:** plain `swift test` started failing with "plugin for module
  'TestingMacros' not found". It kept failing after `swift package clean`, and also in an
  unrelated throwaway package that had passed earlier. The plugin loads fine with `swiftc`
  directly, so the problem is in SwiftPM's default "swiftbuild" build system, not this code.
  `Scripts/test.sh` uses the classic build system with explicit Swift Testing paths, which works
  reliably. Revisit once full Xcode is installed or the toolchain is updated.
- **Snapshots** match the desktop's field/output ratio for a 2× display with default output
  (`Snapshot.fieldScale`).
