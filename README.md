<h1><img src="docs/icon.png" width="96" align="middle" alt=""> Caldera</h1>

A native macOS menu bar app that reads temperature, fan, and power sensors
directly via IOKit/SMC — no third-party libraries, no Activity-Monitor-style
overhead.

<p align="center">
  <img src="docs/menubar.png" height="48" alt="Caldera's menu bar item, showing a pinned CPU temperature and fan speed separated by a middle dot">
</p>

<p align="center">
  <img src="docs/main.png" height="400" alt="Caldera's sensor popover, showing pinned CPU and fan sensors with sparklines and top CPU processes">
  <img src="docs/settings.png" height="400" alt="Caldera's Settings window, showing general preferences and section management">
</p>

## Features

- Reads real hardware sensors via the System Management Controller, with
  sensor keys discovered dynamically at launch (not hardcoded), since Apple
  Silicon's SMC key meanings shift across chip generations
- Pin any sensor to the menu bar as `icon value`; pin several and they join
  with a middle dot, or show one combined item instead of separate ones
- Popover lists every sensor grouped by hardware area, with collapsible
  sections, per-sensor alert thresholds, history sparklines, and °C/°F
- Optional per-group averaging — collapse all pinned CPU sensors (etc.) into
  one averaged menu bar entry with its own SF Symbol glyph
- Settings window: hide or reorder sections/sensors, launch at login, alert
  scope, refresh interval
- Best-effort system notification + a "Running hot" banner listing the
  system's top CPU-consuming processes when a pinned sensor crosses its
  threshold
- Manual fan override, per fan, clamped to its own hardware min/max —
  reverts to automatic control the moment Caldera quits (see
  [Fan control](#fan-control))

## Fan control

Each fan in the popover has a "Manual Control…" link. Clicking it seeds a
slider at the fan's current speed; dragging it writes a new target RPM,
clamped to that fan's own hardware min/max so it can never be pushed outside
what Apple's firmware already considers a safe range. "Auto" hands control
back at any time, and quitting Caldera (or it crashing) does the same
automatically — manual targets are never saved to disk, so every launch
starts in automatic.

Under the hood this writes directly to the SMC's fan target key. Some Macs
expose a separate "force manual" key that most fan-control tools use to
lock in an override; this one doesn't, so Caldera instead keeps rewriting
the target on every poll tick and simply stops the instant it's not
supposed to be in control anymore, letting the firmware's own thermal loop
reclaim the key.

**Whether this actually does anything depends on the Mac.** SMC key *reads*
are unrestricted for any process, but on some machines the driver rejects
*writes* from an unprivileged, unentitled app with `kIOReturnNotPrivileged`
— confirmed by testing this live against real hardware, not assumed.
Caldera detects that on the first write attempt and turns the control off
entirely (with an explanatory line in place of the slider) rather than
showing you a control that silently does nothing. Making it work on those
Macs would mean a signed, privileged helper process — a real project, not a
quick fix — so it isn't done here.

## Requirements

- Apple Silicon Mac, macOS 13+
- Xcode command line tools (`xcode-select --install`)

## Download

Grab `Caldera.app.zip` from the [latest release](https://github.com/dscx/Caldera/releases/latest), unzip it, and move `Caldera.app` wherever you like.

It's ad-hoc signed only (no Apple Developer ID, not notarized), so macOS
blocks it on first launch — and on current macOS, the dialog you get from
double-clicking or right-click → Open only offers **Move to Trash** or
**Done**, with no direct bypass. To actually open it, use one of:

- **System Settings:** try to open the app once (so macOS registers the
  block), then go to **System Settings → Privacy & Security**, scroll to
  the security message about `Caldera.app`, and click **Open Anyway**.
  Confirm once more when it re-launches. Only needed the first time.
- **Terminal:** strip the quarantine flag yourself, then open it normally:
  ```bash
  xattr -d com.apple.quarantine /path/to/Caldera.app
  ```

## Build & run

```bash
./build.sh
open Caldera.app
```

`build.sh` compiles a release binary via Swift Package Manager and assembles
`Caldera.app`. The app isn't sandboxed (SMC access requires that), so it
can't go through the Mac App Store.

## License

MIT — see [LICENSE](LICENSE).
