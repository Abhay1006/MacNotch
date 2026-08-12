import Cocoa

// A dependency-free test runner for the pure-logic parts of MacNotch.
//
// A full XCTest target needs an Xcode project or Swift package (see IMPROVEMENTS.md 5.5).
// Until then this covers the units most likely to break silently: date parsing, the
// favourite-match precedence rules, markdown task parsing, and notch geometry.

var failures = 0
var checks = 0

func check(_ condition: Bool, _ message: String, file: StaticString = #file, line: UInt = #line) {
    checks += 1
    if !condition {
        failures += 1
        print("  ✗ \(message)  (line \(line))")
    }
}

func checkEqual<T: Equatable>(_ actual: T, _ expected: T, _ message: String, line: UInt = #line) {
    checks += 1
    if actual != expected {
        failures += 1
        print("  ✗ \(message): expected \(expected), got \(actual)  (line \(line))")
    }
}

func suite(_ name: String, _ body: () -> Void) {
    print("\n\(name)")
    body()
}

// MARK: - Date parsing

func makeMatch(
    id: String,
    state: String,
    home: String = "Arsenal",
    away: String = "Chelsea",
    offsetSeconds: TimeInterval
) -> SportMatch {
    SportMatch(
        id: id, leagueId: "eng.1", leagueName: "Premier League",
        homeTeam: home, awayTeam: away, homeAbbr: "ARS", awayAbbr: "CHE",
        homeScore: "1", awayScore: "0",
        statusState: state, statusDetail: state == "in" ? "72'" : "FT",
        homeLogo: nil, awayLogo: nil,
        date: Date().addingTimeInterval(offsetSeconds)
    )
}

