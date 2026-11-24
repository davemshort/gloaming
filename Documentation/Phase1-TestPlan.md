# Phase 1: Desktop Integration Test Plan

Run each test on **this Mac (macOS 27)** and on **a macOS 14 machine or VM**. Record pass,
fail or notes in the tables. Every event the prototype sees is written to
`~/Library/Logs/DesktopPrototype/events.log` (menu bar icon → *Reveal Log in Finder*). Use
*Log Window Stack* (⌘L in the menu) to record the window order at any moment.

## Setup

```bash
cd Prototype && ./Scripts/bundle.sh && open build/DesktopPrototype.app
```

- A ✨ icon appears in the menu bar; the desktop shows a slowly moving blue/violet/teal
  gradient.
- Put at least 3 files on the desktop so icon layering can be checked.
- To clear the log between runs: `rm ~/Library/Logs/DesktopPrototype/events.log`
- To stop: menu bar icon → *Quit Desktop Prototype*. If the menu is unreachable, run
  `pkill DesktopPrototype`.

Record the environment: macOS version, Mac model, displays (model, resolution, scale,
refresh rate), Stage Manager on/off, desktop icons on/off, and the Desktop & Dock setting
"Click wallpaper to reveal desktop".

## D: Desktop basics

| # | Test | Expected | macOS 27 | macOS 14 |
|---|---|---|---|---|
| D-0 | Right after launch: menu → *Log Window Stack*; paste the output from the log here | DesktopPrototype at `desktop+0`, below Finder (`desktop+20`), above every wallpaper layer. Record the wallpaper layer owners | | |
| D-1 | Launch with the desktop visible | Animated gradient replaces the wallpaper; no Dock icon | Pass (2026-11-17) | |
| D-2 | Look at desktop icons | Icons, labels and selection highlights draw **above** the gradient | Pass (2026-11-17): icons **and desktop widgets** draw above | |
| D-3 | Click, drag-select, double-click and right-click on empty desktop; drag a file around | All Finder behavior unchanged; "click to reveal desktop" still works | Pass (2026-11-17): click, drag, right-click OK | |
| D-4 | Open, move and resize app windows over the desktop | Gradient always stays behind every window | | |
| D-5 | ⌘-Tab, ⌘-\`, ⌘H, ⌘M | The prototype never appears in switchers or cycling; nothing is drawn over windows | | |
| D-6 | Leave running for 2+ hours | No leak (Activity Monitor memory stays flat at about 80 MB); one visible jump about every 68 min is a **known** prototype artifact | | |
| D-7 | **Occlusion:** cover the desktop with windows, then use Show Desktop (fn-F11, or the thumb-and-three-finger spread gesture) and wait 15 s | The log shows `occlusion … visible=` changes, or `stats … occlusionVisible=yes` while the desktop is shown. **If it never says yes, record that; it's the key finding** | Pass (2026-11-17): Show Desktop looked correct. During Space switches the log shows `visible=false` → `visible=true` within about 15–150 ms, so notifications fire both ways. Brief transient false states mean any pausing must be debounced | |

## S: Spaces and Mission Control

| # | Test | Expected | macOS 27 | macOS 14 |
|---|---|---|---|---|
| S-1 | Create a second desktop Space and switch with Ctrl-→ or a 3/4-finger swipe | Gradient present on every Space; note whether it stays still or slides with the Space during the animation | Pass (2026-11-17): new Space shows the gradient correctly (still vs. sliding not recorded) | |
| S-2 | Check the log after switching | `event activeSpaceChanged` lines appear | Pass (2026-11-17) | |
| M-1 | Open Mission Control | Gradient doesn't cover window thumbnails; note what the background shows | | |
| M-2 | Look at the Spaces bar thumbnails at the top | Expected: the **system** wallpaper, not the gradient. Record what you see | | |
| M-3 | App Exposé (Ctrl-↓) and Show Desktop (spread gesture or F11) | Windows move out of the way; gradient stays put and fully visible on Show Desktop | | |

## F: Fullscreen apps

| # | Test | Expected | macOS 27 | macOS 14 |
|---|---|---|---|---|
| F-1 | Put an app into fullscreen (green button) | App fills the screen; gradient never draws over it | Pass (2026-11-17). Log: `visible=false` for the whole ~6.5 s in fullscreen, `true` on return, yet the prototype kept rendering about 29 FPS unseen. A debounced occlusion pause would save that work | |
| F-2 | Swipe between the fullscreen app and the desktop | Transition looks acceptable; note any flash or gradient visible behind | | |
| F-3 | Play a fullscreen video (Safari or QuickTime) | Playback unaffected | | |

## T: Stage Manager

| # | Test | Expected | macOS 27 | macOS 14 |
|---|---|---|---|---|
| T-1 | Turn on Stage Manager (Control Center) | Gradient stays behind the stage and the strip; icons hide/show per Stage Manager settings | Pass (2026-11-17) | |
| T-2 | Click the desktop with Stage Manager on | Windows step aside as normal; gradient visible | | |
| T-3 | Switch app groups from the strip | No gradient over windows; no flicker | | |

## P: Multiple displays and scaling (if available)

| # | Test | Expected | macOS 27 | macOS 14 |
|---|---|---|---|---|
| P-1 | Launch with two displays | One gradient per display, filling each fully, including under the menu bar | | |
| P-2 | Unplug and replug a display while running | Log shows `screenParametersChanged`, `display removed`, then the display re-added; gradient comes back | | |
| P-3 | Change resolution / "Larger Text ↔ More Space" in Displays settings | Gradient refills the screen with no stretching, gaps or black bars | | |
| P-4 | Mix Retina and non-Retina displays | Both render; `drawable=` sizes in the log match each screen's scale × render scale | | |
| P-5 | Change the main display / arrangement | Windows follow their screens | | |

## L: Lifecycle and power

| # | Test | Expected | macOS 27 | macOS 14 |
|---|---|---|---|---|
| L-1 | Sleep (Apple menu → Sleep), then wake | Log shows `willSleep` and `didWake`; animation resumes, and `stats` lines continue at the target FPS | | |
| L-2 | Let the display sleep (`pmset displaysleepnow`), then wake | `screensDidSleep` and `screensDidWake` logged; animation resumes | | |
| L-3 | Lock screen (⌃⌘Q), then unlock | Lock screen shows the system wallpaper (expected). After unlock, the gradient is back | | |
| L-4 | Fast user switch to another account and back | `sessionResignedActive` and `sessionBecameActive` logged; gradient restored | | |
| L-5 | On a laptop: unplug and replug power; toggle Low Power Mode | `lowPowerMode=` lines logged (power source isn't logged in Phase 1) | | |
| L-6 | Menu: Pause, Resume, and 15/30/60 FPS | Animation freezes and resumes; `stats measuredFPS` follows the selection | | |
| L-7 | Quit from the menu | Gradient disappears immediately; system wallpaper visible; Finder unaffected | | |
| L-8 | Force-quit (`pkill -9 DesktopPrototype`) | Same as L-7. Nothing persistent was changed, so nothing needs restoring | | |

## Other findings

- **Menu bar icon hidden (2026-11-17): caused by a third-party menu bar manager (Dimble), not
  macOS.** The status item was created (`isVisible=true`), but its window was 33×0 at the screen
  origin, which is how a hidden item looks from inside the app. It wasn't listed in System
  Settings → Menu Bar either. Moving it to Dimble's "visible" section didn't help; quitting Dimble
  made it appear immediately (confirmed). Possibly Dimble doesn't recognise rebuilt ad-hoc-signed
  binaries as the same app (unverified). Users with menu bar managers will hit this routinely. Fallback
  added: opening the app again shows a Keep Running / Quit dialog. **Phase 3 requirement:** the
  real app must stay controllable without its menu bar icon, e.g. reopening opens Settings.

## Pass criteria for Phase 1

- **Blocking:** D-2, D-3, D-4, F-1 and T-1 must pass on both macOS versions. Any case where the
  gradient covers windows, icons or fullscreen apps blocks the architecture.
- **Design-shaping:** the D-7, M-2, S-1 and F-2 results decide whether occlusion-based pausing
  and the optional static companion wallpaper go into scope (see Feasibility doc §6).
