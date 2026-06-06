# MacNotch - macOS Dynamic Island

MacNotch is a native macOS application built with Swift and SwiftUI that brings a fluid, interactive **Dynamic Island** (like iPhone) to your MacBook's camera notch area. It is fully optimized for Apple Silicon (M1/M2/M3/M4) and Intel Macs, running as a lightweight, borderless accessory panel.

---

## ✨ Features by Tab

MacNotch organizes its interactive widgets into 7 responsive tabs aligned along the top bar.

### 1. 🎵 Music Controller (`music.note`)
* **Apple Music Integration**: Automatically monitors playback status, track names, artists, and album artwork using AppleScript.
* **Playback Controls**: Interactive buttons to Play/Pause, Skip Next, and Skip Previous.
* **Audio Visualizer**: A pulsing micro-animation visualizer that dances when music is active.
* **Dynamic Sizing**: Automatically drops to a compact `240px` capsule when collapsed to hug the notch.

### 2. 📅 Calendar Widget (`calendar`)
* **EventKit Integration**: Integrates directly with Apple Calendar (with permission handling).
* **Next Event Tracker**: Displays the title and localized start time of your next scheduled event within 24 hours.

### 3. 🏆 Live Sports Scoreboard (`trophy`)
* **ESPN Soccer API**: Pulls live soccer matches and scores across major global leagues (Premier League, La Liga, Serie A, Champions League, FIFA World Cup, etc.).
* **Favorite Team Tracking**: Specify a favorite team via the interface. The app automatically prioritizes tracking their live matches, falls back to the closest upcoming match, or shows the most recent finished match.
* **Local Timezone Conversion**: Automatically converts and formats kick-off times to your local timezone (e.g. IST).
* **Dynamic Polling Rate**: Intelligently updates scoreboards every 30 seconds if a favorite team's match is live, and scales back to 60 seconds when idle to conserve battery and network.
* **Camera Notch Clearance Sizing**: When sports tracking is active, the collapsed notch expands to `300px` (instead of the standard `240px`). This places the team logos, abbreviations, and scores at the absolute left and right ends, keeping them fully visible around the camera notch.
* **Dynamic Island Notifications**: Sends overlay banners inside the Island for match events: Kick-off, Goals, Half Time, and Full Time.

### 4. 📋 Clipboard History & File Shelf (`doc.on.clipboard`)
* **Background Monitoring**: Automatically monitors system copy pasteboard (`NSPasteboard`) and registers copied text.
* **History Capacity**: Stores a rolling history of up to 15 copied items.
* **Search & Filter**: Includes an integrated text search box to quickly filter through history items.
* **Instant Re-Copy**: Click any history item to instantly copy it back to your active pasteboard with visual checkmark feedback.
* **Quick File Shelf**: Drag and drop files or folders directly onto the island to place them in a fast-access shelf for quick reference or drag-out actions.

### 5. ⚙️ System Control & Metrics (`slider.horizontal.3`)
* **Battery Widget**: Circular live widget displaying battery percentage, coloring dynamically (green, yellow, red), with a charging indicator bolt.
* **System Volume**: Sliders to adjust output volume in real-time.
* **System Brightness**: Real-time display brightness slider using macOS display services APIs.
* **Realtime Metrics**: Live CPU and RAM usage bars polling every 2 seconds.

### 6. 🧘 Zen Mode / Rest Timer (`leaf.fill`)
* **Zen Rest Timer**: Designed to prompt breaks. Default duration is **15 minutes**.
* **Duration Controls**: Adjust timer duration in 5-minute increments (range: 1 min to 120 mins).
* **Auto-Collapse**: Collapses automatically upon starting to eliminate distraction.
* **Collapsed View Overlay**: The collapsed notch displays a green leaf icon and a running countdown timer.
* **Completion Alerts**: Plays a green Dynamic Island completion banner when the rest duration ends.

