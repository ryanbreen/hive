import Foundation

struct RuntimeTelemetryEvent: Codable, Sendable {
    enum EventType: String, Codable, Sendable {
        case cwd
        case process
        case closed
    }

    var timestamp: Double
    var podId: String
    var paneId: String
    var position: String
    var event: EventType
    var value: String
}

actor RuntimeTelemetryService {
    private let eventsFile: URL

    init(baseDirectory: URL? = nil) {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let stateDir = baseDirectory ?? home.appendingPathComponent(".claude-pods")
        eventsFile = stateDir.appendingPathComponent("runtime-events.jsonl")
    }

    func loadEvents() -> [RuntimeTelemetryEvent] {
        guard let data = try? Data(contentsOf: eventsFile),
              let text = String(data: data, encoding: .utf8),
              !text.isEmpty else {
            return []
        }

        let decoder = JSONDecoder()
        return text
            .split(whereSeparator: \.isNewline)
            .compactMap { line in
                guard let data = line.data(using: .utf8) else { return nil }
                return try? decoder.decode(RuntimeTelemetryEvent.self, from: data)
            }
            .sorted { $0.timestamp < $1.timestamp }
    }
}
