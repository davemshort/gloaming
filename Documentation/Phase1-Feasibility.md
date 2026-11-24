# Phase 1: Desktop Integration Feasibility

Status: **all blocking integration tests (D-2, D-3, D-4, F-1, T-1) pass on macOS 27.2.1; macOS 14 run, Mission Control thumbnails (M-2) and sleep/wake still pending.**
Date: 2026-11-17

## 1. Summary

An animated Metal wallpaper on macOS 14+ **is feasible using only public APIs**, with known
gaps. macOS has no API for a live, animated *system* wallpaper. What it does allow is an
ordinary `NSWindow` placed at the documented desktop window level, which sits above the system
wallpaper and below Finder's desktop icons. The prototype does exactly that, and on this machine
it landed in the correct place in the window stack and held its target frame rate.

No private or undocumented APIs are used, and none are recommended.

The system wallpaper still appears on the lock screen, the login window and (expected, not yet
verified) Mission Control's Spaces bar. Section 5 lists the limits.

## 2. What was verified, and how

Test machine: Apple M5 Pro, macOS **27.2.1** (build 26B131), one LG HDR 4K display at
3008×1692 points, 2× scale (6016×3384 backing pixels), 60 Hz. Desktop icons enabled (Finder
`CreateDesktop` unset, so the default applies), Stage Manager off, "click wallpaper to reveal
desktop" at its default setting.

> **None of this has been verified on macOS 14 or 15.** Desktop window ownership has changed
> between releases (see the "Wallpaper" owners below). The macOS 14 run in the test plan is
> required before relying on any of it.

### 2.1 Window ordering (verified with `CGWindowListCopyWindowInfo`)

On-screen windows at or below the desktop-icon level, front to back:

| Layer | Relative to `.desktopWindow` | Owner | Notes |
|---|---|---|---|
| -2147483603 | +20 (`.desktopIconWindow`) | Finder | Desktop icons, full-screen, transparent |
| -2147483623 | **+0 (`.desktopWindow`)** | **DesktopPrototype** | **Our window** |
| -2147483624 | −1 | WindowManager ("Wallpaper") | |
| -2147483625 | −2 | Wallpaper (system agent) | System wallpaper image |
| -2147483626 | −3 | Window Server | |

Our window is the only one at its level, so its position doesn't depend on tie-breaking
between windows at the same level. It is above every system wallpaper layer and below Finder's
icons.