### 7. 🚀 Favorite Applications Panel (`square.grid.2x2.fill`)
* **App Grid**: A clean, Launchpad-like grid using high-resolution native macOS application icons.
* **Default Apps**: Pre-populated with Finder, Safari, Music, Mail, Settings, and Terminal.
* **Drag-and-Drop Installation**: Add any favorite app by dragging its `.app` file from Finder and dropping it onto the island.
* **Quick Removal**: Hover over an app in the grid and click the red `(X)` button, or right-click to choose "Remove Favorite" from the context menu.
* **One-Click Launch**: Launches apps instantly using `NSWorkspace`.

---

## 📐 Layout & Interaction Design

* **Fluid Animations**: Custom springy liquid animations when expanding, collapsing, or switching between tabs.
* **Glassmorphism Theme**: Jet-black translucent background (`opacity(0.85)`) with subtle glowing borders and drop shadows.
* **Accessory Agent Mode**: Runs quietly in the background. It does not clutter your Dock or Command+Tab switcher.
* **Mouse Interactions**:
  * **Expand**: Hover your mouse cursor over the collapsed black capsule at the top center of your display to expand the menu.
  * **Collapse**: Move your cursor away, and it will immediately snap back into its compact capsule shape.
  * **Zen Collapse**: Starting the Zen Mode timer immediately collapses the island for a distraction-free work/rest session.

---

## 🚀 How to Run & Start the Application

You can start the application in two ways:

### Method 1: Using the Terminal (Recommended)
Simply run the compilation and launch script:
```bash
./build.sh --run
```
This script will stop any running instances, compile the source files, package them into `MacNotch.app`, and launch it.

### Method 2: From Finder
1. Open the [MacNotch](file:///Users/abhay/Desktop/projects/MacNotch) folder in Finder.
2. Double-click the compiled application: **`MacNotch.app`**.
3. It will immediately appear at the top-center of your screen.

---

## ⌨️ Shortcuts & Quitting

* **Text Focus**: Click on the Clipboard tab's search box. The window will capture keyboard focus, allowing you to type and filter.
* **Quit the App**:
  * With the Clipboard search box focused, press `Cmd + Q`.
  * Or run this terminal command:
    ```bash
    killall MacNotch
    ```

---

## 🛠️ Project Structure

* [main.swift](file:///Users/abhay/Desktop/projects/MacNotch/main.swift): Configures the borderless `NSPanel` overlay window, sets transparent colors, forces alignment with the screen's top-center, and animates frame sizing.
* [NotchIslandView.swift](file:///Users/abhay/Desktop/projects/MacNotch/NotchIslandView.swift): Core SwiftUI layout, tab management, visualizer animations, widget layouts (Zen Mode, Favorite Apps, Clipboard, Notification overlays), and managers.
* [SportsManager.swift](file:///Users/abhay/Desktop/projects/MacNotch/SportsManager.swift): Handles soccer score fetching from the ESPN API, favorite team tracking, and local timezone conversions.
* [MusicManager.swift](file:///Users/abhay/Desktop/projects/MacNotch/MusicManager.swift): Asynchronously polls Apple Music via AppleScript to update play state, durations, track names, artwork, and control actions.
* [ClipboardManager.swift](file:///Users/abhay/Desktop/projects/MacNotch/ClipboardManager.swift): Monitors the system pasteboard (`NSPasteboard`) and keeps copy history.
* [SystemManager.swift](file:///Users/abhay/Desktop/projects/MacNotch/SystemManager.swift): Interfaces with macOS power services, display brightness, volume outputs, and CPU/RAM host metrics.
* [CalendarManager.swift](file:///Users/abhay/Desktop/projects/MacNotch/CalendarManager.swift): Interfaces with Apple Calendar (`EventKit`) to query upcoming events.
* [Info.plist](file:///Users/abhay/Desktop/projects/MacNotch/Info.plist): Bundle settings defining accessory status.
* [build.sh](file:///Users/abhay/Desktop/projects/MacNotch/build.sh): Automation script for compilation and run.
