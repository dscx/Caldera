# TempBar

A native macOS menu bar app that reads temperature, fan, and power sensors
directly via IOKit/SMC — no third-party libraries, no Activity-Monitor-style
overhead.

## Features

- Reads real hardware sensors via the System Management Controller, with
  sensor keys discovered dynamically at launch (not hardcoded), since Apple
  Silicon's SMC key meanings shift across chip generations
- Pin any sensor to the menu bar as `icon value`; pin several and they join
  with `::`, or show one combined item instead of separate ones
- Popover lists every sensor grouped by hardware area, with collapsible
  sections, per-sensor alert thresholds, history sparklines, and °C/°F
- Optional per-group averaging — collapse all pinned CPU sensors (etc.) into
  one averaged menu bar entry with its own SF Symbol glyph
- Settings window: hide or reorder sections/sensors, launch at login, alert
  scope, refresh interval
- Best-effort system notification + a "Running hot" banner listing the
  system's top CPU-consuming processes when a pinned sensor crosses its
  threshold

## Requirements

- Apple Silicon Mac, macOS 13+
- Xcode command line tools (`xcode-select --install`)

## Build & run

```bash
./build.sh
open TempBar.app
```

`build.sh` compiles a release binary via Swift Package Manager and assembles
`TempBar.app`. The app isn't sandboxed (SMC access requires that) and is only
ad-hoc code signed, so it's meant to be built and run locally rather than
distributed as a signed binary.

## License

MIT — see [LICENSE](LICENSE).
