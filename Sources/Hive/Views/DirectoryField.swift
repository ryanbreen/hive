import SwiftUI
import AppKit

struct DirectoryField: View {
    @Binding var directory: String
    @State private var suggestions: [String] = []
    @State private var selectedIndex = 0
    @State private var showSuggestions = false
    @FocusState private var isFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            TextField("~/", text: $directory)
                .textFieldStyle(.roundedBorder)
                .font(.system(.body, design: .monospaced))
                .focused($isFocused)
                .onChange(of: directory) { _, newValue in
                    updateSuggestions(for: newValue)
                }
                .onKeyPress(.tab) {
                    handleTab()
                    return .handled
                }
                .onKeyPress(.downArrow) {
                    guard showSuggestions && !suggestions.isEmpty else { return .ignored }
                    selectedIndex = min(selectedIndex + 1, suggestions.count - 1)
                    return .handled
                }
                .onKeyPress(.upArrow) {
                    guard showSuggestions && !suggestions.isEmpty else { return .ignored }
                    selectedIndex = max(selectedIndex - 1, 0)
                    return .handled
                }
                .onKeyPress(.return) {
                    guard showSuggestions && !suggestions.isEmpty else { return .ignored }
                    directory = suggestions[selectedIndex]
                    showSuggestions = false
                    updateSuggestions(for: directory)
                    return .handled
                }
                .onKeyPress(.escape) {
                    guard showSuggestions else { return .ignored }
                    showSuggestions = false
                    return .handled
                }

            if showSuggestions && !suggestions.isEmpty {
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(Array(suggestions.enumerated()), id: \.offset) { index, path in
                            let isSelected = index == selectedIndex
                            let bg: Color = isSelected ? .accentColor : .clear
                            let fg: Color = isSelected ? .white : .primary

                            HStack(spacing: 4) {
                                Text(displayName(for: path))
                                    .font(.system(size: 11, design: .monospaced))
                                    .foregroundStyle(fg)
                                Spacer()
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 2)
                            .background(bg, in: RoundedRectangle(cornerRadius: 3))
                            .contentShape(Rectangle())
                            .onTapGesture {
                                directory = path
                                showSuggestions = false
                                updateSuggestions(for: path)
                                isFocused = true
                            }
                        }
                    }
                    .padding(4)
                }
                .frame(maxHeight: 120)
                .background(.background, in: RoundedRectangle(cornerRadius: 6))
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .strokeBorder(.separator, lineWidth: 0.5)
                )
            }
        }
        .onAppear {
            if directory.isEmpty {
                directory = "~/"
            }
        }
    }

    private func handleTab() {
        if suggestions.isEmpty {
            updateSuggestions(for: directory)
            if suggestions.isEmpty { NSSound.beep() }
            return
        }

        if suggestions.count == 1 {
            directory = suggestions[0]
            showSuggestions = false
            updateSuggestions(for: directory)
            return
        }

        let prefix = commonPrefix(suggestions)
        if prefix.count > directory.count {
            directory = prefix
            updateSuggestions(for: directory)
        } else {
            NSSound.beep()
            showSuggestions = true
        }
    }

    private func expandPath(_ path: String) -> String {
        (path as NSString).expandingTildeInPath
    }

    private func contractPath(_ path: String) -> String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        if path.hasPrefix(home) {
            return "~" + path.dropFirst(home.count)
        }
        return path
    }

    private func directoryExists(_ path: String) -> Bool {
        var isDir: ObjCBool = false
        return FileManager.default.fileExists(atPath: expandPath(path), isDirectory: &isDir) && isDir.boolValue
    }

    private func updateSuggestions(for input: String) {
        guard !input.isEmpty else {
            suggestions = []
            showSuggestions = false
            return
        }

        let expanded = expandPath(input)
        let fm = FileManager.default

        let parentDir: String
        let prefix: String

        if input.hasSuffix("/") {
            parentDir = expanded
            prefix = ""
        } else {
            parentDir = (expanded as NSString).deletingLastPathComponent
            prefix = (expanded as NSString).lastPathComponent.lowercased()
        }

        var isDir: ObjCBool = false
        guard fm.fileExists(atPath: parentDir, isDirectory: &isDir), isDir.boolValue else {
            suggestions = []
            showSuggestions = false
            return
        }

        do {
            let contents = try fm.contentsOfDirectory(atPath: parentDir)
            let dirs = contents
                .filter { name in
                    let fullPath = (parentDir as NSString).appendingPathComponent(name)
                    var check: ObjCBool = false
                    fm.fileExists(atPath: fullPath, isDirectory: &check)
                    return check.boolValue && !name.hasPrefix(".")
                }
                .filter { name in
                    prefix.isEmpty || name.lowercased().hasPrefix(prefix)
                }
                .sorted()
                .prefix(20)
                .map { name in
                    contractPath((parentDir as NSString).appendingPathComponent(name)) + "/"
                }

            suggestions = Array(dirs)
            selectedIndex = 0
        } catch {
            suggestions = []
            showSuggestions = false
        }
    }

    private func commonPrefix(_ paths: [String]) -> String {
        guard let first = paths.first else { return "" }
        var prefix = first
        for path in paths.dropFirst() {
            while !path.hasPrefix(prefix) && !prefix.isEmpty {
                prefix = String(prefix.dropLast())
            }
        }
        return prefix
    }

    private func displayName(for path: String) -> String {
        let trimmed = path.hasSuffix("/") ? String(path.dropLast()) : path
        return (trimmed as NSString).lastPathComponent + "/"
    }
}
