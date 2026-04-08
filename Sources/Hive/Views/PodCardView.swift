import SwiftUI

struct PodCardView: View {
    let pod: Pod
    @Environment(AppState.self) var state
    @State private var isHovered = false
    @State private var isRefreshing = false
    @State private var showDeleteConfirm = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(pod.displayName)
                            .font(.system(.body, weight: .semibold))
                            .lineLimit(1)

                        if pod.mode == .tab {
                            Text("TAB")
                                .font(.system(size: 8, weight: .bold))
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 4)
                                .padding(.vertical, 1)
                                .background(.quaternary, in: RoundedRectangle(cornerRadius: 3))
                        }
                    }

                    Text(pod.directory)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }

                Spacer()

                paneCountSummary
            }

            PodLayoutView(pod: pod)
                .frame(height: max(32, CGFloat(pod.leftPanes.count) * 12))

            HStack(spacing: 8) {
                Button {
                    Task { await refreshSessions() }
                } label: {
                    if isRefreshing {
                        ProgressView()
                            .controlSize(.mini)
                    } else {
                        Image(systemName: "arrow.triangle.2.circlepath")
                            .font(.caption)
                    }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(isRefreshing)
                .help("Refresh sessions")

                Spacer()

                Button {
                    state.selectedPodId = pod.id
                    state.isEditingPod = true
                } label: {
                    Image(systemName: "pencil")
                        .font(.caption)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)

                Button {
                    showDeleteConfirm = true
                } label: {
                    Image(systemName: "trash")
                        .font(.caption)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .confirmationDialog("Delete \(pod.displayName)?", isPresented: $showDeleteConfirm) {
                    Button("Delete", role: .destructive) {
                        Task { await state.deletePod(pod.id) }
                    }
                }
            }
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(isHovered ? Color.primary.opacity(0.04) : Color.primary.opacity(0.02))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(.quaternary, lineWidth: 0.5)
        )
        .onHover { isHovered = $0 }
    }

    private var paneCountSummary: some View {
        HStack(spacing: 4) {
            let claudeCount = pod.panes.filter { $0.processType == .claude }.count
            let codexCount = pod.panes.filter { $0.processType == .codex }.count

            if claudeCount > 0 {
                HStack(spacing: 2) {
                    Circle().fill(ProcessType.claude.color).frame(width: 6, height: 6)
                    Text("\(claudeCount)")
                        .font(.system(size: 10, weight: .medium, design: .rounded))
                        .foregroundStyle(.secondary)
                }
            }
            if codexCount > 0 {
                HStack(spacing: 2) {
                    Circle().fill(ProcessType.codex.color).frame(width: 6, height: 6)
                    Text("\(codexCount)")
                        .font(.system(size: 10, weight: .medium, design: .rounded))
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private func refreshSessions() async {
        isRefreshing = true
        defer { isRefreshing = false }
        await state.refreshSessions(for: pod.id)
    }
}
