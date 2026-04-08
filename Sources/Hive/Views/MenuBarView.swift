import SwiftUI

struct MenuBarView: View {
    @Environment(AppState.self) var state
    @State private var searchText = ""
    @State private var isSearching = false
    @State private var collapsedWorkspaces: Set<Int> = []
    @FocusState private var searchFieldFocused: Bool

    private var filteredGroups: [(workspace: Int, pods: [Pod])] {
        if searchText.isEmpty {
            return state.podsByWorkspace
        }
        let query = searchText.lowercased()
        return state.podsByWorkspace.compactMap { group in
            let matched = group.pods.filter {
                $0.displayName.lowercased().contains(query) ||
                $0.directory.lowercased().contains(query)
            }
            if matched.isEmpty { return nil }
            return (workspace: group.workspace, pods: matched)
        }
    }

    var body: some View {
        Group {
            switch state.navigationMode {
            case .list:
                listContent
            case .creating:
                PodEditorView(pod: nil) {
                    state.navigationMode = .list
                }
                .environment(state)
            case .editing(let podId):
                if let pod = state.pods.first(where: { $0.id == podId }) {
                    PodEditorView(pod: pod) {
                        state.navigationMode = .list
                        state.selectedPodId = nil
                    }
                    .environment(state)
                } else {
                    listContent
                }
            }
        }
        .frame(width: 440, height: 620)
        .task {
            await state.load()
        }
        .alert(
            "Hive Error",
            isPresented: Binding(
                get: { state.error != nil },
                set: { presented in
                    if !presented {
                        state.error = nil
                    }
                }
            ),
            actions: {
                Button("OK", role: .cancel) {
                    state.error = nil
                }
            },
            message: {
                Text(state.error ?? "Unknown error")
            }
        )
    }

    private var listContent: some View {
        VStack(spacing: 0) {
            header
            Divider()

            if isSearching {
                searchBar
                Divider()
            }

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 12, pinnedViews: .sectionHeaders) {
                        ForEach(filteredGroups, id: \.workspace) { group in
                            Section {
                                if !collapsedWorkspaces.contains(group.workspace) {
                                    ForEach(group.pods) { pod in
                                        PodCardView(pod: pod)
                                    }
                                }
                            } header: {
                                workspaceSectionHeader(group: group)
                            }
                            .id(group.workspace)
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                }
                .onKeyPress(keys: Set("123456789".map { KeyEquivalent(Character(String($0))) })) { press in
                    if isSearching { return .ignored }
                    if let num = Int(String(press.key.character)) {
                        collapsedWorkspaces.remove(num)
                        withAnimation {
                            proxy.scrollTo(num, anchor: .top)
                        }
                        return .handled
                    }
                    return .ignored
                }
                .onKeyPress(KeyEquivalent("/")) {
                    if isSearching { return .ignored }
                    isSearching = true
                    searchFieldFocused = true
                    return .handled
                }
                .onKeyPress(.escape) {
                    if isSearching {
                        searchText = ""
                        isSearching = false
                        searchFieldFocused = false
                        return .handled
                    }
                    return .ignored
                }
            }

            Divider()
            footer
        }
    }

    private var searchBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
                .font(.caption)
            TextField("Search pods...", text: $searchText)
                .textFieldStyle(.plain)
                .font(.system(.body))
                .focused($searchFieldFocused)
                .onSubmit {
                    if let firstPod = filteredGroups.first?.pods.first {
                        Task { await launchPod(firstPod) }
                    }
                }
            if !searchText.isEmpty {
                Button {
                    searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                        .font(.caption)
                }
                .buttonStyle(.plain)
            }
            Button {
                searchText = ""
                isSearching = false
                searchFieldFocused = false
            } label: {
                Text("Esc")
                    .font(.system(.caption, weight: .medium))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(.quaternary, in: RoundedRectangle(cornerRadius: 3))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }

    private func workspaceSectionHeader(group: (workspace: Int, pods: [Pod])) -> some View {
        let isCollapsed = collapsedWorkspaces.contains(group.workspace)
        return HStack(spacing: 8) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    if isCollapsed {
                        collapsedWorkspaces.remove(group.workspace)
                    } else {
                        collapsedWorkspaces.insert(group.workspace)
                    }
                }
            } label: {
                HStack {
                    Image(systemName: isCollapsed ? "chevron.right" : "chevron.down")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(.tertiary)
                        .frame(width: 10)
                    Image(systemName: "square.grid.2x2")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("Workspace \(group.workspace)")
                        .font(.system(.caption, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .textCase(.uppercase)
                    Spacer()
                    Text("\(group.pods.count)")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(.quaternary, in: Capsule())
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Button {
                Task { await rebuild(workspaces: [group.workspace]) }
            } label: {
                HStack(spacing: 4) {
                    if state.isRebuilding {
                        ProgressView()
                            .controlSize(.mini)
                    } else {
                        Image(systemName: "arrow.clockwise")
                            .font(.caption)
                    }
                    Text("Relaunch")
                        .font(.caption)
                }
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .disabled(state.isRebuilding)
            .help("Relaunch workspace \(group.workspace)")
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 6)
        .background(.background)
    }

    private func launchPod(_ pod: Pod) async {
        do {
            await state.refreshSessions(for: pod.id)
            guard let updatedPod = state.pods.first(where: { $0.id == pod.id }) else { return }
            let launcher = PodLauncher()
            try await launcher.launch(pod: updatedPod)
        } catch {
            state.error = error.localizedDescription
        }
    }

    private var header: some View {
        HStack {
            BackupStatusIcon(backupMode: state.backupMode, size: 18)
            Text("Hive")
                .font(.system(.headline, weight: .bold))

            Spacer()

            if !state.backupMode.isEnabled {
                Button("Enable Backups") {
                    Task { await state.enableAutomaticBackups() }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .tint(.yellow)
                .help("Create a new authoritative backup checkpoint")
            }

            Button {
                state.isCreatingPod = true
            } label: {
                Image(systemName: "plus.circle.fill")
                    .font(.title3)
            }
            .buttonStyle(.plain)
            .help("Create new pod")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    private var footer: some View {
        HStack {
            Button {
                Task { await rebuildAll() }
            } label: {
                HStack(spacing: 4) {
                    if state.isRebuilding {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Image(systemName: "arrow.clockwise")
                    }
                    Text("Rebuild All")
                }
            }
            .buttonStyle(.plain)
            .disabled(state.isRebuilding)

            Spacer()

            HStack(spacing: 10) {
                Text(state.backupMode.isEnabled ? "Backups on" : "Backups paused")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("\(state.pods.count) pods")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    private func rebuildAll() async {
        await rebuild(workspaces: nil)
    }

    private func rebuild(workspaces: [Int]?) async {
        state.isRebuilding = true
        defer { state.isRebuilding = false }

        do {
            let podIDs = state.pods
                .filter { pod in
                    guard let workspaces else { return true }
                    return workspaces.contains(pod.workspace)
                }
                .map(\.id)

            for podID in podIDs {
                await state.refreshSessions(for: podID)
            }

            let podsToLaunch = state.pods.filter { pod in
                guard let workspaces else { return true }
                return workspaces.contains(pod.workspace)
            }

            let launcher = PodLauncher()
            try await launcher.rebuildAll(pods: podsToLaunch)
        } catch {
            state.error = "Rebuild failed: \(error.localizedDescription)"
        }
    }
}
