import AppKit
import Carbon
import Foundation

@MainActor
public final class HotkeyManager {
    var onToggle: (() -> Void)?
    var onCancel: (() -> Void)?

    private var hotKeyRef: EventHotKeyRef?
    private var cancelHotKeyRef: EventHotKeyRef?
    private var eventHandlerRef: EventHandlerRef?
    private let hotKeyID = EventHotKeyID(signature: HotkeyManager.signature, id: 1)
    private let cancelHotKeyID = EventHotKeyID(signature: HotkeyManager.signature, id: 2)

    func start() {
        stop()

        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )

        let selfPointer = Unmanaged.passUnretained(self).toOpaque()
        InstallEventHandler(
            GetApplicationEventTarget(),
            { _, event, userData in
                guard let event, let userData else { return noErr }

                var receivedID = EventHotKeyID()
                let status = GetEventParameter(
                    event,
                    EventParamName(kEventParamDirectObject),
                    EventParamType(typeEventHotKeyID),
                    nil,
                    MemoryLayout<EventHotKeyID>.size,
                    nil,
                    &receivedID
                )
                guard status == noErr,
                      receivedID.signature == HotkeyManager.signature
                else { return noErr }

                let manager = Unmanaged<HotkeyManager>.fromOpaque(userData).takeUnretainedValue()
                let id = receivedID.id
                Task { @MainActor in
                    switch id {
                    case 1: manager.onToggle?()
                    case 2: manager.onCancel?()
                    default: break
                    }
                }
                return noErr
            },
            1,
            &eventType,
            selfPointer,
            &eventHandlerRef
        )

        var ref: EventHotKeyRef?
        let status = RegisterEventHotKey(
            UInt32(kVK_ANSI_1),
            UInt32(optionKey),
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &ref
        )
        if status == noErr {
            hotKeyRef = ref
        }
    }

    func stop() {
        if let hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
        }
        stopCancelHotkey()
        if let eventHandlerRef {
            RemoveEventHandler(eventHandlerRef)
        }
        hotKeyRef = nil
        eventHandlerRef = nil
    }

    /// Register a global Escape hotkey. Only active while recording/processing so Escape is not
    /// globally hijacked the rest of the time.
    func startCancelHotkey() {
        guard cancelHotKeyRef == nil else { return }
        var ref: EventHotKeyRef?
        let status = RegisterEventHotKey(
            UInt32(kVK_Escape),
            0,
            cancelHotKeyID,
            GetApplicationEventTarget(),
            0,
            &ref
        )
        if status == noErr {
            cancelHotKeyRef = ref
        }
    }

    func stopCancelHotkey() {
        if let cancelHotKeyRef {
            UnregisterEventHotKey(cancelHotKeyRef)
        }
        cancelHotKeyRef = nil
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

    private static let signature: OSType = {
        let scalars = Array("VIHK".unicodeScalars)
        return scalars.reduce(OSType(0)) { result, scalar in
            (result << 8) + OSType(scalar.value)
        }
    }()
}
