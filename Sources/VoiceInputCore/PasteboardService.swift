import AppKit
import ApplicationServices
import Foundation

@MainActor
enum PasteboardService {
    static func copy(_ text: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }

    /// Current clipboard string, used to snapshot and later restore the user's clipboard
    /// around an auto-paste. Returns nil when the clipboard holds no plain text.
    static func currentString() -> String? {
        NSPasteboard.general.string(forType: .string)
    }

    static func paste() {
        let source = CGEventSource(stateID: .combinedSessionState)
        let keyDown = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: true)
        let keyUp = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: false)
        keyDown?.flags = .maskCommand
        keyUp?.flags = .maskCommand
        keyDown?.post(tap: .cghidEventTap)
        keyUp?.post(tap: .cghidEventTap)
    }

    static func requestAccessibilityIfNeeded() -> Bool {
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }

    /// Whether the currently focused element accepts a paste.
    /// - `true`: positively editable, safe to paste.
    /// - `false`: positively non-editable (e.g. focus is on Finder, a button), skip paste.
    /// - `nil`: could not determine (common for web inputs whose AX info is opaque). Callers
    ///   should treat this as "maybe" and still paste, to preserve browser/Electron compatibility.
    static func focusedElementPasteDecision() -> Bool? {
        let system = AXUIElementCreateSystemWide()
        var focusedRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(system, "AXFocusedUIElement" as CFString, &focusedRef) == .success,
              let focused = focusedRef
        else { return nil }

        let element = focused as! AXUIElement
        let role = stringAttribute("AXRole", from: element)
        let subrole = stringAttribute("AXSubrole", from: element)
        var settable = DarwinBoolean(false)
        let settableResult = AXUIElementIsAttributeSettable(element, "AXValue" as CFString, &settable)

        return FocusedElementPastePolicy.canPaste(
            role: role,
            subrole: subrole,
            isValueSettable: settableResult == .success && settable.boolValue
        )
    }

    /// Wait until no keyboard modifier keys are physically held, up to `timeout`.
    /// The toggle hotkey is Option+1, so when recording stops the Option key may still be down;
    /// posting Cmd+V while it is held can merge into Cmd+Option+V in the target app.
    static func waitForModifiersCleared(timeout: TimeInterval = 0.4) async {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if NSEvent.modifierFlags.intersection(.deviceIndependentFlagsMask).isEmpty { return }
            try? await Task.sleep(nanoseconds: 20_000_000)
        }
    }

    private static func stringAttribute(_ name: String, from element: AXUIElement) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success else { return nil }
        return value as? String
    }
}

public enum FocusedElementPastePolicy {
    public static func canPaste(role: String?, subrole: String?, isValueSettable: Bool) -> Bool {
        if isValueSettable { return true }

        let editableRoles: Set<String> = [
            "AXTextArea",
            "AXTextField",
            "AXComboBox",
            "AXSearchField"
        ]

        if let role, editableRoles.contains(role) {
            return true
        }

        let editableSubroles: Set<String> = [
            "AXSecureTextField"
        ]

        if let subrole, editableSubroles.contains(subrole) {
            return true
        }

        return false
    }
}
