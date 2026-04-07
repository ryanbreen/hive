import Foundation

struct YabaiWindow: Decodable, Sendable {
    let id: Int
    let app: String
    let title: String
    let space: Int
    let frame: YabaiFrame?
    let hasFocus: Bool?

    enum CodingKeys: String, CodingKey {
        case id, app, title, space, frame
        case hasFocus = "has-focus"
    }
}

struct YabaiFrame: Decodable, Sendable {
    let x: Double
    let y: Double
    let w: Double
    let h: Double
}

private extension YabaiWindow {
    var isGhosttyWindow: Bool {
        app.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == "ghostty"
    }
}

actor YabaiService {
    private let executablePath: String?

    init(
        executablePath: String? = nil,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) {
        self.executablePath = executablePath ?? Self.locateExecutablePath(environment: environment)
    }

    static func locateExecutablePath(
        environment: [String: String],
        fileExists: (String) -> Bool = { FileManager.default.isExecutableFile(atPath: $0) }
    ) -> String? {
        let pathEntries = environment["PATH"]?
            .split(separator: ":")
            .map(String.init) ?? []

        let candidates = pathEntries.map { "\($0)/yabai" } + [
            "/opt/homebrew/bin/yabai",
            "/usr/local/bin/yabai",
            "/opt/local/bin/yabai"
        ]

        for candidate in candidates {
            if fileExists(candidate) {
                return candidate
            }
        }
        return nil
    }

    private func resolvedExecutablePath() throws -> String {
        guard let executablePath else {
            throw HiveError.yabaiQueryFailed("Could not find yabai binary. Install yabai or add it to PATH.")
        }
        return executablePath
    }

    private func run(_ arguments: [String]) async throws -> Data {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: try resolvedExecutablePath())
        process.arguments = arguments
        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr
        try process.run()
        process.waitUntilExit()
        let output = stdout.fileHandleForReading.readDataToEndOfFile()
        let error = stderr.fileHandleForReading.readDataToEndOfFile()
        try validateTermination(process: process, errorData: error, arguments: arguments)
        return output
    }

    private func runCommand(_ arguments: [String]) async throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: try resolvedExecutablePath())
        process.arguments = arguments
        process.standardOutput = Pipe()
        let stderr = Pipe()
        process.standardError = stderr
        try process.run()
        process.waitUntilExit()
        let error = stderr.fileHandleForReading.readDataToEndOfFile()
        try validateTermination(process: process, errorData: error, arguments: arguments)
    }

    private func validateTermination(process: Process, errorData: Data, arguments: [String]) throws {
        guard process.terminationStatus == 0 else {
            let stderr = String(data: errorData, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let message = stderr?.isEmpty == false
                ? stderr!
                : "Command failed: yabai \(arguments.joined(separator: " "))"
            throw HiveError.yabaiQueryFailed(message)
        }
    }

    func currentSpace() async throws -> Int {
        let data = try await run(["-m", "query", "--spaces", "--space"])
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let index = json["index"] as? Int else {
            throw HiveError.yabaiQueryFailed("Could not parse current space")
        }
        return index
    }

    func focusSpace(_ space: Int) async throws {
        try await runCommand(["-m", "space", "--focus", "\(space)"])
    }

    func focusWindow(windowId: Int) async throws {
        try await runCommand(["-m", "window", "--focus", "\(windowId)"])
    }

    func moveWindow(windowId: Int, toSpace space: Int) async throws {
        try await runCommand(["-m", "window", "\(windowId)", "--space", "\(space)"])
    }

    func ghosttyWindows() async throws -> [YabaiWindow] {
        let data = try await run(["-m", "query", "--windows"])
        let windows = try JSONDecoder().decode([YabaiWindow].self, from: data)
        return windows.filter(\.isGhosttyWindow)
    }

    func ghosttyWindowsOnSpace(_ space: Int) async throws -> [YabaiWindow] {
        let data = try await run(["-m", "query", "--windows", "--space", "\(space)"])
        let windows = try JSONDecoder().decode([YabaiWindow].self, from: data)
        return windows.filter(\.isGhosttyWindow)
    }

    func newestGhosttyWindow() async throws -> YabaiWindow? {
        let windows = try await ghosttyWindows()
        return windows.max { $0.id < $1.id }
    }
}

enum HiveError: Error, LocalizedError {
    case yabaiQueryFailed(String)
    case ghosttyAutomationFailed(String)
    case stateError(String)

    var errorDescription: String? {
        switch self {
        case .yabaiQueryFailed(let msg): return "Yabai: \(msg)"
        case .ghosttyAutomationFailed(let msg): return "Ghostty: \(msg)"
        case .stateError(let msg): return "State: \(msg)"
        }
    }
}
