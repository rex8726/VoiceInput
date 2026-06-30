import AppKit
import SwiftUI

@MainActor
final class OverlayWindowController {
    private var window: NSWindow?
    private let model = OverlayModel()

    init() {
        let view = OverlayView(model: model)
        let hosting = NSHostingController(rootView: view)
        hosting.view.wantsLayer = true
        hosting.view.layer?.backgroundColor = NSColor.clear.cgColor
        let window = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 300, height: 72),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        window.contentViewController = hosting
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        window.level = .floating
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        window.ignoresMouseEvents = true
        window.alphaValue = 0
        self.window = window
    }

    func update(_ state: CaptureState) {
        model.state = state
        switch state {
        case .idle:
            hide()
        case .recording, .processing:
            show()
        case .done, .failed:
            show()
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) { [weak self] in
                self?.hide()
            }
        }
    }

    func updateAudioLevel(_ level: Double) {
        model.audioLevel = level
    }

    private func show() {
        guard let window else { return }
        position(window)
        window.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.16
            window.animator().alphaValue = 1
        }
    }

    private func hide() {
        guard let window else { return }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.16
            window.animator().alphaValue = 0
        } completionHandler: {
            Task { @MainActor in
                window.orderOut(nil)
            }
        }
    }

    private func position(_ window: NSWindow) {
        let screen = NSScreen.main ?? NSScreen.screens.first
        guard let frame = screen?.visibleFrame else { return }
        let size = window.frame.size
        let origin = NSPoint(
            x: frame.midX - size.width / 2,
            y: frame.minY + 56
        )
        window.setFrameOrigin(origin)
    }
}

@MainActor
final class OverlayModel: ObservableObject {
    @Published var state: CaptureState = .idle
    @Published var audioLevel: Double = 0
}

struct OverlayView: View {
    @ObservedObject var model: OverlayModel

    var body: some View {
        HStack(spacing: 12) {
            statusIcon
                .frame(width: 86, height: 36)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 14, weight: .semibold))
                subtitleView
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .frame(width: 300, height: 72)
        .background(
            Capsule()
                .fill(.regularMaterial)
        )
        .overlay(Capsule().strokeBorder(Color.white.opacity(0.18)))
        .clipShape(Capsule())
        .shadow(color: .black.opacity(0.18), radius: 18, y: 8)
    }

    private var title: String {
        switch model.state {
        case .idle:
            "准备就绪"
        case .recording:
            "正在听"
        case .processing:
            "整理中"
        case .done:
            "已输入"
        case .failed:
            "处理失败"
        }
    }

    @ViewBuilder
    private var subtitleView: some View {
        switch model.state {
        case .idle:
            Text("Option+1")
        case let .recording(startedAt):
            TimelineView(.periodic(from: .now, by: 0.25)) { timeline in
                Text(RecordingDurationFormatter.text(elapsed: timeline.date.timeIntervalSince(startedAt)) + " · Esc 取消")
            }
        case .processing:
            Text("正在转写并润色 · Esc 取消")
        case let .done(message):
            Text(message)
        case let .failed(message):
            Text(message)
        }
    }

    @ViewBuilder
    private var statusIcon: some View {
        switch model.state {
        case .recording:
            RecordingWaveView(level: model.audioLevel)
        case .processing:
            ProgressView().controlSize(.small)
        case .done:
            Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
        case .failed:
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
        case .idle:
            Image(systemName: "mic.fill").foregroundStyle(.secondary)
        }
    }
}

struct RecordingWaveView: View {
    let level: Double

    var body: some View {
        TimelineView(.animation) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate
            HStack(spacing: 7) {
                ZStack {
                    Circle()
                        .fill(Color.red.opacity(0.18 + 0.12 * pulse(t)))
                        .frame(width: 30 + 8 * pulse(t), height: 30 + 8 * pulse(t))
                    Circle()
                        .fill(Color.red)
                        .frame(width: 12, height: 12)
                }

                HStack(alignment: .center, spacing: 3) {
                    ForEach(0..<8, id: \.self) { index in
                        Capsule()
                            .fill(Color.red.opacity(0.82))
                            .frame(width: 4, height: barHeight(t, index: index, level: level))
                    }
                }
                .frame(width: 44, height: 32)
            }
        }
    }

    private func pulse(_ t: TimeInterval) -> Double {
        (sin(t * 4.2) + 1) / 2
    }

    private func barHeight(_ t: TimeInterval, index: Int, level: Double) -> CGFloat {
        guard level > 0.03 else { return 5 }
        let phase = t * 6.5 + Double(index) * 0.72
        return CGFloat(5 + 24 * level * ((sin(phase) + 1) / 2))
    }
}
