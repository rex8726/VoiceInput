import AppKit
import Carbon
import Foundation

@MainActor
public final class HotkeyManager {
    var onToggle: (() -> Void)?

    private var globalKeyMonitor: Any?
    private var localKeyMonitor: Any?

    func start() {
        globalKeyMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            Task { @MainActor in self?.handleKey(event) }
        }
        localKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            self?.handleKey(event)
            return event
        }
    }

    func stop() {
        [globalKeyMonitor, localKeyMonitor].forEach { monitor in
            if let monitor { NSEvent.removeMonitor(monitor) }
        }
        globalKeyMonitor = nil
        localKeyMonitor = nil
    }

    private func handleKey(_ event: NSEvent) {
        if Self.shouldToggleBackupShortcut(
            keyCode: event.keyCode,
            modifierFlags: event.modifierFlags,
            isRepeat: event.isARepeat
        ) {
            onToggle?()
        }
    }

    public static func shouldToggleBackupShortcut(
        keyCode: UInt16,
        modifierFlags: NSEvent.ModifierFlags,
        isRepeat: Bool
    ) -> Bool {
        guard !isRepeat else { return false }
        let flags = modifierFlags.intersection(.deviceIndependentFlagsMask)
        return flags.contains(.option) && keyCode == UInt16(kVK_ANSI_1)
    }
}
