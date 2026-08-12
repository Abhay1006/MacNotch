# MacNotch — Code Review & Improvement Plan

Review date: 2026-08-12 (baseline commit `27b3fc0`)
Scope reviewed: all 10 Swift sources (~3,450 lines), `build.sh`, `Info.plist`, `README.md`.

Status legend: `[ ]` open · `[x]` done · `[~]` partially done · `[-]` deferred (with reason)

## How this was verified

- `./build.sh` — clean compile, no warnings, 37 sources.
- `./run-tests.sh` — 41/41 checks pass.
- App run for 16+ minutes: 0.0% CPU idle, ~68 MB resident, no crash reports.
- Window geometry probed live against `CGWindowListCopyWindowInfo`: on this 14" MacBook the
  reported notch is 179pt wide (`safeAreaInsets.top` 32, aux areas 646/645), and the idle island
  renders at x 647–822 — i.e. genuinely inside the cutout, where the old hardcoded 110×22 was
  merely *near* it.

**Not verified interactively:** hover-to-expand. Synthetic `CGEventPost` is a no-op without
Accessibility permission, so it could not be exercised from a script. The geometry it depends on is
unit-tested, but please confirm the feel of the hover target by hand — it is deliberately tighter
than before (see 4.4).

---

## 1. Correctness bugs

### [x] 1.1 Data race in `SportsManager.fetchScores` — **crash risk**
`SportsManager.swift:186-198`. Eight concurrent `URLSession` completion handlers all call
`allMatches.append(contentsOf:)` on the same array with no synchronization. `Array` is not
thread-safe; concurrent appends can corrupt the heap.

**Fix:** collect per-league results into a lock-guarded dictionary keyed by league, then flatten
on the notify queue.

### [x] 1.2 Managers duplicated per screen
`AppDelegate.swift:53-57` creates one `NotchWindowController` per `NSScreen`, and each
`NotchIslandView` owns its own `@StateObject` managers (`NotchIslandView.swift:70-78`). On a
two-display setup that means 2× AppleScript polls, 2× ESPN fetches (16 HTTP requests per poll
cycle), 2× clipboard timers, 2× Obsidian vault scans.

**Fix:** a single shared `AppEnvironment` created once, injected into every window.

### [x] 1.3 Timer leaks on every screen-parameter change
`setupWindows()` runs on every `didChangeScreenParametersNotification`
(`AppDelegate.swift:35-41`) — which fires on display sleep, resolution change, and monitor
connect — and rebuilds everything. Only `SportsManager` had a `deinit`. `MusicManager.progressTimer`,
`ZenManager.timer`, and `NotificationManager.collapseTimer` are `Timer.scheduledTimer` instances
retained by the run loop, so the old objects leaked and kept firing. `MusicManager`'s
`DistributedNotificationCenter` observer was never removed. The rebuild also wiped clipboard
history and killed any running Zen timer.

**Fix:** shared managers (so they survive rebuilds) + `deinit` invalidation everywhere +
`setupWindows` now diffs the screen list and only creates/destroys what actually changed.

### [x] 1.4 1 Hz whole-view invalidation for nothing
`currentTime` (`NotchIslandView.swift:101`) was assigned every second at line 208 and never read.
That is a `@State` write re-evaluating the entire 1,800-line view body once per second, forever,
in an always-running accessory app.

**Fix:** deleted `currentTime` and the 1 Hz `updateTimer`. `.onChange(of: bodySize)` already
drives window resizing.

### [x] 1.5 `DateFormatter` churn in a hot path
`SportMatch.timeUntilKickoff` (`SportsManager.swift:32-52`) built up to three `DateFormatter`s
per call, and was reached from `shouldShowFavoriteTeamMatchCollapsed` → `bodySize` (evaluated
every second) plus inside filters and sorts. `DateFormatter` initialization is very expensive.

**Fix:** parse once at `SportMatch` construction into a stored `Date?`; static cached formatters
for the remaining string formatting.

