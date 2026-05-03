import AppKit
import AVFoundation
import ApplicationServices
import Foundation

public struct PermissionSnapshot: Equatable, Sendable {
    public let microphone: String
    public let accessibility: String
    public let inputMonitoring: String

    public var allRequiredGranted: Bool {
        microphone == "已允许" && accessibility == "已允许"
    }
}

@MainActor
enum PermissionService {
    static func snapshot() -> PermissionSnapshot {
        PermissionSnapshot(
            microphone: microphoneStatus(),
            accessibility: AXIsProcessTrusted() ? "已允许" : "未允许",
            inputMonitoring: "按键无响应时请开启"
        )
    }

    static func openPrivacySettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy")!
        NSWorkspace.shared.open(url)
    }

    private static func microphoneStatus() -> String {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            return "已允许"
        case .denied, .restricted:
            return "未允许"
        case .notDetermined:
            return "未询问"
        @unknown default:
            return "未知"
        }
    }
}
