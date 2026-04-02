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

actor YabaiService {
    private func run(_ arguments: [String]) async throws -> Data {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["yabai"] + arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()
        try process.run()
        process.waitUntilExit()
        return pipe.fileHandleForReading.readDataToEndOfFile()
    }

    private func runCommand(_ arguments: [String]) async throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["yabai"] + arguments
        process.standardOutput = Pipe()
        process.standardError = Pipe()
        try process.run()
        process.waitUntilExit()
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

    func moveWindow(windowId: Int, toSpace space: Int) async throws {
        try await runCommand(["-m", "window", "\(windowId)", "--space", "\(space)"])
    }

    func ghosttyWindows() async throws -> [YabaiWindow] {
        let data = try await run(["-m", "query", "--windows"])
        let windows = try JSONDecoder().decode([YabaiWindow].self, from: data)
        return windows.filter { $0.app == "Ghostty" }
    }

    func ghosttyWindowsOnSpace(_ space: Int) async throws -> [YabaiWindow] {
        let data = try await run(["-m", "query", "--windows", "--space", "\(space)"])
        let windows = try JSONDecoder().decode([YabaiWindow].self, from: data)
        return windows.filter { $0.app == "Ghostty" }
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
