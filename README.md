# MacNotch — macOS Dynamic Island

MacNotch is a native macOS app built with Swift and SwiftUI that turns your MacBook's camera
notch into an interactive Dynamic Island. It runs as a lightweight, borderless accessory panel
— no Dock icon, no Cmd-Tab entry.

When idle it hides completely behind the camera housing. Hover it and it expands into a tabbed
panel; live content (music, a match in progress, a Zen countdown) shows either side of the notch
without ever covering the camera.

---

## Requirements

| | |
|---|---|
| macOS | 14.0 (Sonoma) or later |
| Hardware | Any Mac. On notched MacBooks the island derives its geometry from the real cutout; on other displays it uses a compact pill at top centre. |
| Toolchain | Xcode Command Line Tools (`xcode-select --install`) |

---

## Build & run

```bash
./build.sh --run          # compile, bundle, sign, launch
./build.sh                # build only
./build.sh --universal    # universal binary (arm64 + x86_64)
./run-tests.sh            # run the logic tests
```

`build.sh` discovers sources automatically, keeps its build cache in `~/Library/Caches/MacNotch`,
and ad-hoc signs the bundle with a stable identifier. **The signing step matters**: macOS ties
Automation and Calendar permissions to a bundle's code signature, so an unsigned build re-prompts
for every permission each time you rebuild.

To sign with a Developer ID instead:

```bash
SIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)" ./build.sh
```

To quit: right-click the island and choose **Quit MacNotch**, or use the Quit button in the
Settings tab.

---

## Permissions

On first launch macOS will ask for:

- **Automation → Music** — read the current track and drive playback (AppleScript).
- **Calendar** — show your next event, and write events when you sync Obsidian tasks.

Both are explained by the usage strings in `Sources/Core/Info.plist`. Brightness control uses a
private DisplayServices entry point and needs no permission; volume uses CoreAudio and needs none
either.

---

## Privacy

MacNotch is local-first. Two things are worth knowing:

- **Clipboard history** is kept in memory only (never written to disk) and is capped by the limit
  in Settings. Copies that an app marks private — the `org.nspasteboard.ConcealedType` /
  `TransientType` convention used by password managers — are **never recorded**.
- **Album artwork lookup**: when Apple Music has no local artwork (streamed or URL tracks),
  MacNotch queries Apple's public iTunes Search API, which means the track title and artist leave
  your machine. Turn this off with *Settings → Look up missing album art*.

Live scores are fetched from ESPN's public scoreboard API. No account, no analytics, no telemetry.

---

## Tabs

| Tab | What it does |
|---|---|
| 🎵 **Music** | Track, artist, artwork, scrubbing progress, and transport controls for Apple Music. Falls back to the iTunes Search API for artwork on streamed tracks. |
| 📅 **Calendar** | Your next event in the coming 24 hours (EventKit), alongside pending Obsidian daily tasks with one-click sync into Apple Calendar. |
| 🏆 **Sports** | Live soccer scores from ESPN across 14 competitions. Set a favourite team to have its match tracked and spotlighted, with in-island banners for kick-off, goals, half time, and full time. |
| 📋 **Clipboard** | Rolling copy history with search and one-click re-copy, plus a drag-and-drop file shelf. |
| ⚙️ **System** | Battery ring, volume and brightness sliders, live CPU and RAM meters. |
| 🧘 **Zen** | A rest timer (1–120 min) that collapses the island and counts down beside the notch. |
| 🚀 **Apps** | Launchpad-style grid of favourite apps. Drag any `.app` onto the island to add it. |
| 💬 **Quotes** | A motivational quote, drawn from your Obsidian notes when available. |
| 🔧 **Settings** | Obsidian vault location, launch at login, artwork lookup, external-display behaviour, clipboard history size. |

### Obsidian integration

Point *Settings → Obsidian Vault* at your vault. MacNotch reads:

- `Daily Tasks/YYYY-MM-DD.md` and `YYYY-MM-DD.md` at the vault root — markdown checkboxes
  (`- [ ]` / `- [x]`) become tasks.
- `Quotes and ideas.md` — list items become the quote pool.

The vault is watched with FSEvents, so edits appear without polling. Nothing is written back to
your notes; the Sync button only creates events in Apple Calendar.

---

## Interaction

- **Expand** — move the cursor over the notch.
- **Collapse** — move the cursor away.
- **Right-click** — Settings or Quit.
- **Drag & drop** — a `.app` goes to Favourites; anything else goes to the file shelf.
- **Multi-display** — an island appears on each screen (toggle in Settings). All screens share one
  set of data sources, so nothing is polled twice.

---

## Project structure

```
Sources/
  Core/        entry point, window/panel management, shared environment,
               preferences, notch geometry, FSEvents watcher, logging
  Models/      SportMatch, ObsidianTask, IslandTab, ShelfFile, FavApp
  Managers/    one per data source — music, clipboard, system, audio,
               calendar, obsidian, sports, quotes, zen, notifications,
               file shelf, favourite apps
  Views/       NotchIslandView (shell), CollapsedIslandView,
               Tabs/ (one file per tab), Components/ (shared views)
Tests/         logic tests, run with ./run-tests.sh
```

Managers are owned by `AppEnvironment` and shared across every screen; views hold no state that
outlives a window.

See [IMPROVEMENTS.md](IMPROVEMENTS.md) for the current engineering backlog and the rationale
behind recent changes.

---

## Known gaps

- No app icon yet (`Contents/Resources` is empty).
- Not notarized — distributing to another Mac requires a Developer ID identity and notarization.
- The build is a `swiftc` script rather than a Swift package; migrating would enable XCTest.
- On external displays the island sits at top centre and overlaps the menu bar clock; only
  built-in-display placement is properly tuned.
