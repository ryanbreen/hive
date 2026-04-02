import Foundation

enum PodMode: String, Codable, Hashable, Sendable {
    case standalone
    case tab
}

enum PanePosition: String, Codable, Hashable, Sendable, CaseIterable {
    case left0, left1, left2, left3, left4, left5, left6, left7
    case middle
    case rightTop, rightBottom

    var isLeft: Bool {
        switch self {
        case .left0, .left1, .left2, .left3, .left4, .left5, .left6, .left7:
            return true
        default:
            return false
        }
    }

    var isRight: Bool {
        switch self {
        case .rightTop, .rightBottom:
            return true
        default:
            return false
        }
    }

    var displayLabel: String {
        switch self {
        case .left0: return "Left 1"
        case .left1: return "Left 2"
        case .left2: return "Left 3"
        case .left3: return "Left 4"
        case .left4: return "Left 5"
        case .left5: return "Left 6"
        case .left6: return "Left 7"
        case .left7: return "Left 8"
        case .middle: return "Middle"
        case .rightTop: return "Right Top"
        case .rightBottom: return "Right Bottom"
        }
    }

    static func leftPositions(count: Int) -> [PanePosition] {
        let all: [PanePosition] = [.left0, .left1, .left2, .left3, .left4, .left5, .left6, .left7]
        return Array(all.prefix(count))
    }
}

enum ProcessType: String, Codable, Hashable, Sendable {
    case claude
    case codex
    case lazygit
    case shell
    case custom

    var displayName: String {
        switch self {
        case .claude: return "Claude"
        case .codex: return "Codex"
        case .lazygit: return "Lazygit"
        case .shell: return "Shell"
        case .custom: return "Custom"
        }
    }

    func resumeCommand(sessionId: String?) -> String? {
        switch self {
        case .claude:
            if let sid = sessionId, !sid.isEmpty {
                return "claude --resume \(sid)"
            }
            return "claude"
        case .codex:
            if let sid = sessionId, !sid.isEmpty {
                return "codex resume \(sid)"
            }
            return "codex"
        case .lazygit:
            return "lazygit"
        case .shell:
            return nil
        case .custom:
            return nil
        }
    }
}

struct PaneConfig: Codable, Hashable, Identifiable, Sendable {
    var id: String
    var position: PanePosition
    var processType: ProcessType
    var sessionId: String?
    var customCommand: String?

    init(position: PanePosition, processType: ProcessType, sessionId: String? = nil, customCommand: String? = nil) {
        self.id = UUID().uuidString.prefix(8).lowercased().description
        self.position = position
        self.processType = processType
        self.sessionId = sessionId
        self.customCommand = customCommand
    }

    var launchCommand: String? {
        if let cmd = customCommand, !cmd.isEmpty {
            return cmd
        }
        return processType.resumeCommand(sessionId: sessionId)
    }
}

struct Pod: Identifiable, Codable, Hashable, Sendable {
    let id: String
    var directory: String
    var workspace: Int
    var mode: PodMode
    var windowGroup: String
    var panes: [PaneConfig]
    var createdAt: Date

    var mainCmd: String?
    var claudeCount: Int?
    var claudeSessions: [String]?

    var displayName: String {
        URL(fileURLWithPath: directory).lastPathComponent
    }

    var leftPanes: [PaneConfig] {
        panes.filter { $0.position.isLeft }.sorted { $0.position.rawValue < $1.position.rawValue }
    }

    var middlePane: PaneConfig? {
        panes.first { $0.position == .middle }
    }

    var rightPanes: [PaneConfig] {
        panes.filter { $0.position.isRight }.sorted { pos1, pos2 in
            if pos1.position == .rightTop { return true }
            if pos2.position == .rightTop { return false }
            return false
        }
    }

    static func newID() -> String {
        UUID().uuidString.prefix(8).lowercased().description
    }

    enum CodingKeys: String, CodingKey {
        case id, directory, workspace, mode, windowGroup, panes, createdAt
        case mainCmd, claudeCount, claudeSessions
    }

    init(id: String, directory: String, workspace: Int, mode: PodMode, windowGroup: String, panes: [PaneConfig], createdAt: Date, mainCmd: String? = nil, claudeCount: Int? = nil, claudeSessions: [String]? = nil) {
        self.id = id
        self.directory = directory
        self.workspace = workspace
        self.mode = mode
        self.windowGroup = windowGroup
        self.panes = panes
        self.createdAt = createdAt
        self.mainCmd = mainCmd
        self.claudeCount = claudeCount
        self.claudeSessions = claudeSessions
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        directory = try container.decode(String.self, forKey: .directory)
        workspace = try container.decode(Int.self, forKey: .workspace)
        mode = try container.decode(PodMode.self, forKey: .mode)
        windowGroup = try container.decode(String.self, forKey: .windowGroup)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        mainCmd = try container.decodeIfPresent(String.self, forKey: .mainCmd)
        claudeCount = try container.decodeIfPresent(Int.self, forKey: .claudeCount)
        claudeSessions = try container.decodeIfPresent([String].self, forKey: .claudeSessions)
        panes = try container.decodeIfPresent([PaneConfig].self, forKey: .panes) ?? []
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(directory, forKey: .directory)
        try container.encode(workspace, forKey: .workspace)
        try container.encode(mode, forKey: .mode)
        try container.encode(windowGroup, forKey: .windowGroup)
        try container.encode(panes, forKey: .panes)
        try container.encode(createdAt, forKey: .createdAt)
        try container.encodeIfPresent(mainCmd, forKey: .mainCmd)
        try container.encodeIfPresent(claudeCount, forKey: .claudeCount)
        try container.encodeIfPresent(claudeSessions, forKey: .claudeSessions)
    }
}
