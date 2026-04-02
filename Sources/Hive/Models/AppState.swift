import Foundation
import SwiftUI

enum NavigationMode: Equatable {
    case list
    case creating
    case editing(podId: String)
}

@Observable
@MainActor
final class AppState {
    var pods: [Pod] = []
    var selectedPodId: String?
    var navigationMode: NavigationMode = .list
    var isRebuilding = false
    var error: String?

    var isCreatingPod: Bool {
        get { navigationMode == .creating }
        set { navigationMode = newValue ? .creating : .list }
    }

    var isEditingPod: Bool {
        get {
            if case .editing = navigationMode { return true }
            return false
        }
        set {
            if newValue, let id = selectedPodId {
                navigationMode = .editing(podId: id)
            } else {
                navigationMode = .list
                selectedPodId = nil
            }
        }
    }

    var editingPod: Pod? {
        if case .editing(let podId) = navigationMode {
            return pods.first { $0.id == podId }
        }
        return nil
    }

    private let stateService = StateService()
    private let sessionService = SessionService()

    var podsByWorkspace: [(workspace: Int, pods: [Pod])] {
        let grouped = Dictionary(grouping: pods) { $0.workspace }
        return grouped.keys.sorted().map { key in
            (workspace: key, pods: grouped[key]!.sorted { $0.createdAt < $1.createdAt })
        }
    }

    func load() async {
        do {
            pods = try await stateService.load()
        } catch {
            self.error = error.localizedDescription
        }
    }

    func save() async {
        do {
            try await stateService.save(pods)
        } catch {
            self.error = error.localizedDescription
        }
    }

    func deletePod(_ id: String) async {
        pods.removeAll { $0.id == id }
        if selectedPodId == id {
            selectedPodId = nil
        }
        await save()
    }

    func refreshSessions(for podId: String) async {
        guard let index = pods.firstIndex(where: { $0.id == podId }) else { return }
        let pod = pods[index]

        let claudeSessions = await sessionService.discoverClaudeSessions(for: pod.directory)
        let codexSessions = await sessionService.discoverCodexSessions(for: pod.directory)

        var updatedPanes = pod.panes
        var claudeQueue = claudeSessions
        var codexQueue = codexSessions

        for i in updatedPanes.indices {
            switch updatedPanes[i].processType {
            case .claude:
                if !claudeQueue.isEmpty {
                    updatedPanes[i].sessionId = claudeQueue.removeFirst().id
                }
            case .codex:
                if !codexQueue.isEmpty {
                    updatedPanes[i].sessionId = codexQueue.removeFirst().id
                }
            default:
                break
            }
        }

        pods[index].panes = updatedPanes
    }
}
