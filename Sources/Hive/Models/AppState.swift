import Foundation
import SwiftUI

enum NavigationMode: Equatable {
    case list
    case creating
    case editing(podId: String)
}

enum BackupMode: Equatable {
    case disabledUntilManualEnable
    case enabled

    var isEnabled: Bool {
        self == .enabled
    }
}

@Observable
@MainActor
final class AppState {
    var pods: [Pod] = []
    var selectedPodId: String?
    var navigationMode: NavigationMode = .list
    var backupMode: BackupMode = .disabledUntilManualEnable
    var isRebuilding = false
    var error: String?
    private var hasLoaded = false
    private var syncTask: Task<Void, Never>?

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
    private let runtimeTelemetry = RuntimeTelemetryService()

    var podsByWorkspace: [(workspace: Int, pods: [Pod])] {
        let grouped = Dictionary(grouping: pods) { $0.workspace }
        return grouped.keys.sorted().map { key in
            (workspace: key, pods: grouped[key]!.sorted { $0.createdAt < $1.createdAt })
        }
    }

    func load() async {
        guard !hasLoaded else { return }
        error = nil
        do {
            pods = try await stateService.load()
            hasLoaded = true
            startBackgroundSync()
        } catch {
            self.error = error.localizedDescription
        }
    }

    func save() async {
        error = nil
        do {
            try await persistUserState()
        } catch {
            self.error = error.localizedDescription
        }
    }

    func enableAutomaticBackups() async {
        guard !backupMode.isEnabled else { return }
        error = nil
        do {
            try await stateService.save(pods)
            backupMode = .enabled
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
        error = nil
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
        if updatedPanes != pod.panes {
            do {
                try await persistLiveSyncState(pods)
            } catch {
                self.error = error.localizedDescription
            }
        }
    }

    private func startBackgroundSync() {
        // Disabled: runtime telemetry was overwriting configured processType
        // with observed shell state, corrupting pod definitions on failed launches.
        // Re-enable once we separate "configured" vs "observed" pane state.
    }

    private func synchronizeRuntimeState() async {
        let events = await runtimeTelemetry.loadEvents()
        guard !events.isEmpty else { return }

        var updatedPods = pods
        var changed = false

        for event in events {
            guard let podIndex = updatedPods.firstIndex(where: { $0.id == event.podId }),
                  let paneIndex = updatedPods[podIndex].panes.firstIndex(where: { $0.id == event.paneId }) else {
                continue
            }

            switch event.event {
            case .process:
                guard let processType = ProcessType(rawValue: event.value) else { continue }
                if updatedPods[podIndex].panes[paneIndex].processType != processType {
                    updatedPods[podIndex].panes[paneIndex].processType = processType
                    updatedPods[podIndex].panes[paneIndex].sessionId = nil
                    updatedPods[podIndex].panes[paneIndex].customCommand = nil
                    changed = true
                }
            case .cwd:
                continue
            case .closed:
                continue
            }
        }

        guard changed else { return }
        pods = updatedPods

        do {
            try await persistLiveSyncState(updatedPods)
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func persistUserState() async throws {
        if backupMode.isEnabled {
            try await stateService.save(pods)
        } else {
            try await stateService.saveCurrentStateOnly(pods)
        }
    }

    private func persistLiveSyncState(_ pods: [Pod]) async throws {
        if backupMode.isEnabled {
            try await stateService.saveLiveSync(pods)
        } else {
            try await stateService.saveCurrentStateOnly(pods)
        }
    }
}
