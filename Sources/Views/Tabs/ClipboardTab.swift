import SwiftUI
import Cocoa

struct ClipboardTab: View {
    @ObservedObject var clipboard: ClipboardManager
    @ObservedObject var fileShelf: FileShelfManager
    @ObservedObject var appState: AppState

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var search = ""
    @State private var recentlyCopiedId: UUID? = nil

    var body: some View {
        VStack(spacing: 8) {
            if !fileShelf.files.isEmpty {
                shelf
            }
            searchField
            historyList

            Divider()
                .background(Color.white.opacity(0.08))
                .padding(.horizontal, 16)

            HStack {
                Spacer()
                Button(action: { clipboard.clearHistory() }) {
                    Text("Clear History")
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                        .foregroundColor(.red.opacity(0.8))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.red.opacity(0.1))
                        .cornerRadius(6)
                }
                .buttonStyle(PlainButtonStyle())
                .padding(.trailing, 16)
                .padding(.bottom, 8)
                .accessibilityLabel("Clear clipboard history")
            }
        }
    }

    // MARK: - File shelf

    private var shelf: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(fileShelf.files) { file in
                    HStack(spacing: 6) {
                        Image(systemName: "doc.fill")
                            .font(.system(size: 10))
                            .foregroundColor(.pink)
                        Text(file.name)
                            .font(.system(size: 9, design: .rounded))
                            .foregroundColor(.white)
                            .lineLimit(1)
                            .frame(maxWidth: 80)

                        Button(action: { fileShelf.remove(file) }) {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 10))
                                .foregroundColor(.white.opacity(0.45))
                        }
                        .buttonStyle(PlainButtonStyle())
                        .accessibilityLabel("Remove \(file.name) from shelf")
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background(Color.white.opacity(0.08))
                    .cornerRadius(6)
                    .onDrag {
                        NSItemProvider(contentsOf: file.url) ?? NSItemProvider()
                    }
                }
            }
            .padding(.horizontal, 16)
        }
        .frame(height: 28)
        .padding(.top, 4)
    }

    // MARK: - Search

    private var searchField: some View {
        HStack {
            Image(systemName: "magnifyingglass")
                .foregroundColor(.white.opacity(0.45))
                .font(.system(size: 12))

            TextField("Search clipboard...", text: $search)
                .textFieldStyle(PlainTextFieldStyle())
                .font(.system(size: 12, design: .rounded))
                .foregroundColor(.white)

            if !search.isEmpty {
                Button(action: { search = "" }) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.white.opacity(0.45))
                }
                .buttonStyle(PlainButtonStyle())
                .accessibilityLabel("Clear search")
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(Color.white.opacity(0.08))
        .cornerRadius(8)
        .padding(.horizontal, 16)
        .padding(.top, 4)
    }

    // MARK: - History

    private var filteredItems: [ClipboardManager.ClipboardItem] {
        guard !search.isEmpty else { return clipboard.items }
        return clipboard.items.filter { $0.content.localizedCaseInsensitiveContains(search) }
    }

    private var historyList: some View {
        ScrollView {
            VStack(spacing: 6) {
                if filteredItems.isEmpty {
                    Text(clipboard.items.isEmpty ? "Nothing copied yet" : "No items found")
                        .font(.system(size: 11, design: .rounded))
                        .foregroundColor(.white.opacity(0.45))
                        .padding(.top, 24)
                } else {
                    ForEach(filteredItems) { item in
                        row(item)
                    }
                }
            }
            .padding(.horizontal, 16)
        }
        .frame(maxHeight: 180)
    }

    private func row(_ item: ClipboardManager.ClipboardItem) -> some View {
        HStack {
            Text(item.preview)
                .font(.system(size: 11, design: .monospaced))
                .foregroundColor(.white.opacity(0.85))
                .lineLimit(1)
                .frame(maxWidth: 320, alignment: .leading)

            Spacer()

            if recentlyCopiedId == item.id {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.green)
                    .font(.system(size: 12))
            } else {
                Image(systemName: "doc.on.doc")
                    .foregroundColor(.white.opacity(0.45))
                    .font(.system(size: 10))
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(Color.white.opacity(recentlyCopiedId == item.id ? 0.08 : 0.03))
        .cornerRadius(6)
        .contentShape(Rectangle())
        .onTapGesture { copy(item) }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(item.preview)
        .accessibilityHint("Copies to clipboard")
    }

    private func copy(_ item: ClipboardManager.ClipboardItem) {
        clipboard.copyToClipboard(item: item)
        withAnimation(reduceMotion ? nil : .default) {
            recentlyCopiedId = item.id
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            if recentlyCopiedId == item.id {
                recentlyCopiedId = nil
            }
        }

        // Collapse immediately and briefly lock hover so the island doesn't spring
        // straight back open under the cursor.
        appState.hoverLocked = true
        withAnimation(reduceMotion ? nil : .spring(response: 0.35, dampingFraction: 0.75)) {
            appState.isExpanded = false
        }

        (NSApp.delegate as? AppDelegate)?.restorePreviousActiveApp()

        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            appState.hoverLocked = false
        }
    }
}
