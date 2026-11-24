# DesktopPrototype (Phase 1)

A minimal proof of concept: animated Metal content in a public-API, desktop-level window
behind Finder's icons, one window per display. It is **not** the app. It exists to validate
desktop integration. See `../Documentation/Phase1-Feasibility.md` and
`../Documentation/Phase1-TestPlan.md`.

## Requirements

- macOS 14 or later, Apple silicon or a Metal-capable Intel Mac
- Swift 6 toolchain. **Command Line Tools are enough; full Xcode isn't required.** Shaders
  are compiled at runtime, so the offline `metal` compiler isn't needed.
- No signing identity. The bundle script signs ad hoc.

## Build and run

```bash
./Scripts/bundle.sh                     # release build → build/DesktopPrototype.app
open build/DesktopPrototype.app
```

Or run the binary directly to see the log on stdout and pass options:

```bash
./build/DesktopPrototype.app/Contents/MacOS/DesktopPrototype --fps 30 --render-scale 0.25
```

`swift run DesktopPrototype -- --fps 60` also works for quick iteration.

| Option | Default | Meaning |
|---|---|---|
| `--fps N` | 30 | Preferred frame rate (15/30/60 are the targets) |
| `--render-scale S` | 0.5 | Fraction of native pixels to render; the layer upscales |
| `--level-offset K` | 0 | Added to `CGWindowLevelForKey(.desktopWindow)` |
| `--pause-when-occluded` | off | Stop rendering while the window reports not visible (see Feasibility §2.3 before using) |
| `--exit-after SECONDS` | none | Quit automatically, for unattended runs |

**Quitting:** use the ✨ menu bar icon → *Quit Desktop Prototype*, or run `pkill DesktopPrototype`.
The windows ignore the mouse, so there is no other UI.

## Logs

Events, per-display stats (measured FPS, GPU wall time, CPU encode time, drawable size,
occlusion state) and window-stack dumps go to:

```
~/Library/Logs/DesktopPrototype/events.log
```

## Layout

| File | Purpose |
|---|---|
| `main.swift` | Entry point; `.accessory` activation policy (no Dock icon) |
| `AppDelegate.swift` | Per-screen windows, system event logging, status-item menu |
| `DesktopWindow.swift` | The desktop-level `NSWindow` configuration |
| `Renderer.swift` | Shared Metal context, `CAMetalLayer` view, `NSView.displayLink` frame loop |
| `Shaders.swift` | MSL source (placeholder dithered gradient) |
| `WindowList.swift` | `CGWindowListCopyWindowInfo` stack dump |
| `Options.swift`, `EventLog.swift` | CLI options, log file |

## Permissions

None. The prototype makes no network requests, doesn't use location, and doesn't change the
system wallpaper or any preferences.