**Visual confirmation is still needed.** `screencapture` failed ("could not create image
from display"). The cause isn't confirmed: other processes' window titles *were* readable,
which usually needs the same Screen Recording permission. The attempt also appears to have
raised a system permission warning. The stack order above is structural evidence only; test D-2
is the visual check.

### 2.2 Rendering cost (measured)

Each run was about 20 s; values come from the prototype's own counters and `ps`.

| FPS | Render scale | Drawable (px) | Measured FPS | CPU (ps %) | CPU encode / frame | GPU wall time / frame* | RSS |
|---|---|---|---|---|---|---|---|
| 15 | 0.5 | 3008×1692 | 15.0 | 1.1 % | 0.23 ms | 10.0–10.8 ms | 77 MB |
| 30 | 0.5 | 3008×1692 | 30.0 | 2.2–2.4 % | 0.21 ms | 9.9–15.0 ms | 77 MB |
| 60 | 0.5 | 3008×1692 | 60.0 | 4.2 % | 0.19 ms | 11.2–11.8 ms | 77 MB |
| 30 | 0.25 | 1504×846 | 30.0 | 2.2 % | 0.21 ms | 1.7–1.9 ms | 77 MB |
| 30 | 1.0 | 6016×3384 | 30.0 | 2.2 % | 0.21 ms | 15.1 ms | 77 MB |

\* *GPU wall time* is `gpuEndTime − gpuStartTime` for each command buffer. It is **not GPU
utilization**: it includes GPU clock-state effects (note that 4× the pixels did not cost 4× the
time). Treat it as a relative cost indicator only. Measuring real GPU utilization and power
needs Instruments or `powermetrics` (requires sudo); neither was run.

What the numbers show:
- Frame pacing through `NSView.displayLink` hit 15, 30 and 60 FPS exactly.
- CPU cost is small and grows with frame rate, as expected.
- The placeholder shader is **too expensive at 0.5 scale**. Dropping to 0.25 scale cut GPU time
  about 6×. Phase 2 should default to roughly 0.25 scale and use a cheaper noise function. Soft
  gradients upscale well; grain is the exception (see §4).

### 2.3 Occlusion reporting (works; needs confirmation that it updates)

In the first runs, `window.occlusionState` reported **not visible** throughout, with no change
notification. A later run checked this directly. While the prototype ran, the bounds of all
normal-level app windows were dumped, and about **7 % of the desktop was uncovered**. Within
about 1 s of launch, the window logged `occlusion visible=true`, and the 10 s stats line agreed.

Conclusions:
- Finder's full-screen, transparent icon window does **not** make our window count as occluded,
  so occlusion state *can* report visible at the desktop level.
- The earlier "not visible" readings most likely came from a desktop that was fully covered at
  the time. The window layout wasn't recorded during those runs, so this isn't proven.
- **Update (manual test D-7, 2026-11-17):** during Space switches the window logged
  `visible=false` and then `visible=true` within about 15–150 ms, so the notifications fire in
  both directions. These brief false states mean occlusion-based pausing must be **debounced**,
  for example by pausing only after the window has been not-visible for about 1 s, and resuming
  immediately. `--pause-when-occluded` (no debounce) remains a prototype-only flag.

## 3. Options evaluated

| Approach | Public? | Verdict |
|---|---|---|
| **Borderless `NSWindow` at `CGWindowLevelForKey(.desktopWindow)`, one per screen** | Yes | **Recommended.** Used by the prototype. |
| Window at `.desktopIconWindow − 1` | Yes | Equivalent in practice. `.desktopWindow` is the documented level and currently has no other windows at it. Keep the offset configurable in case a macOS release changes the stack. |
| `NSWorkspace.setDesktopImageURL` with frequently updated images | Yes | Not animation: each call is a heavyweight wallpaper change with disk I/O. Useful only as a **static companion** (§4). |
| `.mov` or dynamic `.heic` wallpaper | Yes (file formats) | Dynamic HEIC changes by time of day or appearance and can't run continuous generative animation. Making the files requires private formats or tools and doesn't meet the project goals. |
| Screen saver (`ScreenSaverView`) | Yes | Wrong surface; it only runs while the screen saver is active. |
| Private SkyLight/CGS calls (e.g. moving windows into the wallpaper's Space, or private window tags) | **No** | Rejected. They break between releases, could make App Store or notarization review harder, and aren't needed. |

## 4. Recommended architecture

```text
App (menu bar, NSApplication .accessory / LSUIElement)
└── DesktopCoordinator (main actor)
    ├── observes NSScreen changes, Spaces, sleep/wake, session, power
    └── per display: DesktopWindowController
          NSWindow  level=.desktopWindow, borderless, opaque, ignoresMouseEvents
                    collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
          MetalView (CAMetalLayer backing, NSView.displayLink → follows its screen)
└── RenderContext (one MTLDevice, one MTLCommandQueue, shared pipelines)
```

Decisions behind this layout:

- **One process, one Metal device, one window and display link per screen.** Each screen keeps
  its own refresh rate and scale; pipelines and shaders are shared. The prototype already uses
  this shape.
- **`NSView.displayLink(target:selector:)` (macOS 14+)** instead of `CVDisplayLink`, which is
  deprecated in macOS 14. It follows the view's screen automatically and supports
  `preferredFrameRateRange`.
- **Render below native resolution and let `CAMetalLayer` upscale.** Phase 2 adds a native-
  resolution pass for grain only, since grain blurs if it's upscaled.
- **Dither before 8-bit output.** The prototype uses a 4×4 Bayer matrix. Phase 2 should evaluate
  blue noise, or a 16-bit float drawable on EDR-capable displays.
- **Time** is a `Double` on the CPU and wrapped before being passed to the shader. The prototype's
  wrap produces a visible jump about every 68 minutes; Phase 2 must make motion continuous across
  the wrap, for example with periodic noise domains or CPU-side phase accumulation.
- **Static companion wallpaper (optional, opt-in).** Use the public
  `NSWorkspace.setDesktopImageURL` to set a still frame of the current palette as the real system
  wallpaper. Mission Control, the lock screen and Space transitions then match the animation. The
  user's original wallpaper URL and options **must** be saved and restored on quit and on
  uninstall. This changes the user's real wallpaper, so it needs consent in the UI. It was not
  enabled in Phase 1.

## 5. Limitations and expected failure modes

**Known (structural):**
1. **Lock screen, login window and fast user switching** always show the system wallpaper. No
   public API can draw there.
2. **Mission Control's Spaces bar thumbnails** are expected to show the system wallpaper.
   *(Expected; verify with test M-2.)*
3. **Clicks on empty desktop** reach Finder's full-screen icon window before ours (it's above
   us), and our window ignores mouse events anyway. "Click wallpaper to reveal desktop" and
   desktop right-click menus should therefore be unaffected. *(Expected from the window stack;
   verify with test D-3.)*
4. **Screenshots** taken with system tools will include our window, because it's real window
   content. That's probably desirable, but worth noting.
5. **Sandboxing isn't required** for this approach. The app needs no special permissions for
   rendering. Weather and solar features need Location only if the user opts in.

**To verify (behavior on real hardware):**
6. **Space switching:** our window has `.canJoinAllSpaces` + `.stationary`, so it should stay
   still while app windows slide.
7. **Fullscreen apps:** the window joins fullscreen Spaces behind the app. It may be briefly
   visible during the transition animation, which is probably acceptable. It must never draw over
   the fullscreen app.
8. **Stage Manager:** hides desktop icons by default and manages window groups. Our window should
   stay behind everything.
9. **Occlusion state** works at the desktop level and updates in both directions, but it flickers
   briefly during Space transitions (§2.3). Pausing based on it is viable with a debounce. Still
   unverified: fullscreen apps and Stage Manager.
13. **The menu bar icon can be hidden by third-party menu bar managers.** In testing, the
    prototype's status item was created but never shown, because a menu bar manager (Dimble) was
    hiding it. The app must offer another way in; reopening the app should open Settings.
10. **Display hot-plug and resolution changes:** the prototype rebuilds windows on
    `didChangeScreenParametersNotification`. `CGDirectDisplayID` can change across reconnects;
    Phase 4 needs a sturdier identifier (vendor/model/serial from `CGDisplay*` or
    `NSScreen.localizedName` plus geometry).
11. **Sleep/wake:** the display link should recover by itself. The prototype logs
    `willSleep`/`didWake`/`screensDidSleep`/`screensDidWake` so this can be confirmed.
12. **OS-version drift:** on macOS 27 the wallpaper layers belong to the `WindowManager` and
    `Wallpaper` processes. Owners differ across releases; test D-0 records them on macOS 14. Our
    window doesn't depend on who owns the layers below it, only on the documented level
    constants, but a future release could still change the stack.

## 6. Recommendation

Go ahead with the public desktop-level-window architecture once the manual test plan
(`Documentation/Phase1-TestPlan.md`) passes on this machine **and** on macOS 14. These
results would change the plan:
- **Any case where our window draws over app windows, fullscreen apps, or desktop icons** blocks
  the approach. A higher level offset won't fix that; the design would need a rethink.
- **Occlusion never reports visible** means drop occlusion-based pausing (limitation 9) and
  document it.
- **Mission Control or Space transitions look poor** argues for building the optional static
  companion wallpaper earlier, in Phase 3 rather than later.
