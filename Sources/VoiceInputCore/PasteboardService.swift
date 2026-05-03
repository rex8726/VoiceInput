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

    static func focusedElementAcceptsPaste() -> Bool {
        let system = AXUIElementCreateSystemWide()
        var focusedRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(system, "AXFocusedUIElement" as CFString, &focusedRef) == .success,
              let focused = focusedRef
        else { return false }

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
