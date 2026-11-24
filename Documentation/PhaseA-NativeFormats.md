# Phase A: Native Wallpaper Formats

Status: **time-of-day dynamic HEIC verified on desktop and lock screen (A-5 to A-7 pass). Still and light/dark checks (A-1 to A-4) pending.**
Date: 2026-11-20 · Mac: Apple M5 Pro, macOS 27.2.1, built-in Retina display 3600×2338 px.

Question: can wallpapers this app exports be applied through System Settings and show on the
**desktop and lock screen**? Do dynamic files switch as intended?

## Test files

Generate them with (the time-of-day schedule is relative to when you run it):

```bash
./Scripts/bundle.sh
build/Gloaming.app/Contents/MacOS/Gloaming --phase-a-test build/phase-a --snapshot-size 3600x2338
```

| File | Contents | Metadata |
|---|---|---|
| `1-still-sunset.png` | One Sunset frame | none |
| `2-appearance-light-sunset-dark-ocean.heic` | 2 images: Sunset (light), Ocean (dark) | `apple_desktop:apr = {l: 0, d: 1}` |
| `3-time-of-day-sunset-ocean-forest-ember.heic` | 4 images: Sunset → Ocean → Forest → Ember | `apple_desktop:h24`, entries at −1, +3, +6 and +9 minutes from generation |

## Automated checks (done)

- Dimensions 3600×2338, image counts 2 and 4, metadata decodes as written: **verified**
  with ImageIO.
- Metadata round-trip tests (`ExportTests`, 3 tests): **pass**. The full suite is 31 tests.
- **`apr` matches Apple's own format:** `/System/Library/Desktop Pictures/Sonoma.heic` carries
  `apple_desktop:apr = {l: 0, d: 1}`, the same as our file.
- **Finding:** macOS 27 picks one behavior per file. `h24` only gives **Dynamic** (follows
  the clock; Light/Dark (Still) ignore `ap`). Adding `apr` gives **Automatic** (follows
  appearance, ignores the clock). Time-of-day exports write `h24` only (A-5b, A-5c).
  Untested idea for getting both: Apple's `solar` format with an `ap` entry.
- **`h24` is not checked against an Apple file:** no Apple time-of-day wallpaper is installed
  locally. The schema follows community reverse-engineering, and the manual test below is
  the real check.

## Manual results (pending)

Apply each file via **System Settings → Wallpaper → Add Photo…** (or add the
`build/phase-a` folder).

| # | Check | Result |
|---|---|---|
| A-1 | Still PNG shows on desktop | |
| A-2 | Still PNG shows on lock screen (⌃⌘Q) | |
| A-3 | Light/dark HEIC: Sunset in Light mode, Ocean in Dark mode, switches when appearance changes | |
| A-4 | Light/dark HEIC on lock screen | |
| A-5 | Time-of-day HEIC: shows the frame for the current time, and System Settings recognizes it as dynamic | **Pass (2026-11-20).** Shows Sunset (the current-time frame). System Settings lists it with a **Dynamic / Light (Still) / Dark (Still)** menu, Dynamic selected; the Light/Dark options come from the `ap` entry (light = Sunset, dark = Ocean) |
| A-6 | Time-of-day HEIC switches at the scheduled minutes (records how quickly macOS updates) | **Pass (2026-11-20):** switched Sunset → Ocean around 11:52 and → Forest around 11:55, on schedule as far as observed (exact delay not measured) |
| A-7 | Time-of-day HEIC on lock screen | **Pass (2026-11-20):** lock screen showed Ocean, then switched to Forest along with the desktop |
| A-5b | Time-of-day HEIC: "Light (Still)" / "Dark (Still)" show the light and dark images | **Needs a separate `apr` tag (2026-11-20).** First file (`h24` with `ap` only): both still choices kept the current frame (Forest). Retest with Ember as the current frame: **3a** (`h24` only) didn't change between Light and Dark Still; **3b** (`h24` + separate `apr`) changed. *(Superseded by A-5c: the extra tag breaks time-following.)* |
| A-5c | Does a time-of-day file with `h24` + `apr` still follow the clock? | **No (2026-11-20).** With both tags System Settings shows **Automatic** (h24 only: **Dynamic**). Test file 4a: at 1:01 PM, when the schedule said Ember, the desktop showed **Sunset**, the light image, so it follows appearance. **Decision: time-of-day exports write `h24` only.** Light/Dark (Still) then keep the current frame; the separate light/dark export covers that use |
| A-8 | Adding the folder and using "rotate" works (optional) | |

## Notes

- The app did **not** change the user's wallpaper. The API reports the current wallpaper as
  `DefaultDesktop.heic`, which is what it returns for system-managed wallpapers such as
  Aerials, so the original couldn't be reliably restored. Users apply exports themselves; an
  optional "Set as Wallpaper" button comes in Phase E.