### [x] 1.6 Sorting by date **string**
`SportsManager.swift:227,239,242` sorted matches with `$0.dateString > $1.dateString`. That only
works while ESPN happens to return `Z`-suffixed UTC; any offset form (`+01:00`) sorts wrong.

**Fix:** sort on the parsed `Date`.

### [x] 1.7 Zen timer drifts
`ZenManager.startTimer` decremented `timeRemaining -= 1` (`NotchIslandView.swift:1657`) on a
default-mode `Timer`, which stalls during menu tracking and coalesces under load.

**Fix:** store an end `Date` and compute remaining time; accurate and unaffected by stalls.

### [x] 1.8 Track titles containing `|` corrupt playback state
`MusicManager.parseState` split on `|` (`MusicManager.swift:192`). A title containing `|` still
passes the `parts.count >= 6` guard but shifts every field.

**Fix:** switched to the ASCII unit-separator `\u{1F}`, which cannot appear in a track title,
and parse from both ends so stray separators cannot shift the numeric fields.

### [x] 1.9 Overlapping system polls
`SystemManager.updateSystemStatusAsync` (`SystemManager.swift:53`) was dispatched to a
*concurrent* global queue every 5s while reading `self.systemVolume` (a main-thread `@Published`)
and mutating `lastVolumeCheck` and `cpuCounter.prevCpuInfo`. A slow AppleScript call plus a vault
scan can exceed 5s, so two invocations overlap and race.

**Fix:** dedicated serial queue + a re-entrancy guard.

### [x] 1.10 Potential infinite loop in quote selection
`QuotesManager.selectNewQuote` (`QuotesManager.swift:94-98`): `while newQuote == currentQuote`
spins forever if the Obsidian quotes file contains N identical lines — `count > 1` does not imply
*distinct*. An infinite loop on the main thread hangs the app.

**Fix:** `filter { $0 != currentQuote }.randomElement()`.

### [x] 1.11 Unstable Obsidian task IDs
`ObsidianTaskManager.swift:83` embeds `cleanedTitle.hashValue` in the task ID. Swift's hash seed
is randomized per process, so IDs change on every launch. Harmless today; a trap the moment
anything is persisted or diffed.

**Fix:** stable FNV-1a hash of the title.

### [x] 1.12 Spurious "Charging" notification at launch
`isBatteryCharging` starts `false` (`SystemManager.swift:8`) and the first poll flips it, so
`.onChange` (`NotchIslandView.swift:344`) fired on every launch while plugged in — and again
after every screen-change rebuild.

**Fix:** track whether a real battery reading has been seen and skip the first transition.

---

## 2. Privacy & security

### [x] 2.1 Clipboard manager captures passwords — **highest-priority privacy fix**
`ClipboardManager.checkClipboard` (`ClipboardManager.swift:38`) stored every string copy,
including from password managers, and rendered it in a visible on-screen list.

**Fix:** honor the standard convention and skip pasteboards carrying
`org.nspasteboard.ConcealedType`, `org.nspasteboard.TransientType`, or
`org.nspasteboard.AutoGeneratedType`.

### [x] 2.2 Artwork temp file in shared `/tmp`
`MusicManager.swift:74,89` wrote and read a fixed, world-writable `/tmp/macnotch_artwork.jpg`.
Any local process can swap the image, and it collides between users on the same machine.

**Fix:** per-launch unique file under `FileManager.default.temporaryDirectory`, cleaned up
after read.

### [x] 2.3 Synchronous network inside a completion handler
`Data(contentsOf: artworkUrl)` at `MusicManager.swift:131` blocked a `URLSession` delegate thread.

**Fix:** second `dataTask` + an in-memory artwork cache keyed by track identity.

### [~] 2.4 Track titles leave the machine
The iTunes Search fallback (`MusicManager.swift:114`) sends the current track title and artist to
Apple on every track change.

**Fix:** documented in the README; added an `ArtworkLookupEnabled` preference (default on) to
turn it off. A full preferences pane is deferred — see 6.1.

---

## 3. Battery & efficiency

### [x] 3.1 N global `.mouseMoved` monitors
`AppDelegate.swift:166` installed one global monitor per screen, each firing `checkMouseHover()`
on every mouse move system-wide.

