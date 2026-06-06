# MacNotch - macOS Dynamic Island

MacNotch is a native macOS application built with Swift and SwiftUI that brings an interactive **Dynamic Island** (like iPhone) to your MacBook's notch area. It is fully optimized for Apple Silicon (M1/M2/M3/M4) Macs.

---

## ✨ Features

1. **🎵 Music Controller**
   * Automatically detects and tracks playback status for **Apple Music**.
   * Displays track title, artist, progress bar, and album artwork.
   * Play/Pause, Skip Next, and Skip Previous controls.
   * A beautiful mini **audio visualizer micro-animation** that pulses when music is active.

2. **📋 Clipboard History**
   * Automatically monitors the system pasteboard and captures copied text items in the background.
   * Stores a history of up to 15 recent items.
   * Includes a **search bar** to quickly filter through your history.
   * Click any history item to instantly re-copy it to your active clipboard (with visual checkmark feedback).
   * Brief auto-expansion animation when a new item is copied!

3. **⚙️ System Control**
   * Shows a circular live **Battery widget** showing the percentage, coloring dynamically based on level, and showing a green lightning bolt when charging.
   * Interactable **Volume slider** to adjust system output volume.
   * Interactable **Brightness slider** to adjust display brightness level.

4. **💫 Premium Design & Interactions**
   * Smooth, springy liquid animations when expanding, collapsing, and switching tabs.
   * Glassmorphism layout: Jet black translucent background with subtle glowing borders.
   * Positioned precisely around the MacBook camera notch at the top center of your display.
   * Accessory agent behavior: Runs quietly in the background without cluttering your Dock.

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

## 🖱️ How to Interact

* **Expansion**: Move your mouse pointer over the collapsed black capsule at the top center of your screen. It will instantly stretch open to show the menu.
* **Collapse**: Move your mouse pointer away from the menu, and it will snap back into its compact capsule shape.
* **Tabs**: Switch widgets using the icons at the top of the expanded island:
  * 🎵 **Music** (`music.note`)
  * 📋 **Clipboard** (`doc.on.clipboard`)
  * ⚙️ **System Control** (`slider.horizontal.3`)
* **Search & Type**: Click on the Clipboard tab and select the search text box. The window will capture keyboard focus, allowing you to type and filter.
* **Quit the App**:
  * Open the Clipboard tab, click on the search text box to focus the app, and press `Cmd + Q`.
  * Or, run the following in terminal:
    ```bash
    killall MacNotch
    ```

---

## 🛠️ Project Structure

* [main.swift](file:///Users/abhay/Desktop/projects/MacNotch/main.swift): Configures the borderless `NSPanel` overlay window, sets transparent colors, forces alignment with the screen's top-center, and animates frame sizing.
* [NotchIslandView.swift](file:///Users/abhay/Desktop/projects/MacNotch/NotchIslandView.swift): Core SwiftUI layout, tab management, visualizer animations, and widget styling.
* [ClipboardManager.swift](file:///Users/abhay/Desktop/projects/MacNotch/ClipboardManager.swift): Monitors the system pasteboard (`NSPasteboard`) and keeps copy history.
* [MusicManager.swift](file:///Users/abhay/Desktop/projects/MacNotch/MusicManager.swift): Asynchronously polls Apple Music via AppleScript to update play state, durations, track names, artwork, and control actions.
* [SystemManager.swift](file:///Users/abhay/Desktop/projects/MacNotch/SystemManager.swift): Interfaces with macOS power services and volume outputs.
* [Info.plist](file:///Users/abhay/Desktop/projects/MacNotch/Info.plist): Bundle settings defining accessory status.
* [build.sh](file:///Users/abhay/Desktop/projects/MacNotch/build.sh): Automation script for compilation and run.
