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
            OpenAICompatibleAPI.endpoint(baseURL: "https://api.siliconflow.cn/v1/", path: "chat/completions")?.absoluteString == "https://api.siliconflow.cn/v1/chat/completions",
            "endpoint builder should avoid duplicate slashes"
        )

        let fakeBearerHeader = "Authorization: Bearer " + "secret-token"
        check(
            OpenAICompatibleAPI.sanitizedErrorMessage(fakeBearerHeader + "\n{\"message\":\"bad\"}").contains("secret-token") == false,
            "API errors should not include bearer tokens"
        )

        check(
            OpenAICompatibleAPI.sanitizedErrorMessage(String(repeating: "x", count: 400)).count <= 220,
            "API errors should be capped for UI display"
        )

        let siliconflowPayload = try! ChatRefinementClient.chatRequestJSON(provider: .siliconflow, model: "m", rawText: "x")
        let deepseekPayload = try! ChatRefinementClient.chatRequestJSON(provider: .deepseek, model: "m", rawText: "x")
        let bailianPayload = try! ChatRefinementClient.chatRequestJSON(provider: .bailian, model: "m", rawText: "x")
        check(siliconflowPayload.contains("enable_thinking"), "siliconflow payload includes enable_thinking")
        check(deepseekPayload.contains("enable_thinking") == false, "deepseek payload omits enable_thinking")
        check(bailianPayload.contains("enable_thinking") == false, "bailian payload omits enable_thinking")

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
        let migrated = try! JSONDecoder().decode(AppSettings.self, from: legacySettingsJSON)
        check(migrated.sttConfig.model == "FunAudioLLM/SenseVoiceSmall", "legacy sttModel migrates")
        check(migrated.textConfig.model == "Qwen/Qwen3-8B", "legacy textModel migrates")
        check(migrated.textConfig.provider == .siliconflow, "legacy text provider is siliconflow")
        check(migrated.sttConfig.baseURL == "https://api.siliconflow.cn/v1", "legacy baseURL migrates to stt")
        check(migrated.textConfig.baseURL == "https://api.siliconflow.cn/v1", "legacy baseURL migrates to text")
        check(migrated.refineMinLength == 8, "default refineMinLength on migration")
        check(migrated.timeoutSeconds == AppSettings.defaults.timeoutSeconds, "legacy settings should migrate timeoutSeconds")
        check(AppSettings.defaults.timeoutSeconds >= 10, "default timeout should be long enough for network calls")
        check(AppSettings.defaults.textConfig.provider == .deepseek, "fresh install defaults to deepseek")
        check(AppSettings.defaults.textConfig.model == "deepseek-v4-flash", "fresh install deepseek model")
        check(AppSettings.defaults.sttConfig.model == "FunAudioLLM/SenseVoiceSmall", "fresh install stt model")
        check(RecordingDurationFormatter.text(elapsed: 0) == "已录 00:00", "recording duration should start at zero")
        check(RecordingDurationFormatter.text(elapsed: 75) == "已录 01:15", "recording duration should show minutes and seconds")
        check(AudioLevelNormalizer.normalizedPower(-80) == 0, "silent input should normalize to zero")
        check(AudioLevelNormalizer.normalizedPower(-20) > 0.6, "speech-level input should move waveform")

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

        check(
            OpenAICompatibleAPI.refinementSystemPrompt.contains("Markdown") && OpenAICompatibleAPI.refinementSystemPrompt.contains("纯文本"),
            "refinement prompt should forbid Markdown and require plain text"
        )
        check(
            OpenAICompatibleAPI.refinementSystemPrompt.contains("第一人称") && OpenAICompatibleAPI.refinementSystemPrompt.contains("不要有任何开场白"),
            "refinement prompt should keep the user's voice and ban assistant-style framing"
        )

        check(LLMProvider.deepseek.keychainAccount == "apikey-deepseek", "keychain account per provider")
        check(LLMProvider.siliconflow.keychainAccount == "apikey-siliconflow", "keychain account siliconflow")

        check(RefinementPolicy.shouldRefine("好的", minLength: 8) == false, "short text skips refine")
        check(RefinementPolicy.shouldRefine("这是一段足够长的语音输入文本", minLength: 8), "long text refines")
        check(RefinementPolicy.shouldRefine("一二三四五六七八", minLength: 8), "at-threshold refines")
        check(RefinementPolicy.shouldRefine("短", minLength: 0), "minLength 0 always refines")

        check(LLMProvider.deepseek.defaultTextModel == "deepseek-v4-flash", "deepseek default model id")
        check(LLMProvider.bailian.defaultTextModel == "qwen3.7-plus", "bailian default model id")
        check(LLMProvider.siliconflow.defaultBaseURL == "https://api.siliconflow.cn/v1", "siliconflow base url")
        check(LLMProvider.deepseek.defaultBaseURL == "https://api.deepseek.com/v1", "deepseek base url")
        check(LLMProvider.bailian.defaultBaseURL == "https://dashscope.aliyuncs.com/compatible-mode/v1", "bailian base url")
        check(LLMProvider.siliconflow.supportsSTT && !LLMProvider.deepseek.supportsSTT && !LLMProvider.bailian.supportsSTT, "only siliconflow supports STT")
        check(LLMProvider.siliconflow.sendsEnableThinking && !LLMProvider.deepseek.sendsEnableThinking, "enable_thinking only for siliconflow")

        print("VoiceInputChecks passed")
    }
}