**Fix:** one shared monitor owned by the delegate, fanning out to controllers, with coalescing so
sub-pixel jitter does no work.

### [x] 3.2 Obsidian vault re-scanned from disk every 5 seconds
`SystemManager.swift:108` triggered a full directory listing plus a read of every dated `.md`
file, every 5 seconds, forever.

**Fix:** a `DispatchSource` file-system watcher on the vault directories, plus a 5-minute
fallback rescan and an immediate rescan when the Calendar tab is opened.

### [x] 3.3 Volume read via AppleScript
`SystemManager.swift:81` shelled out to `NSAppleScript` for the output volume. Slow, and it
requires Automation permission.

**Fix:** CoreAudio (`AudioObjectGetPropertyData` /
`kAudioHardwareServiceDeviceProperty_VirtualMainVolume`) for both read and write — instant,
permission-free, and no AppleScript round trip.

### [x] 3.4 ESPN poll fan-out
`SportsManager.swift:175-184` fetched 8 leagues on every poll — 8 requests every 30s during a
live match, each `limit=200` over a 120-day window.

**Fix:** during live polling only the favorite team's league is refreshed; the wider fallback
sweep runs on a much slower cadence.

### [x] 3.5 Sports never refreshes without a favorite team
`startTimer()` left `shouldPoll = false` when `favoriteTeamMatch == nil`
(`SportsManager.swift:120-144`), so default league mode was static until you switched tabs.

**Fix:** a slow idle refresh cadence when the Sports tab is visible.

---

## 4. Architecture

### [x] 4.1 `NotchIslandView.swift` was 1,825 lines
It held 8 tab views plus `FileShelfManager`, `NotificationManager`, `ZenManager`,
`FavoriteAppsManager`, and three model types.

**Fix:** split into `Views/Tabs/*`, `Models/*`, and the managers moved into `Managers/`.

### [x] 4.2 `SystemManager` owned unrelated managers
`SystemManager.swift:15-16` owned `CalendarManager` and `ObsidianTaskManager`, so views reached
through `systemManager.obsidianTaskManager.todayTasks` — a Law of Demeter violation that also tied
Calendar refreshes to a 5s hardware poll.

**Fix:** both hoisted into `AppEnvironment` as peers.

### [x] 4.3 Hardcoded notch geometry
110×22, 240×35, 300×35, 380×… were duplicated across `AppDelegate.swift:77,87,181` and
`NotchIslandView.swift:130-168`. macOS 12+ exposes `NSScreen.safeAreaInsets.top` and
`auxiliaryTopLeftArea`, which give the real notch size for the current Mac — 14", 16", and 15" Air
all differ.

**Fix:** a single `NotchMetrics` type that derives geometry per screen from the real safe-area
insets, with a sensible fallback for notch-less displays.

### [x] 4.4 Hover region did not match the visible capsule
Detection was clamped to a 240×35 minimum (`AppDelegate.swift:181-182`) while the idle capsule is
110×22, so hovering blank menu-bar area triggered expansion and made centered menu-bar items hard
to click.

**Fix:** the detection rect now tracks the actual rendered size (with a small, deliberate margin).

### [x] 4.5 `TouchBarWindow` misnamed
Renamed to `NotchPanel` — it has nothing to do with the Touch Bar.

### [-] 4.6 Non-notch external displays
The island still renders at top-center on notch-less screens. `NotchMetrics` now detects the
absence of a notch, and a `ShowOnExternalDisplays` preference exists, but per-screen placement
strategy (e.g. sit *below* the menu bar on external monitors) is a design decision left open.

---

## 5. Build & distribution

### [x] 5.1 No code signing
The app `dlopen`s a private DisplayServices framework and drives AppleScript automation. TCC
grants are keyed to the code signature, so an unsigned ad-hoc binary has its permissions reset on
**every rebuild** — hence repeated permission prompts.

**Fix:** `build.sh` now ad-hoc signs with a stable identifier (`com.abhay.MacNotch`), which keeps
TCC grants stable across rebuilds. Developer ID + notarization is still required for distribution
to other machines — see 5.5.

