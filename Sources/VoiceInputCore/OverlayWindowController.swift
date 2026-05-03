import AppKit
import SwiftUI

@MainActor
final class OverlayWindowController {
    private var window: NSWindow?
    private let model = OverlayModel()

    init() {
        let view = OverlayView(model: model)
        let hosting = NSHostingController(rootView: view)
        let window = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 230, height: 56),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        window.contentViewController = hosting
        window.isOpaque = false
        window.backgroundColor = .clear
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
}

struct OverlayView: View {
    @ObservedObject var model: OverlayModel

    var body: some View {
        HStack(spacing: 12) {
            statusIcon
                .frame(width: 24, height: 24)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 14, weight: .semibold))
                Text(subtitle)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .frame(width: 230, height: 56)
        .background(.regularMaterial, in: Capsule())
        .overlay(Capsule().strokeBorder(Color.white.opacity(0.16)))
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

    private var subtitle: String {
        switch model.state {
        case .idle:
            "Fn 或 Option+1"
        case let .recording(startedAt):
            startedAt.formatted(.relative(presentation: .numeric))
        case .processing:
            "正在转写并润色"
        case let .done(message):
            message
        case let .failed(message):
            message
        }
    }

    @ViewBuilder
    private var statusIcon: some View {
        switch model.state {
        case .recording:
            ZStack {
                Circle().fill(Color.red.opacity(0.18))
                Circle().fill(Color.red).frame(width: 9, height: 9)
            }
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
