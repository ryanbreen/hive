import SwiftUI
import AppKit

struct BackupStatusIcon: View {
    let backupMode: BackupMode
    var size: CGFloat = 16

    private var badgeSize: CGFloat { size * 0.58 }
    private var centerDotSize: CGFloat { size * 0.3 }
    private var hexagonColor: Color {
        backupMode.isEnabled ? .green : .yellow
    }

    var body: some View {
        ZStack {
            Image(systemName: "hexagon.fill")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: size, height: size)
                .foregroundStyle(hexagonColor)

            if backupMode.isEnabled {
                Circle()
                    .fill(Color(red: 0.05, green: 0.42, blue: 0.14))
                    .frame(width: centerDotSize, height: centerDotSize)
            } else {
                ZStack {
                    Circle()
                        .fill(Color.yellow)
                    Image(systemName: "pause.fill")
                        .font(.system(size: size * 0.28, weight: .bold))
                        .foregroundStyle(Color.black)
                }
                .frame(width: badgeSize, height: badgeSize)
                .offset(x: size * 0.3, y: size * 0.3)
            }
        }
        .frame(width: size, height: size)
        .accessibilityLabel(backupMode.isEnabled ? "Hive backups enabled" : "Hive backups paused")
    }
}

struct BackupStatusMenuBarLabel: View {
    let backupMode: BackupMode
    var size: CGFloat = 18

    var body: some View {
        if let image = renderedImage {
            Image(nsImage: image)
                .renderingMode(.original)
        } else {
            BackupStatusIcon(backupMode: backupMode, size: size)
        }
    }

    private var renderedImage: NSImage? {
        let renderer = ImageRenderer(
            content: BackupStatusIcon(backupMode: backupMode, size: size)
        )
        renderer.scale = NSScreen.main?.backingScaleFactor ?? 2

        guard let image = renderer.nsImage else {
            return nil
        }

        image.isTemplate = false
        return image
    }
}
