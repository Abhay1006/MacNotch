import SwiftUI
import AppKit

/// Settings.
///
/// Before this, the Obsidian vault path, the quotes note, and the clipboard history size
/// were compile-time constants pointing at one specific home directory — which made the
/// app unusable for anyone but its author without editing the source.
struct SettingsTab: View {
    @ObservedObject var preferences: Preferences

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 10) {
                vaultSection
                Divider().background(Color.white.opacity(0.08))
                togglesSection
                Divider().background(Color.white.opacity(0.08))
                clipboardSection
                Divider().background(Color.white.opacity(0.08))
                quitRow
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
        }
    }

    // MARK: - Vault

    private var vaultSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            sectionLabel("Obsidian Vault", systemImage: "folder")

            HStack(spacing: 6) {
                Text(displayPath(preferences.obsidianVaultPath))
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundColor(vaultExists ? .white.opacity(0.75) : .orange)
                    .lineLimit(1)
                    .truncationMode(.head)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .help(preferences.obsidianVaultPath)

                Button("Choose…", action: chooseVault)
                    .font(.system(size: 9, weight: .semibold, design: .rounded))
                    .buttonStyle(PlainButtonStyle())
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Color.white.opacity(0.1))
                    .cornerRadius(5)
            }

            if !vaultExists {
                Text("Folder not found — tasks and quotes will fall back to built-ins.")
                    .font(.system(size: 8, design: .rounded))
                    .foregroundColor(.orange.opacity(0.9))
            }
        }
    }

    private var vaultExists: Bool {
        var isDirectory: ObjCBool = false
        let exists = FileManager.default.fileExists(
            atPath: preferences.obsidianVaultPath,
            isDirectory: &isDirectory
        )
        return exists && isDirectory.boolValue
    }

    private func chooseVault() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Select Vault"
        panel.directoryURL = URL(fileURLWithPath: preferences.obsidianVaultPath)

        // An accessory app has no regular activation, so bring it forward or the
        // panel opens behind whatever the user was working in.
        NSApp.activate(ignoringOtherApps: true)
        if panel.runModal() == .OK, let url = panel.url {
            preferences.obsidianVaultPath = url.path
        }
    }

    // MARK: - Toggles

    private var togglesSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            settingToggle(
                "Launch at login",
                isOn: $preferences.launchAtLogin,
                caption: nil
            )
            settingToggle(
                "Look up missing album art",
                isOn: $preferences.artworkLookupEnabled,
                caption: "Sends the track title and artist to Apple's iTunes Search API."
            )
            settingToggle(
                "Show on external displays",
                isOn: $preferences.showOnExternalDisplays,
                caption: nil
            )
        }
    }

    private func settingToggle(_ title: String, isOn: Binding<Bool>, caption: String?) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Toggle(isOn: isOn) {
                Text(title)
                    .font(.system(size: 10, weight: .medium, design: .rounded))
                    .foregroundColor(.white.opacity(0.9))
            }
            .toggleStyle(.switch)
            .controlSize(.mini)
            .tint(.pink)

            if let caption = caption {
                Text(caption)
                    .font(.system(size: 8, design: .rounded))
                    .foregroundColor(.white.opacity(0.5))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: - Clipboard

    private var clipboardSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            sectionLabel("Clipboard", systemImage: "doc.on.clipboard")

            Stepper(
                value: $preferences.clipboardHistoryLimit,
                in: 5...100,
                step: 5
            ) {
                Text("Keep \(preferences.clipboardHistoryLimit) items")
                    .font(.system(size: 10, weight: .medium, design: .rounded))
                    .foregroundColor(.white.opacity(0.9))
            }
            .controlSize(.mini)

            Text("Copies marked private by password managers are never recorded.")
                .font(.system(size: 8, design: .rounded))
                .foregroundColor(.white.opacity(0.5))
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - Quit

    private var quitRow: some View {
        HStack {
            Text("MacNotch \(Bundle.main.shortVersion)")
                .font(.system(size: 9, design: .rounded))
                .foregroundColor(.white.opacity(0.45))
            Spacer()
            Button(action: { NSApp.terminate(nil) }) {
                Text("Quit")
                    .font(.system(size: 9, weight: .bold, design: .rounded))
                    .foregroundColor(.red.opacity(0.9))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 3)
                    .background(Color.red.opacity(0.12))
                    .cornerRadius(5)
            }
            .buttonStyle(PlainButtonStyle())
            .accessibilityLabel("Quit MacNotch")
        }
    }

    // MARK: - Helpers

    private func sectionLabel(_ text: String, systemImage: String) -> some View {
        HStack(spacing: 5) {
            Image(systemName: systemImage)
                .font(.system(size: 9, weight: .bold))
                .foregroundColor(.pink)
            Text(text)
                .font(.system(size: 10, weight: .bold, design: .rounded))
                .foregroundColor(.white.opacity(0.8))
                .textCase(.uppercase)
        }
    }

    /// Abbreviate the home directory so the path fits the narrow panel.
    private func displayPath(_ path: String) -> String {
        (path as NSString).abbreviatingWithTildeInPath
    }
}

extension Bundle {
    var shortVersion: String {
        object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—"
    }
}