### [x] 5.2 Manually maintained source list / arm64 only
`build.sh` hardcoded every file path (easy to forget a new one) and targeted `arm64` only despite
the README claiming Intel support.

**Fix:** sources are auto-discovered via `find`; `--universal` builds and `lipo`s both slices.

### [x] 5.3 Module cache written into the repo
`build.sh` wrote `./scratch/ModuleCache`. Moved to `~/Library/Caches/MacNotch`.

### [x] 5.4 Info.plist gaps
No `CFBundleVersion` (required for a well-formed bundle), no `CFBundleIconFile`,
no `LSApplicationCategoryType`. Added.

### [-] 5.5 SPM / Xcode project migration, notarization
Deferred deliberately. Moving to SPM changes the whole build flow and still needs a script to
assemble the `.app`; it is worth doing but should be its own change. Notarization additionally
requires a paid Developer ID.

### [~] 5.6 No tests
The pure-logic units most likely to rot silently: kickoff parsing and formatting, match state
precedence, stable task IDs, notch geometry, Zen formatting and clamping, and clipboard preview
truncation.

**Fix:** `Tests/LogicTests.swift` plus `./run-tests.sh` — a dependency-free runner that compiles
every source except `main.swift` alongside the tests. 41 checks, currently all passing. Notably it
pins `stableHash` against an *independently computed* reference FNV-1a rather than against our own
output, and asserts the derived notch geometry actually fits inside the physical cutout.

A real XCTest target still depends on 5.5. Not yet covered: `ObsidianTaskManager` markdown parsing
and `cleanMarkdownLinks` (they need filesystem fixtures), and the `SportsManager` favourite-match
precedence chain (it needs the network layer injected rather than hardcoded to `URLSession.shared`).

### [x] 5.7 Debug `print` statements
`AppDelegate.swift:45,56` replaced with `os.Logger` (subsystem `com.abhay.MacNotch`).

---

## 6. UX gaps

### [~] 6.1 No preferences UI
The Obsidian vault path (`ObsidianTaskManager.swift:24-25`) and quotes file path
(`QuotesManager.swift:70`) were hardcoded to one machine's home directory — the single biggest
blocker to anyone else using the app.

**Fix:** all paths and toggles now read from `Preferences` (`UserDefaults`-backed) with sane
defaults, and a Settings tab exposes vault path, artwork lookup, launch-at-login, and external
display behaviour. A full standalone preferences *window* is deferred.

### [x] 6.2 No launch-at-login
Added via `SMAppService.mainApp`.

### [x] 6.3 No way to quit from the UI
The README's answer was "focus the clipboard search and press Cmd+Q, or `killall`". Added a
right-click context menu on the island with Preferences / Quit.

### [~] 6.4 Accessibility
No VoiceOver labels, no `accessibilityReduceMotion` handling, 8–9pt text at
`white.opacity(0.4)` fails contrast guidelines.

**Fix:** added accessibility labels to icon-only controls and `reduceMotion` handling for the
spring animations and the audio visualizer. Raising the minimum font sizes and contrast is a
visual-design change left for you to make deliberately.

### [x] 6.5 Inconsistent app launching
`FavoriteAppsManager.launchApp` used `NSWorkspace.shared.open(url)`
(`NotchIslandView.swift:1757`) while the rest of the code used the modern
`openApplication(at:configuration:)`. Made consistent.

---

## 7. Documentation

### [x] 7.1 README staleness
The "Project Structure" section pointed at `file:///Users/abhay/Desktop/projects/MacNotch/main.swift`
— wrong paths (files live under `Sources/Core/` and `Sources/Managers/`) and absolute links into
one home directory, so they were dead for anyone else. It also said "7 tabs" when there are 8
(`quotes` was added later).

**Fix:** corrected paths, relative links, tab count, added requirements, build instructions,
and a privacy note covering the clipboard and iTunes artwork lookup.

### [-] 7.2 No LICENSE, no screenshot
Both worth adding; the license choice is yours to make.
