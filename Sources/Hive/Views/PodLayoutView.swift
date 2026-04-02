import SwiftUI

struct PodLayoutView: View {
    let pod: Pod

    private var leftCount: Int { pod.leftPanes.count }

    var body: some View {
        HStack(spacing: 1.5) {
            VStack(spacing: 1.5) {
                ForEach(pod.leftPanes) { pane in
                    paneCell(pane)
                }
            }
            .frame(maxWidth: .infinity)

            if let middle = pod.middlePane {
                paneCell(middle)
                    .frame(maxWidth: .infinity)
            }

            VStack(spacing: 1.5) {
                ForEach(pod.rightPanes) { pane in
                    paneCell(pane)
                }
            }
            .frame(maxWidth: .infinity)
        }
        .clipShape(RoundedRectangle(cornerRadius: 4))
    }

    @ViewBuilder
    private func paneCell(_ pane: PaneConfig) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 2)
                .fill(pane.processType.color.opacity(0.2))
                .overlay(
                    RoundedRectangle(cornerRadius: 2)
                        .strokeBorder(pane.processType.color.opacity(0.4), lineWidth: 0.5)
                )

            Text(pane.processType.shortLabel)
                .font(.system(size: 7, weight: .semibold, design: .rounded))
                .foregroundStyle(pane.processType.color)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

extension ProcessType {
    var color: Color {
        switch self {
        case .claude: return .indigo
        case .codex: return .green
        case .lazygit: return .orange
        case .shell: return .gray
        case .custom: return .cyan
        }
    }

    var shortLabel: String {
        switch self {
        case .claude: return "C"
        case .codex: return "X"
        case .lazygit: return "G"
        case .shell: return ">"
        case .custom: return "*"
        }
    }
}