func runAllTests() {
    suite("SportMatch date parsing") {
        // The form ESPN actually returns.
        let utc = SportMatch.parseDate(from: "2026-08-12T19:30Z")
        check(utc != nil, "parses ESPN's yyyy-MM-dd'T'HH:mmZ form")

        check(SportMatch.parseDate(from: "2026-08-12T19:30:00Z") != nil, "parses full ISO-8601 with seconds")
        check(SportMatch.parseDate(from: "") == nil, "empty string yields nil")
        check(SportMatch.parseDate(from: "not a date") == nil, "garbage yields nil")

        // An offset form must sort correctly against a Z form — string comparison, which the
        // old code used, gets this wrong.
        let a = SportMatch.parseDate(from: "2026-08-12T23:00Z")
        let b = SportMatch.parseDate(from: "2026-08-13T01:00+03:00") // == 22:00Z, i.e. EARLIER
        if let a = a, let b = b {
            check(b < a, "offset timestamps compare by real instant, not lexically")
            check("2026-08-13T01:00+03:00" > "2026-08-12T23:00Z", "…and the old string compare disagreed")
        } else {
            check(false, "both offset forms parse")
        }
    }

    suite("SportMatch kickoff formatting") {
        let today = Date().addingTimeInterval(3600)
        check(SportMatch.formatMatchTime(today).hasPrefix("Today "), "today's kickoff is labelled Today")

        let tomorrow = Date().addingTimeInterval(60 * 60 * 26)
        let label = SportMatch.formatMatchTime(tomorrow)
        check(label.hasPrefix("Tomorrow ") || label.hasPrefix("Today "),
              "a kickoff ~26h out is Tomorrow (or Today near midnight), got \(label)")

        let farOut = Date().addingTimeInterval(60 * 60 * 24 * 9)
        let farLabel = SportMatch.formatMatchTime(farOut)
        check(!farLabel.hasPrefix("Today") && !farLabel.hasPrefix("Tomorrow"),
              "a kickoff 9 days out uses the dated form, got \(farLabel)")
    }

    // MARK: - Match state

    suite("SportMatch state helpers") {
        let live = makeMatch(id: "1", state: "in", offsetSeconds: -3600)
        check(live.isLive && !live.isFinished && !live.isScheduled, "\"in\" means live")

        let done = makeMatch(id: "2", state: "post", offsetSeconds: -7200)
        check(done.isFinished && !done.isLive, "\"post\" means finished")

        let upcoming = makeMatch(id: "3", state: "pre", offsetSeconds: 3600)
        check(upcoming.isScheduled, "\"pre\" means scheduled")
        check((upcoming.timeUntilKickoff ?? 0) > 0, "future kickoff has positive countdown")
        check((live.timeUntilKickoff ?? 0) < 0, "past kickoff has negative countdown")

        // Undated fixtures must sort last, not to the epoch.
        let undated = SportMatch(
            id: "4", leagueId: "eng.1", leagueName: "PL",
            homeTeam: "A", awayTeam: "B", homeAbbr: "A", awayAbbr: "B",
            homeScore: "0", awayScore: "0", statusState: "pre", statusDetail: "TBD",
            homeLogo: nil, awayLogo: nil, date: nil
        )
        check(undated.sortDate > upcoming.sortDate, "undated fixtures sort after dated ones")
    }

    // MARK: - Stable hashing

    suite("Stable task IDs") {
        // The whole point: unlike `hashValue`, this must not change between runs.
        checkEqual("Buy milk".stableHash, "Buy milk".stableHash, "same input hashes identically")
        check("Buy milk".stableHash != "Buy bread".stableHash, "different inputs differ")
        check(!"".stableHash.isEmpty, "empty string still produces an id")
        // Pinned against a reference FNV-1a implementation (not against our own output),
        // so a change to the algorithm is caught rather than rubber-stamped.
        checkEqual("Buy milk".stableHash, "3jyk37f4p12m", "matches reference FNV-1a for 'Buy milk'")
        checkEqual("".stableHash, "33niihzj4ux45", "matches the FNV-1a offset basis for an empty string")
    }

    // MARK: - Notch geometry

    suite("NotchMetrics") {
        guard let screen = NSScreen.screens.first else {
            check(false, "a screen is available")
            return
        }
        let metrics = NotchMetrics(screen: screen)

        check(metrics.collapsedIdle.width > 0 && metrics.collapsedIdle.height > 0, "idle size is positive")
        check(metrics.collapsedActive.width > metrics.collapsedIdle.width,
              "active capsule is wider than the idle one")
        checkEqual(metrics.expandedWidth, 380, "expanded width")

        if metrics.hasNotch {
            // Must fit *inside* the physical cutout or black corners peek out.
            check(metrics.collapsedIdle.width < metrics.notchSize.width,
                  "idle capsule is narrower than the notch (\(metrics.collapsedIdle.width) vs \(metrics.notchSize.width))")
            check(metrics.collapsedIdle.height < metrics.notchSize.height,
                  "idle capsule is shorter than the notch")
            check(metrics.notchSize.width >= 120 && metrics.notchSize.width <= 280,
                  "notch width is within sane bounds, got \(metrics.notchSize.width)")
        }

        // Hover target: a point at the top centre must hit; one well below must not.
        let idleRect = metrics.hoverRect(on: screen, currentSize: metrics.collapsedIdle)
        let centreX = screen.frame.midX
        check(idleRect.contains(NSPoint(x: centreX, y: screen.frame.maxY - 2)),
              "hover rect catches the cursor at the top centre")
        check(!idleRect.contains(NSPoint(x: centreX, y: screen.frame.maxY - 200)),
              "hover rect ignores the cursor far below the notch")

        // The old fixed 240pt floor swallowed clicks on menu-bar items near centre.
        check(idleRect.width < 240, "hover rect no longer spans the old 240pt minimum")

        // Expanded: the rect must grow with the panel, or the island would collapse
        // the moment the cursor moved onto its own body.
        let expandedRect = metrics.hoverRect(on: screen, currentSize: CGSize(width: 380, height: 170))
        check(expandedRect.contains(NSPoint(x: centreX, y: screen.frame.maxY - 160)),
              "expanded hover rect covers the panel body")
    }

    // MARK: - Zen timer formatting

    suite("ZenManager") {
        let zen = ZenManager()
        checkEqual(zen.durationFormatted, "15 Min", "default duration")
        checkEqual(zen.timeFormatted, "15:00", "default countdown rounds up to a whole minute")

        zen.adjustDuration(by: 5 * 60)
        checkEqual(zen.durationFormatted, "20 Min", "increments by five minutes")

        // Clamping: must refuse to go below 1 minute or above 2 hours.
        for _ in 0..<10 { zen.adjustDuration(by: -5 * 60) }
        check(zen.duration >= 60, "duration never drops below one minute, got \(zen.duration)")

        for _ in 0..<40 { zen.adjustDuration(by: 5 * 60) }
        check(zen.duration <= 120 * 60, "duration never exceeds two hours, got \(zen.duration)")
    }

    // MARK: - Clipboard

    suite("ClipboardManager") {
        let short = ClipboardManager.ClipboardItem(content: "  hello  ", timestamp: Date())
        checkEqual(short.preview, "hello", "preview trims whitespace")

        let long = ClipboardManager.ClipboardItem(content: String(repeating: "x", count: 500), timestamp: Date())
        checkEqual(long.preview.count, 100, "long previews truncate to 100 characters")
        check(long.preview.hasSuffix("..."), "truncated previews are elided")
    }

    // MARK: - Audio

    suite("AudioManager") {
        // Read-only: a test must never move the user's actual volume.
        let audio = AudioManager()
        check((0...100).contains(audio.volume), "reports a level in 0...100, got \(audio.volume)")
        check((0...100).contains(audio.displayVolume), "display level in range")
        if audio.isMuted {
            checkEqual(audio.displayVolume, 0, "a muted device displays as 0")
        } else {
            checkEqual(audio.displayVolume, audio.volume, "an unmuted device displays its scalar")
        }
    }

    // MARK: - Summary

    print("\n\(checks - failures)/\(checks) checks passed")
    if failures > 0 {
        print("\(failures) FAILED")
        exit(1)
    }
    print("All tests passed ✅")
}
