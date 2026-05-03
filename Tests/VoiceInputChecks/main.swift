import AppKit
import VoiceInputCore

func check(_ condition: @autoclosure () -> Bool, _ message: String) {
    guard condition() else {
        fputs("FAIL: \(message)\n", stderr)
        Foundation.exit(1)
    }
}

@main
struct VoiceInputChecks {
    @MainActor
    static func main() {
        check(
            HotkeyManager.shouldToggleBackupShortcut(
                keyCode: 18,
                modifierFlags: [.option],
                isRepeat: true
            ) == false,
            "backup shortcut should ignore repeated keyDown events"
        )

        check(
            HotkeyManager.shouldToggleBackupShortcut(
                keyCode: 18,
                modifierFlags: [.option],
                isRepeat: false
            ),
            "backup shortcut should accept Option+1 once"
        )

        check(
            FocusedElementPastePolicy.canPaste(role: nil, subrole: nil, isValueSettable: false) == false,
            "unknown focused elements should not be considered pasteable"
        )

        check(
            FocusedElementPastePolicy.canPaste(role: "AXTextField", subrole: nil, isValueSettable: false),
            "AXTextField should be considered pasteable"
        )

        let store = HistoryStore(storageKey: "voiceInput.test.history.\(UUID().uuidString)")
        store.add(rawText: "1", refinedText: "一", limit: 2)
        store.add(rawText: "2", refinedText: "二", limit: 2)
        store.add(rawText: "3", refinedText: "三", limit: 2)
        check(store.items.map(\.refinedText) == ["三", "二"], "history should keep configured limit")

        check(
            SiliconFlowClient.endpoint(baseURL: "https://api.siliconflow.cn/v1/", path: "chat/completions")?.absoluteString == "https://api.siliconflow.cn/v1/chat/completions",
            "endpoint builder should avoid duplicate slashes"
        )

        check(
            SiliconFlowClient.sanitizedErrorMessage("Authorization: Bearer secret-token\n{\"message\":\"bad\"}").contains("secret-token") == false,
            "API errors should not include bearer tokens"
        )

        check(
            SiliconFlowClient.sanitizedErrorMessage(String(repeating: "x", count: 400)).count <= 220,
            "API errors should be capped for UI display"
        )

        let legacySettingsJSON = """
        {
          "baseURL": "https://api.siliconflow.cn/v1",
          "sttModel": "FunAudioLLM/SenseVoiceSmall",
          "textModel": "Qwen/Qwen3-8B",
          "autoPaste": true,
          "keepClipboardCopy": true,
          "historyLimit": 10
        }
        """.data(using: .utf8)!
        let migratedSettings = try! JSONDecoder().decode(AppSettings.self, from: legacySettingsJSON)
        check(migratedSettings.timeoutSeconds == AppSettings.defaults.timeoutSeconds, "legacy settings should migrate timeoutSeconds")
        check(AppSettings.defaults.timeoutSeconds >= 10, "default timeout should be long enough for network calls")

        check(
            DeliveryMessage.message(didPaste: true, usedRawFallback: false) == "已复制并粘贴",
            "successful paste should report copied and pasted"
        )
        check(
            DeliveryMessage.message(didPaste: false, usedRawFallback: true) == "整理失败，已复制原文",
            "raw fallback should report copied raw text"
        )

        let plistData = try! LoginItemService.launchAgentPlist(executablePath: "/Applications/VoiceInput.app/Contents/MacOS/VoiceInput")
        let plist = try! PropertyListSerialization.propertyList(from: plistData, format: nil) as! [String: Any]
        check(plist["Label"] as? String == "cn.local.voiceinput.loginitem", "login item plist should use stable label")
        check((plist["ProgramArguments"] as? [String])?.first == "/Applications/VoiceInput.app/Contents/MacOS/VoiceInput", "login item should launch current executable")
        check(plist["RunAtLoad"] as? Bool == true, "login item should run at load")

        print("VoiceInputChecks passed")
    }
}
