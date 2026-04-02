import Foundation

struct DiscoveredSession: Sendable {
    let id: String
    let processType: ProcessType
    let modifiedAt: Date
}

actor SessionService {
    private let fileManager = FileManager.default

    func discoverClaudeSessions(for directory: String) -> [DiscoveredSession] {
        let home = fileManager.homeDirectoryForCurrentUser
        let encodedPath = directory
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: "_", with: "-")
        let projectDir = home
            .appendingPathComponent(".claude/projects")
            .appendingPathComponent(encodedPath)

        guard fileManager.fileExists(atPath: projectDir.path) else {
            return []
        }

        do {
            let contents = try fileManager.contentsOfDirectory(at: projectDir, includingPropertiesForKeys: [.contentModificationDateKey], options: [.skipsHiddenFiles])
            let jsonlFiles = contents.filter { $0.pathExtension == "jsonl" }

            var sessions: [DiscoveredSession] = []
            for file in jsonlFiles {
                let attrs = try file.resourceValues(forKeys: [.contentModificationDateKey])
                let modDate = attrs.contentModificationDate ?? Date.distantPast
                let sessionId = file.deletingPathExtension().lastPathComponent
                sessions.append(DiscoveredSession(id: sessionId, processType: .claude, modifiedAt: modDate))
            }

            return sessions.sorted { $0.modifiedAt > $1.modifiedAt }
        } catch {
            return []
        }
    }

    func discoverCodexSessions(for directory: String) -> [DiscoveredSession] {
        let home = fileManager.homeDirectoryForCurrentUser
        let sessionsDir = home.appendingPathComponent(".codex/sessions")

        guard fileManager.fileExists(atPath: sessionsDir.path) else {
            return []
        }

        var sessions: [DiscoveredSession] = []
        let calendar = Calendar.current
        let today = Date()

        for dayOffset in 0..<7 {
            guard let date = calendar.date(byAdding: .day, value: -dayOffset, to: today) else { continue }
            let year = calendar.component(.year, from: date)
            let month = String(format: "%02d", calendar.component(.month, from: date))
            let day = String(format: "%02d", calendar.component(.day, from: date))

            let dayDir = sessionsDir
                .appendingPathComponent("\(year)")
                .appendingPathComponent(month)
                .appendingPathComponent(day)

            guard fileManager.fileExists(atPath: dayDir.path) else { continue }

            do {
                let contents = try fileManager.contentsOfDirectory(at: dayDir, includingPropertiesForKeys: [.contentModificationDateKey], options: [])
                let rolloutFiles = contents.filter {
                    $0.lastPathComponent.hasPrefix("rollout-") && $0.pathExtension == "jsonl"
                }

                for file in rolloutFiles {
                    guard let session = parseCodexSession(file: file, matchDirectory: directory) else { continue }
                    sessions.append(session)
                }
            } catch {
                continue
            }
        }

        return sessions.sorted { $0.modifiedAt > $1.modifiedAt }
    }

    private func parseCodexSession(file: URL, matchDirectory: String) -> DiscoveredSession? {
        guard let handle = try? FileHandle(forReadingFrom: file) else { return nil }
        defer { try? handle.close() }

        let chunkSize = 4096
        guard let data = try? handle.read(upToCount: chunkSize), !data.isEmpty else { return nil }

        guard let text = String(data: data, encoding: .utf8) else { return nil }
        guard let firstLine = text.components(separatedBy: "\n").first, !firstLine.isEmpty else { return nil }
        guard let lineData = firstLine.data(using: .utf8) else { return nil }

        do {
            guard let json = try JSONSerialization.jsonObject(with: lineData) as? [String: Any],
                  let type = json["type"] as? String, type == "session_meta",
                  let payload = json["payload"] as? [String: Any],
                  let cwd = payload["cwd"] as? String,
                  let sessionId = payload["id"] as? String else {
                return nil
            }

            let normalizedCwd = (cwd as NSString).standardizingPath
            let normalizedMatch = (matchDirectory as NSString).standardizingPath
            guard normalizedCwd == normalizedMatch else { return nil }

            let attrs = try file.resourceValues(forKeys: [.contentModificationDateKey])
            let modDate = attrs.contentModificationDate ?? Date.distantPast

            return DiscoveredSession(id: sessionId, processType: .codex, modifiedAt: modDate)
        } catch {
            return nil
        }
    }
}
