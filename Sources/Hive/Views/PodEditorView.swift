import SwiftUI
import AppKit

struct PodEditorView: View {
    let pod: Pod?
    var onDismiss: () -> Void = {}
    @Environment(AppState.self) var state

    @State private var directory = ""
    @State private var workspace = 1
    @State private var mode: PodMode = .standalone
    @State private var windowGroup = ""
    @State private var leftPaneCount = 4
    @State private var leftProcessType: ProcessType = .claude
    @State private var middleCommand = ""
    @State private var middleType: ProcessType = .shell

    var isEditing: Bool { pod != nil }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(isEditing ? "Edit Pod" : "New Pod")
                    .font(.headline)
                Spacer()
                Button("Cancel") { onDismiss() }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
            }
            .padding()

            Divider()

            Form {
                Section("Location") {
                    DirectoryField(directory: $directory)

                    Picker("Workspace", selection: $workspace) {
                        ForEach(1...9, id: \.self) { num in
                            Text("\(num)").tag(num)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                Section("Window") {
                    Picker("Mode", selection: $mode) {
                        Text("Standalone").tag(PodMode.standalone)
                        Text("Tab").tag(PodMode.tab)
                    }
                    .pickerStyle(.segmented)

                    if mode == .tab {
                        let standalones = state.pods.filter {
                            $0.mode == .standalone && $0.workspace == workspace
                        }
                        if standalones.isEmpty {
                            Text("No standalone pods on workspace \(workspace)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        } else {
                            Picker("Parent Window", selection: $windowGroup) {
                                ForEach(standalones) { s in
                                    Text(s.displayName).tag(s.id)
                                }
                            }
                        }
                    }
                }

                Section("Left Column") {
                    Stepper("Panes: \(leftPaneCount)", value: $leftPaneCount, in: 1...8)

                    Picker("Process", selection: $leftProcessType) {
                        Text("Claude").tag(ProcessType.claude)
                        Text("Codex").tag(ProcessType.codex)
                        Text("Shell").tag(ProcessType.shell)
                    }
                    .pickerStyle(.segmented)
                }

                Section("Middle Pane") {
                    Picker("Type", selection: $middleType) {
                        Text("Shell").tag(ProcessType.shell)
                        Text("Custom").tag(ProcessType.custom)
                    }
                    .pickerStyle(.segmented)

                    if middleType == .custom {
                        TextField("Command", text: $middleCommand)
                            .textFieldStyle(.roundedBorder)
                    }
                }

                Section("Right Column") {
                    HStack {
                        Label("Lazygit", systemImage: "arrow.triangle.branch")
                        Spacer()
                        Text("Top")
                            .foregroundStyle(.secondary)
                    }
                    HStack {
                        Label("Shell", systemImage: "terminal")
                        Spacer()
                        Text("Bottom")
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .formStyle(.grouped)

            Divider()

            HStack {
                if let pod = pod {
                    PodLayoutView(pod: previewPod(from: pod))
                        .frame(height: 40)
                        .frame(maxWidth: 120)
                } else {
                    PodLayoutView(pod: previewPod(from: nil))
                        .frame(height: 40)
                        .frame(maxWidth: 120)
                }

                Spacer()

                Button(isEditing ? "Save" : "Create") {
                    save()
                    onDismiss()
                }
                .buttonStyle(.borderedProminent)
                .tint(.indigo)
                .disabled(directory.isEmpty)
            }
            .padding()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            if let pod = pod {
                directory = pod.directory
                workspace = pod.workspace
                mode = pod.mode
                windowGroup = pod.windowGroup
                leftPaneCount = pod.leftPanes.count
                leftProcessType = pod.leftPanes.first?.processType ?? .claude
                if let mid = pod.middlePane {
                    middleType = mid.processType
                    middleCommand = mid.customCommand ?? ""
                }
            }
        }
    }

    private func buildPanes() -> [PaneConfig] {
        var panes: [PaneConfig] = []

        for pos in PanePosition.leftPositions(count: leftPaneCount) {
            panes.append(PaneConfig(position: pos, processType: leftProcessType))
        }

        if middleType == .custom && !middleCommand.isEmpty {
            panes.append(PaneConfig(position: .middle, processType: .custom, customCommand: middleCommand))
        } else {
            panes.append(PaneConfig(position: .middle, processType: .shell))
        }

        panes.append(PaneConfig(position: .rightTop, processType: .lazygit))
        panes.append(PaneConfig(position: .rightBottom, processType: .shell))

        return panes
    }

    private func previewPod(from existing: Pod?) -> Pod {
        let id = existing?.id ?? "preview"
        let wg = mode == .standalone ? id : windowGroup
        return Pod(
            id: id,
            directory: directory.isEmpty ? "/preview" : directory,
            workspace: workspace,
            mode: mode,
            windowGroup: wg,
            panes: buildPanes(),
            createdAt: existing?.createdAt ?? Date()
        )
    }

    private func save() {
        let panes = buildPanes()

        if var existing = pod, let index = state.pods.firstIndex(where: { $0.id == existing.id }) {
            existing.directory = directory
            existing.workspace = workspace
            existing.mode = mode
            existing.windowGroup = mode == .standalone ? existing.id : windowGroup
            existing.panes = panes
            state.pods[index] = existing
        } else {
            let newId = Pod.newID()
            let newPod = Pod(
                id: newId,
                directory: directory,
                workspace: workspace,
                mode: mode,
                windowGroup: mode == .standalone ? newId : windowGroup,
                panes: panes,
                createdAt: Date()
            )
            state.pods.append(newPod)
        }

        Task { await state.save() }
    }

}
