import Foundation

/// Translates Hive pod snapshots into the Ghostty session restore JSON format.
/// The session document mirrors Ghostty's internal SplitTree model so that
/// Ghostty can create all windows, tabs, and panes in a single atomic call.

struct GhosttySessionDocument: Encodable {
    let version = 1
    let windows: [GhosttySessionWindow]
}

struct GhosttySessionWindow: Encodable {
    let id: String
    let title: String?
    let tabs: [GhosttySessionTab]
}

struct GhosttySessionTab: Encodable {
    let title: String?
    let surfaceTree: GhosttySessionSurfaceTree
}

struct GhosttySessionSurfaceTree: Encodable {
    let root: GhosttySessionNode?
}

indirect enum GhosttySessionNode: Encodable {
    case leaf(GhosttySessionSurface)
    case split(GhosttySessionSplit)

    struct GhosttySessionSplit: Encodable {
        let direction: GhosttySessionDirection
        let ratio: Double
        let left: GhosttySessionNode
        let right: GhosttySessionNode
    }

    func encode(to encoder: Encoder) throws {
        switch self {
        case .leaf(let surface):
            var container = encoder.container(keyedBy: LeafKeys.self)
            try container.encode(surface, forKey: .view)
        case .split(let split):
            var container = encoder.container(keyedBy: SplitKeys.self)
            try container.encode(split, forKey: .split)
        }
    }

    private enum LeafKeys: String, CodingKey { case view }
    private enum SplitKeys: String, CodingKey { case split }
}

/// Matches Ghostty's SplitTree.Direction Codable format: {"horizontal": {}} or {"vertical": {}}
enum GhosttySessionDirection: Encodable {
    case horizontal
    case vertical
}

struct GhosttySessionSurface: Encodable {
    let pwd: String?
    let initialInput: String?
    let title: String?
}

// MARK: - Pod to Session Translation

enum GhosttySessionBuilder {
    /// Convert a Hive pod snapshot into a Ghostty session document.
    /// Pods are grouped by windowGroup to form windows with tabs.
    static func buildSession(from pods: [Pod]) -> GhosttySessionDocument {
        let sorted = pods.sorted { a, b in
            if a.workspace != b.workspace { return a.workspace < b.workspace }
            return a.createdAt < b.createdAt
        }

        // Group pods into windows by windowGroup
        var windowOrder: [String] = []
        var windowPods: [String: [Pod]] = [:]

        for pod in sorted {
            let group = pod.windowGroup
            if windowPods[group] == nil {
                windowOrder.append(group)
            }
            windowPods[group, default: []].append(pod)
        }

        var windows: [GhosttySessionWindow] = []

        for group in windowOrder {
            guard let groupPods = windowPods[group], !groupPods.isEmpty else { continue }

            var tabs: [GhosttySessionTab] = []
            for pod in groupPods {
                let tree = buildSplitTree(from: pod)
                let title = URL(fileURLWithPath: pod.directory).lastPathComponent
                tabs.append(GhosttySessionTab(title: title, surfaceTree: tree))
            }

            let windowTitle = URL(fileURLWithPath: groupPods[0].directory).lastPathComponent
            windows.append(GhosttySessionWindow(id: group, title: windowTitle, tabs: tabs))
        }

        return GhosttySessionDocument(windows: windows)
    }

    /// Build the split tree for a single pod (tab).
    /// Layout: left column | middle | right column
    private static func buildSplitTree(from pod: Pod) -> GhosttySessionSurfaceTree {
        let leftPanes = pod.leftPanes
        let middle = pod.middlePane
        let rightPanes = pod.rightPanes

        let leftNode = buildColumn(panes: leftPanes, pod: pod)
        let middleNode = buildLeaf(pane: middle, pod: pod)
        let rightNode = buildColumn(panes: rightPanes, pod: pod)

        // Build three-column layout: left | middle | right
        let rightSection: GhosttySessionNode
        if let rightNode {
            rightSection = .split(.init(
                direction: .horizontal,
                ratio: 0.5,
                left: middleNode,
                right: rightNode
            ))
        } else {
            rightSection = middleNode
        }

        let root: GhosttySessionNode
        if let leftNode {
            root = .split(.init(
                direction: .horizontal,
                ratio: 0.33,
                left: leftNode,
                right: rightSection
            ))
        } else {
            root = rightSection
        }

        return GhosttySessionSurfaceTree(root: root)
    }

    /// Build a vertical column of panes.
    private static func buildColumn(panes: [PaneConfig], pod: Pod) -> GhosttySessionNode? {
        guard !panes.isEmpty else { return nil }
        if panes.count == 1 {
            return buildLeaf(pane: panes[0], pod: pod)
        }
        return buildVerticalSplits(panes: panes, pod: pod)
    }

    /// Recursively build vertical splits for N panes with equal ratios.
    private static func buildVerticalSplits(panes: [PaneConfig], pod: Pod) -> GhosttySessionNode {
        if panes.count == 1 {
            return buildLeaf(pane: panes[0], pod: pod)
        }

        let ratio = 1.0 / Double(panes.count)
        let top = buildLeaf(pane: panes[0], pod: pod)
        let bottom = buildVerticalSplits(panes: Array(panes.dropFirst()), pod: pod)

        return .split(.init(
            direction: .vertical,
            ratio: ratio,
            left: top,
            right: bottom
        ))
    }

    /// Build a leaf node for a single pane.
    private static func buildLeaf(pane: PaneConfig?, pod: Pod) -> GhosttySessionNode {
        let expandedDir = (pod.directory as NSString).expandingTildeInPath
        let shellEscapedDir = "'" + expandedDir.replacingOccurrences(of: "'", with: "'\\''") + "'"

        var lines = ["cd -- \(shellEscapedDir)"]
        if let cmd = pane?.launchCommand, !cmd.isEmpty {
            lines.append(cmd)
        }
        let input = lines.joined(separator: "\n") + "\n"

        return .leaf(GhosttySessionSurface(
            pwd: expandedDir,
            initialInput: input,
            title: nil
        ))
    }

    /// Write the session document to a timestamped file under
    /// ~/.claude-pods/sessions/ and update the ghostty-session.json symlink
    /// to point to it. Returns the path of the symlink.
    static func writeSessionFile(_ document: GhosttySessionDocument) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(document)

        let base = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude-pods")
        let sessionsDir = base.appendingPathComponent("sessions")
        try FileManager.default.createDirectory(at: sessionsDir, withIntermediateDirectories: true)

        // Write timestamped file
        let timestamp = ISO8601DateFormatter().string(from: Date())
            .replacingOccurrences(of: ":", with: "-")
        let filename = "ghostty-session-\(timestamp).json"
        let timestampedPath = sessionsDir.appendingPathComponent(filename)
        try data.write(to: timestampedPath)

        // Update symlink: remove old one and create new pointing to timestamped file
        let symlinkPath = base.appendingPathComponent("ghostty-session.json")
        try? FileManager.default.removeItem(at: symlinkPath)
        try FileManager.default.createSymbolicLink(
            at: symlinkPath,
            withDestinationURL: timestampedPath
        )

        return symlinkPath.path
    }
}
