import SwiftUI
import AppKit

extension UsageStatus {
    var color: Color {
        switch self {
        case .ok:      return .green
        case .caution: return .blue
        case .danger:  return .red
        }
    }
}

/// A clock-style ring that fills clockwise with consumption and colors by status.
struct RingGauge: View {
    let fraction: Double
    let status: UsageStatus
    let letter: String
    var size: CGFloat = 16
    var lineWidth: CGFloat = 3

    var body: some View {
        ZStack {
            Circle()
                .stroke(status.color.opacity(0.22), lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: max(0.001, min(1, fraction)))
                .stroke(status.color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
            Text(letter)
                .font(.system(size: size * 0.5, weight: .bold, design: .rounded))
                .foregroundStyle(status.color)
        }
        .frame(width: size, height: size)
    }
}

/// The menu-bar item: two colored gauges (Claude, ChatGPT) rendered to a
/// non-template NSImage so the colors survive in the status bar.
struct MenuBarLabel: View {
    @Bindable var store: UsageStore

    var body: some View {
        Image(nsImage: rendered)
            .renderingMode(.original)
    }

    @MainActor private var rendered: NSImage {
        let content = HStack(spacing: 4) {
            RingGauge(fraction: store.fraction(.claude), status: store.status(.claude),
                      letter: "C", size: 15, lineWidth: 2.5)
            RingGauge(fraction: store.fraction(.codex), status: store.status(.codex),
                      letter: "G", size: 15, lineWidth: 2.5)
        }
        .padding(.horizontal, 2)
        .padding(.vertical, 1)

        let renderer = ImageRenderer(content: content)
        renderer.scale = 2
        let image = renderer.nsImage ?? NSImage()
        image.isTemplate = false // keep our green/blue/red
        return image
    }
}
