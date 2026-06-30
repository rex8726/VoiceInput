# Multi-Provider Text Refinement + Short-Transcript Skip — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make text refinement use any of SiliconFlow / DeepSeek / Bailian with independent per-step config and per-provider Keychain keys, and skip refinement for very short transcripts.

**Architecture:** Add an `LLMProvider` value type carrying per-provider defaults. Replace the single STT+text `SiliconFlowClient` with a `TranscriptionClient` (STT, SiliconFlow only) and an OpenAI-compatible `ChatRefinementClient` driven by explicit config. Restructure `AppSettings` into nested `STTConfig`/`TextConfig` with backward-compatible decode. Keep `VoiceInputChecks` as the runnable regression gate.

**Tech Stack:** Swift 6.3, SwiftPM, AppKit, SwiftUI, Security Keychain, OpenAI-compatible HTTP chat APIs.

## Global Constraints

- Swift tools 6.3, `swiftLanguageModes: [.v6]`, macOS 13+. Verbatim from `Package.swift`.
- Test/regression gate is `swift run VoiceInputChecks` (no XCTest/Swift Testing available). Every task that can be tested adds checks there.
- Provider defaults (verified live 2026-06-30):
  - siliconflow → baseURL `https://api.siliconflow.cn/v1`, text model `Pro/zai-org/GLM-5.1`, STT yes.
  - deepseek → baseURL `https://api.deepseek.com/v1`, text model `deepseek-v4-flash`, STT no.
  - bailian → baseURL `https://dashscope.aliyuncs.com/compatible-mode/v1`, text model `qwen3.7-plus`, STT no.
- `enable_thinking` is sent ONLY for siliconflow; DeepSeek/Bailian get plain OpenAI payload.
- Fresh-install default text provider is `deepseek`; existing configs migrate to `siliconflow`.
- STT stays SiliconFlow; STT model default `FunAudioLLM/SenseVoiceSmall`.
- Keychain account format `apikey-<provider.rawValue>`, service `cn.local.voiceinput`; legacy account `siliconflow-api-key` migrates to `apikey-siliconflow`.
- Short-skip threshold default 8, range 0–50, `0` means always refine. Short-skip delivers raw text with `usedRawFallback: false`.
- Never write API keys to the repo or any file; keys live only in Keychain.

---

## File Structure

- Create `Sources/VoiceInputCore/LLMProvider.swift`: provider enum + per-provider defaults.
- Create `Sources/VoiceInputCore/APIClients.swift`: shared OpenAI-compatible helpers, `TranscriptionClient`, `ChatRefinementClient`, request/response models. Replaces `SiliconFlowClient.swift`.
- Delete `Sources/VoiceInputCore/SiliconFlowClient.swift` (content moves to `APIClients.swift`).
- Modify `Sources/VoiceInputCore/AppModels.swift`: add `RefinementPolicy`; restructure `AppSettings` (`sttConfig`, `textConfig`, `refineMinLength`) with migration.
- Modify `Sources/VoiceInputCore/Stores.swift`: `KeychainStore` provider-keyed API + legacy migration.
- Modify `Sources/VoiceInputCore/VoiceInputApp.swift`: build clients from configs + per-provider keys; short-skip in pipeline.
- Modify `Sources/VoiceInputCore/SettingsWindowController.swift`: provider picker, per-provider key fields, threshold stepper, test via `ChatRefinementClient`.
- Modify `Tests/VoiceInputChecks/main.swift`: new checks; update references to moved statics.
- Modify `README.md`: document multi-provider config + short-skip.

---

## Task 1: LLMProvider value type

**Files:**
- Create: `Sources/VoiceInputCore/LLMProvider.swift`
- Test: `Tests/VoiceInputChecks/main.swift`

**Interfaces:**
- Produces: `LLMProvider` enum (`.siliconflow`/`.deepseek`/`.bailian`) with `displayName`, `defaultBaseURL`, `defaultTextModel`, `supportsSTT: Bool`, `sendsEnableThinking: Bool`, `CaseIterable`, `Codable`, `Sendable`.

- [ ] **Step 1: Write failing checks** in `main.swift` (before `print("VoiceInputChecks passed")`):

```swift
check(LLMProvider.deepseek.defaultTextModel == "deepseek-v4-flash", "deepseek default model id")
check(LLMProvider.bailian.defaultTextModel == "qwen3.7-plus", "bailian default model id")
check(LLMProvider.siliconflow.defaultBaseURL == "https://api.siliconflow.cn/v1", "siliconflow base url")
check(LLMProvider.deepseek.defaultBaseURL == "https://api.deepseek.com/v1", "deepseek base url")
check(LLMProvider.bailian.defaultBaseURL == "https://dashscope.aliyuncs.com/compatible-mode/v1", "bailian base url")
check(LLMProvider.siliconflow.supportsSTT && !LLMProvider.deepseek.supportsSTT && !LLMProvider.bailian.supportsSTT, "only siliconflow supports STT")
check(LLMProvider.siliconflow.sendsEnableThinking && !LLMProvider.deepseek.sendsEnableThinking, "enable_thinking only for siliconflow")
```

- [ ] **Step 2: Run checks, verify fail**

Run: `swift run VoiceInputChecks`
Expected: compile error — `LLMProvider` undefined.

- [ ] **Step 3: Implement `LLMProvider.swift`**

```swift
import Foundation

public enum LLMProvider: String, Codable, CaseIterable, Sendable {
    case siliconflow
    case deepseek
    case bailian

    public var displayName: String {
        switch self {
        case .siliconflow: "硅基流动"
        case .deepseek: "DeepSeek"
        case .bailian: "阿里百炼"
        }
    }

    public var defaultBaseURL: String {
        switch self {
        case .siliconflow: "https://api.siliconflow.cn/v1"
        case .deepseek: "https://api.deepseek.com/v1"
        case .bailian: "https://dashscope.aliyuncs.com/compatible-mode/v1"
        }
    }

    public var defaultTextModel: String {
        switch self {
        case .siliconflow: "Pro/zai-org/GLM-5.1"
        case .deepseek: "deepseek-v4-flash"
        case .bailian: "qwen3.7-plus"
        }
    }

    public var supportsSTT: Bool {
        switch self {
        case .siliconflow: true
        case .deepseek, .bailian: false
        }
    }

    public var sendsEnableThinking: Bool { self == .siliconflow }
}
```

- [ ] **Step 4: Run checks, verify pass**

Run: `swift run VoiceInputChecks`
Expected: `VoiceInputChecks passed`.

- [ ] **Step 5: Commit**

```bash
git add Sources/VoiceInputCore/LLMProvider.swift Tests/VoiceInputChecks/main.swift
git commit -m "feat: add LLMProvider with per-provider defaults"
```

---

## Task 2: RefinementPolicy (short-skip decision)

**Files:**
- Modify: `Sources/VoiceInputCore/AppModels.swift`
- Test: `Tests/VoiceInputChecks/main.swift`

**Interfaces:**
- Produces: `RefinementPolicy.shouldRefine(_ text: String, minLength: Int) -> Bool`.

- [ ] **Step 1: Write failing checks**

```swift
check(RefinementPolicy.shouldRefine("好的", minLength: 8) == false, "short text skips refine")
check(RefinementPolicy.shouldRefine("这是一段足够长的语音输入文本", minLength: 8), "long text refines")
check(RefinementPolicy.shouldRefine("一二三四五六七八", minLength: 8), "at-threshold refines")
check(RefinementPolicy.shouldRefine("短", minLength: 0), "minLength 0 always refines")
```

- [ ] **Step 2: Run checks, verify fail** — `swift run VoiceInputChecks` → `RefinementPolicy` undefined.

- [ ] **Step 3: Implement** — append to `AppModels.swift`:

```swift
public enum RefinementPolicy {
    public static func shouldRefine(_ text: String, minLength: Int) -> Bool {
        guard minLength > 0 else { return true }
        return text.count >= minLength
    }
}
```

- [ ] **Step 4: Run checks, verify pass** — `swift run VoiceInputChecks` → passes.

- [ ] **Step 5: Commit**

```bash
git add Sources/VoiceInputCore/AppModels.swift Tests/VoiceInputChecks/main.swift
git commit -m "feat: add RefinementPolicy for short-transcript skip"
```

---

## Task 3: Provider-keyed Keychain (additive) + legacy migration

**Files:**
- Modify: `Sources/VoiceInputCore/Stores.swift`
- Test: `Tests/VoiceInputChecks/main.swift`

**Interfaces:**
- Produces: `KeychainStore.account(for: LLMProvider) -> String`, `readAPIKey(for:)`, `saveAPIKey(_:for:)`, `deleteAPIKey(for:)`. Existing `readAPIKey()`/`saveAPIKey(_:)`/`deleteAPIKey()` stay until Task 5.

- [ ] **Step 1: Write failing check**

```swift
check(KeychainStore.account(for: .deepseek) == "apikey-deepseek", "keychain account per provider")
check(KeychainStore.account(for: .siliconflow) == "apikey-siliconflow", "keychain account siliconflow")
```

- [ ] **Step 2: Run checks, verify fail** — `account(for:)` undefined.

- [ ] **Step 3: Implement** — in `KeychainStore`, refactor to private account-parameterized primitives and add provider API. Keep existing public no-arg methods delegating to the legacy account so other files still compile:

```swift
enum KeychainStore {
    private static let service = "cn.local.voiceinput"
    private static let legacyAccount = "siliconflow-api-key"

    static func account(for provider: LLMProvider) -> String { "apikey-\(provider.rawValue)" }

    // Provider-keyed API
    static func readAPIKey(for provider: LLMProvider) -> String {
        migrateLegacyIfNeeded()
        return read(account: account(for: provider))
    }
    static func saveAPIKey(_ value: String, for provider: LLMProvider) {
        if value.isEmpty { delete(account: account(for: provider)); return }
        write(value, account: account(for: provider))
    }
    static func deleteAPIKey(for provider: LLMProvider) { delete(account: account(for: provider)) }

    // Legacy no-arg API (removed in Task 5)
    static func readAPIKey() -> String { read(account: legacyAccount) }
    static func saveAPIKey(_ value: String) {
        if value.isEmpty { delete(account: legacyAccount); return }
        write(value, account: legacyAccount)
    }
    static func deleteAPIKey() { delete(account: legacyAccount) }

    private static func migrateLegacyIfNeeded() {
        let target = account(for: .siliconflow)
        guard read(account: target).isEmpty else { return }
        let legacy = read(account: legacyAccount)
        guard !legacy.isEmpty else { return }
        write(legacy, account: target)
    }

    private static func read(account: String) -> String {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data,
              let value = String(data: data, encoding: .utf8)
        else { return "" }
        return value
    }

    private static func write(_ value: String, account: String) {
        let data = Data(value.utf8)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        let status = SecItemUpdate(query as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if status == errSecItemNotFound {
            var addQuery = query
            addQuery[kSecValueData as String] = data
            SecItemAdd(addQuery as CFDictionary, nil)
        }
    }

    private static func delete(account: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(query as CFDictionary)
    }
}
```

- [ ] **Step 4: Run checks, verify pass** — `swift run VoiceInputChecks` → passes; build still green (legacy methods intact).

- [ ] **Step 5: Commit**

```bash
git add Sources/VoiceInputCore/Stores.swift Tests/VoiceInputChecks/main.swift
git commit -m "feat: provider-keyed Keychain with legacy migration"
```

---

## Task 4: Split API clients (explicit config)

**Files:**
- Create: `Sources/VoiceInputCore/APIClients.swift`
- Delete: `Sources/VoiceInputCore/SiliconFlowClient.swift`
- Modify: `Sources/VoiceInputCore/VoiceInputApp.swift`, `Sources/VoiceInputCore/SettingsWindowController.swift`, `Tests/VoiceInputChecks/main.swift`

**Interfaces:**
- Produces:
  - `OpenAICompatibleAPI.endpoint(baseURL:path:) -> URL?`, `.sanitizedErrorMessage(_:) -> String`, `.refinementSystemPrompt: String`, `.ClientError`.
  - `TranscriptionClient(baseURL:model:apiKey:timeout:)` with `transcribe(audioURL:) async throws -> String`.
  - `ChatRefinementClient(provider:baseURL:model:apiKey:timeout:)` with `refine(rawText:) async throws -> String`. Sends `enable_thinking` only when `provider.sendsEnableThinking`.
- Consumes: `LLMProvider` (Task 1).

- [ ] **Step 1: Update existing checks** to reference the new homes (the legacy `SiliconFlowClient.endpoint` / `.sanitizedErrorMessage` / `.refinementSystemPrompt` checks become `OpenAICompatibleAPI.*`). Add a payload check:

```swift
check(OpenAICompatibleAPI.endpoint(baseURL: "https://api.siliconflow.cn/v1/", path: "chat/completions")?.absoluteString == "https://api.siliconflow.cn/v1/chat/completions", "endpoint builder avoids duplicate slashes")
check(OpenAICompatibleAPI.sanitizedErrorMessage("Authorization: Bearer secret-token\n{\"message\":\"bad\"}").contains("secret-token") == false, "errors redact bearer tokens")
check(OpenAICompatibleAPI.refinementSystemPrompt.contains("结构化") && OpenAICompatibleAPI.refinementSystemPrompt.contains("编号列表"), "refinement prompt asks for structure")
check(try ChatRefinementClient.chatRequestJSON(provider: .siliconflow, model: "m", rawText: "x").contains("enable_thinking"), "siliconflow payload includes enable_thinking")
check(try ChatRefinementClient.chatRequestJSON(provider: .deepseek, model: "m", rawText: "x").contains("enable_thinking") == false, "deepseek payload omits enable_thinking")
```

Remove the old `SiliconFlowClient.*` versions of those three checks and the `AppSettings.defaults.textModel == ...` check (textModel moves in Task 5; re-added there).

- [ ] **Step 2: Run checks, verify fail** — `OpenAICompatibleAPI` / `ChatRefinementClient` undefined.

- [ ] **Step 3: Create `APIClients.swift`** with shared helpers, both clients, and a testable `chatRequestJSON` helper. Move `multipartBody`, `validate`, `endpoint`, `sanitizedErrorMessage`, `refinementSystemPrompt`, and the request/response models from `SiliconFlowClient.swift`.

```swift
import Foundation

public enum OpenAICompatibleAPI {
    public enum ClientError: Error, LocalizedError {
        case missingAPIKey, invalidBaseURL, emptyTranscription, emptyRefinement
        case badResponse(Int, String)

        public var errorDescription: String? {
            switch self {
            case .missingAPIKey: "请先在设置里填写 API Key。"
            case .invalidBaseURL: "API Base URL 无效。"
            case .emptyTranscription: "语音转文字结果为空。"
            case .emptyRefinement: "文本整理结果为空。"
            case let .badResponse(code, message): "API 请求失败：\(code) \(message)"
            }
        }
    }

    public static func endpoint(baseURL: String, path: String) -> URL? {
        let base = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let p = path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard !base.isEmpty, !p.isEmpty else { return nil }
        return URL(string: "\(base)/\(p)")
    }

    public static func sanitizedErrorMessage(_ message: String) -> String {
        let redacted = message.replacing(/Bearer\s+[A-Za-z0-9._\-]+/, with: "Bearer [REDACTED]")
        let singleLine = redacted
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\r", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return singleLine.count <= 200 ? singleLine : String(singleLine.prefix(200)) + "..."
    }

    static func validate(response: URLResponse, data: Data) throws {
        guard let http = response as? HTTPURLResponse else { return }
        guard (200..<300).contains(http.statusCode) else {
            throw ClientError.badResponse(http.statusCode, sanitizedErrorMessage(String(data: data, encoding: .utf8) ?? ""))
        }
    }

    public static let refinementSystemPrompt = """
    <copy the existing multi-line prompt verbatim from SiliconFlowClient.swift>
    """
}

public struct TranscriptionClient: Sendable {
    let baseURL: String
    let model: String
    let apiKey: String
    let timeout: Double

    public func transcribe(audioURL: URL) async throws -> String {
        guard !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw OpenAICompatibleAPI.ClientError.missingAPIKey }
        guard let url = OpenAICompatibleAPI.endpoint(baseURL: baseURL, path: "audio/transcriptions") else { throw OpenAICompatibleAPI.ClientError.invalidBaseURL }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = timeout
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        let boundary = "Boundary-\(UUID().uuidString)"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.httpBody = try multipartBody(audioURL: audioURL, model: model, boundary: boundary)
        let (data, response) = try await URLSession.shared.data(for: request)
        try OpenAICompatibleAPI.validate(response: response, data: data)
        let text = try JSONDecoder().decode(TranscriptionResponse.self, from: data).text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { throw OpenAICompatibleAPI.ClientError.emptyTranscription }
        return text
    }

    private func multipartBody(audioURL: URL, model: String, boundary: String) throws -> Data {
        // copy verbatim from SiliconFlowClient.multipartBody
    }
}

public struct ChatRefinementClient: Sendable {
    let provider: LLMProvider
    let baseURL: String
    let model: String
    let apiKey: String
    let timeout: Double

    public func refine(rawText: String) async throws -> String {
        guard !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw OpenAICompatibleAPI.ClientError.missingAPIKey }
        guard let url = OpenAICompatibleAPI.endpoint(baseURL: baseURL, path: "chat/completions") else { throw OpenAICompatibleAPI.ClientError.invalidBaseURL }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = timeout
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = Data(try Self.chatRequestJSON(provider: provider, model: model, rawText: rawText).utf8)
        let (data, response) = try await URLSession.shared.data(for: request)
        try OpenAICompatibleAPI.validate(response: response, data: data)
        let text = (try JSONDecoder().decode(ChatResponse.self, from: data).choices.first?.message.content ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { throw OpenAICompatibleAPI.ClientError.emptyRefinement }
        return text
    }

    static func chatRequestJSON(provider: LLMProvider, model: String, rawText: String) throws -> String {
        let payload = ChatRequest(
            model: model,
            messages: [
                .init(role: "system", content: OpenAICompatibleAPI.refinementSystemPrompt),
                .init(role: "user", content: rawText)
            ],
            temperature: 0.2,
            max_tokens: 2048,
            stream: false,
            enable_thinking: provider.sendsEnableThinking ? false : nil
        )
        return String(data: try JSONEncoder().encode(payload), encoding: .utf8) ?? ""
    }
}

private struct TranscriptionResponse: Decodable { let text: String }

private struct ChatRequest: Encodable {
    let model: String
    let messages: [ChatMessage]
    let temperature: Double
    let max_tokens: Int
    let stream: Bool
    let enable_thinking: Bool?   // nil → omitted by encoder
}

private struct ChatMessage: Codable { let role: String; let content: String }
private struct ChatResponse: Decodable {
    let choices: [Choice]
    struct Choice: Decodable { let message: ChatMessage }
}
```

Note: `enable_thinking: Bool?` with `nil` is omitted by `JSONEncoder` only if encoding skips nil — Swift's synthesized `Encodable` DOES encode `nil` optionals as absent by default, so `nil` → key omitted. Verified by the Step 1 checks.

- [ ] **Step 4: Delete `SiliconFlowClient.swift`** and update the two call sites to construct the new clients from the *current* flat settings (provider `.siliconflow` for now):

In `VoiceInputApp.swift` `stopRecording` task:
```swift
let stt = TranscriptionClient(baseURL: settingsStore.settings.baseURL, model: settingsStore.settings.sttModel, apiKey: KeychainStore.readAPIKey(), timeout: settingsStore.settings.timeoutSeconds)
let rawText = try await stt.transcribe(audioURL: audioURL)
...
let chat = ChatRefinementClient(provider: .siliconflow, baseURL: settingsStore.settings.baseURL, model: settingsStore.settings.textModel, apiKey: KeychainStore.readAPIKey(), timeout: settingsStore.settings.timeoutSeconds)
let refinedText = try await chat.refine(rawText: rawText)
```

In `SettingsWindowController.swift` `testTextModel`:
```swift
let client = ChatRefinementClient(provider: .siliconflow, baseURL: settingsStore.settings.baseURL, model: settingsStore.settings.textModel, apiKey: apiKey, timeout: settingsStore.settings.timeoutSeconds)
let result = try await client.refine(rawText: "嗯那个我想测试一下这个语音输入软件然后看看它能不能把口水词去掉")
```

(These flat fields still exist until Task 5.)

- [ ] **Step 5: Run checks + build, verify pass**

Run: `swift build && swift run VoiceInputChecks`
Expected: `VoiceInputChecks passed`.

- [ ] **Step 6: Commit**

```bash
git add -A
git commit -m "refactor: split STT and chat clients with explicit config"
```

---

## Task 5: AppSettings restructure + pipeline wiring + short-skip

**Files:**
- Modify: `Sources/VoiceInputCore/AppModels.swift`, `Sources/VoiceInputCore/VoiceInputApp.swift`, `Sources/VoiceInputCore/SettingsWindowController.swift`, `Sources/VoiceInputCore/Stores.swift`, `Tests/VoiceInputChecks/main.swift`

**Interfaces:**
- Produces: `AppSettings { sttConfig: STTConfig, textConfig: TextConfig, refineMinLength: Int, autoPaste, keepClipboardCopy, historyLimit, timeoutSeconds }`; `STTConfig { baseURL, model }`; `TextConfig { provider, baseURL, model }`.
- Consumes: `LLMProvider`, `RefinementPolicy`, `TranscriptionClient`, `ChatRefinementClient`, `KeychainStore.*(for:)`.

- [ ] **Step 1: Write failing migration checks** (replace the legacy-settings check block):

```swift
let legacyJSON = """
{ "baseURL": "https://api.siliconflow.cn/v1", "sttModel": "FunAudioLLM/SenseVoiceSmall", "textModel": "Pro/zai-org/GLM-5.1", "autoPaste": true, "keepClipboardCopy": true, "historyLimit": 10 }
""".data(using: .utf8)!
let migrated = try! JSONDecoder().decode(AppSettings.self, from: legacyJSON)
check(migrated.sttConfig.model == "FunAudioLLM/SenseVoiceSmall", "legacy sttModel migrates")
check(migrated.textConfig.model == "Pro/zai-org/GLM-5.1", "legacy textModel migrates")
check(migrated.textConfig.provider == .siliconflow, "legacy text provider is siliconflow")
check(migrated.sttConfig.baseURL == "https://api.siliconflow.cn/v1", "legacy baseURL migrates to stt")
check(migrated.textConfig.baseURL == "https://api.siliconflow.cn/v1", "legacy baseURL migrates to text")
check(migrated.refineMinLength == 8, "default refineMinLength")
check(AppSettings.defaults.textConfig.provider == .deepseek, "fresh install defaults to deepseek")
check(AppSettings.defaults.textConfig.model == "deepseek-v4-flash", "fresh install deepseek model")
check(AppSettings.defaults.sttConfig.model == "FunAudioLLM/SenseVoiceSmall", "fresh install stt model")
```

- [ ] **Step 2: Run checks, verify fail** — `sttConfig`/`textConfig` undefined.

- [ ] **Step 3: Restructure `AppSettings`** in `AppModels.swift`. Replace flat `baseURL`/`sttModel`/`textModel` with nested configs; keep the other fields:

```swift
public struct STTConfig: Codable, Equatable, Sendable {
    public var baseURL: String
    public var model: String
    public static let defaults = STTConfig(baseURL: LLMProvider.siliconflow.defaultBaseURL, model: "FunAudioLLM/SenseVoiceSmall")
}

public struct TextConfig: Codable, Equatable, Sendable {
    public var provider: LLMProvider
    public var baseURL: String
    public var model: String
    public static let defaults = TextConfig(provider: .deepseek, baseURL: LLMProvider.deepseek.defaultBaseURL, model: LLMProvider.deepseek.defaultTextModel)
}

public struct AppSettings: Codable, Equatable, Sendable {
    public var sttConfig: STTConfig
    public var textConfig: TextConfig
    public var autoPaste: Bool
    public var keepClipboardCopy: Bool
    public var historyLimit: Int
    public var timeoutSeconds: Double
    public var refineMinLength: Int

    public static let defaults = AppSettings(
        sttConfig: .defaults, textConfig: .defaults,
        autoPaste: true, keepClipboardCopy: true,
        historyLimit: 10, timeoutSeconds: 45, refineMinLength: 8
    )

    public init(sttConfig: STTConfig, textConfig: TextConfig, autoPaste: Bool, keepClipboardCopy: Bool, historyLimit: Int, timeoutSeconds: Double, refineMinLength: Int) {
        self.sttConfig = sttConfig; self.textConfig = textConfig
        self.autoPaste = autoPaste; self.keepClipboardCopy = keepClipboardCopy
        self.historyLimit = historyLimit; self.timeoutSeconds = timeoutSeconds
        self.refineMinLength = refineMinLength
    }

    enum CodingKeys: String, CodingKey {
        case sttConfig, textConfig, autoPaste, keepClipboardCopy, historyLimit, timeoutSeconds, refineMinLength
        // legacy
        case baseURL, sttModel, textModel
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let legacyBaseURL = try c.decodeIfPresent(String.self, forKey: .baseURL)
        if let stt = try c.decodeIfPresent(STTConfig.self, forKey: .sttConfig) {
            sttConfig = stt
        } else {
            sttConfig = STTConfig(
                baseURL: legacyBaseURL ?? STTConfig.defaults.baseURL,
                model: try c.decodeIfPresent(String.self, forKey: .sttModel) ?? STTConfig.defaults.model
            )
        }
        if let text = try c.decodeIfPresent(TextConfig.self, forKey: .textConfig) {
            textConfig = text
        } else {
            textConfig = TextConfig(
                provider: .siliconflow,
                baseURL: legacyBaseURL ?? LLMProvider.siliconflow.defaultBaseURL,
                model: try c.decodeIfPresent(String.self, forKey: .textModel) ?? LLMProvider.siliconflow.defaultTextModel
            )
        }
        autoPaste = try c.decodeIfPresent(Bool.self, forKey: .autoPaste) ?? Self.defaults.autoPaste
        keepClipboardCopy = try c.decodeIfPresent(Bool.self, forKey: .keepClipboardCopy) ?? Self.defaults.keepClipboardCopy
        historyLimit = try c.decodeIfPresent(Int.self, forKey: .historyLimit) ?? Self.defaults.historyLimit
        timeoutSeconds = try c.decodeIfPresent(Double.self, forKey: .timeoutSeconds) ?? Self.defaults.timeoutSeconds
        refineMinLength = try c.decodeIfPresent(Int.self, forKey: .refineMinLength) ?? Self.defaults.refineMinLength
    }
}
```

- [ ] **Step 4: Update `VoiceInputApp.swift`** pipeline to use configs + per-provider keys + short-skip:

```swift
let settings = settingsStore.settings
let stt = TranscriptionClient(baseURL: settings.sttConfig.baseURL, model: settings.sttConfig.model, apiKey: KeychainStore.readAPIKey(for: .siliconflow), timeout: settings.timeoutSeconds)
let rawText = try await stt.transcribe(audioURL: audioURL)
if Task.isCancelled { try? FileManager.default.removeItem(at: audioURL); return }

guard RefinementPolicy.shouldRefine(rawText, minLength: settings.refineMinLength) else {
    historyStore.add(rawText: rawText, refinedText: rawText, limit: settings.historyLimit)
    deliver(rawText, usedRawFallback: false)
    try? FileManager.default.removeItem(at: audioURL)
    return
}

let chat = ChatRefinementClient(provider: settings.textConfig.provider, baseURL: settings.textConfig.baseURL, model: settings.textConfig.model, apiKey: KeychainStore.readAPIKey(for: settings.textConfig.provider), timeout: settings.timeoutSeconds)
do {
    let refinedText = try await chat.refine(rawText: rawText)
    if Task.isCancelled { try? FileManager.default.removeItem(at: audioURL); return }
    historyStore.add(rawText: rawText, refinedText: refinedText, limit: settings.historyLimit)
    deliver(refinedText, usedRawFallback: false)
} catch {
    if Task.isCancelled { try? FileManager.default.removeItem(at: audioURL); return }
    historyStore.add(rawText: rawText, refinedText: rawText, limit: settings.historyLimit)
    deliver(rawText, usedRawFallback: true)
}
try? FileManager.default.removeItem(at: audioURL)
```

- [ ] **Step 5: Update `SettingsWindowController.swift` bindings** to the nested fields so the file compiles (full UI enrichment is Task 6). Minimum: bind STT/text base URL + model to `settingsStore.settings.sttConfig.*` / `textConfig.*`; build the test client from `textConfig` + `KeychainStore.readAPIKey(for: settingsStore.settings.textConfig.provider)`; key field reads/writes that provider's key.

- [ ] **Step 6: Remove legacy `KeychainStore` no-arg methods** (`readAPIKey()`, `saveAPIKey(_:)`, `deleteAPIKey()`) now that all call sites use the provider API. Re-add the `AppSettings.defaults` text-model check removed in Task 4, now as `textConfig.model`.

- [ ] **Step 7: Run checks + build, verify pass**

Run: `swift build && swift run VoiceInputChecks`
Expected: `VoiceInputChecks passed`.

- [ ] **Step 8: Commit**

```bash
git add -A
git commit -m "feat: per-step provider config and short-transcript skip"
```

---

## Task 6: Settings UI enrichment

**Files:**
- Modify: `Sources/VoiceInputCore/SettingsWindowController.swift`

**Interfaces:**
- Consumes: `LLMProvider.allCases`, `TextConfig`, `KeychainStore.*(for:)`, `ChatRefinementClient`.

- [ ] **Step 1: STT section** — show provider as `Text("硅基流动")` (fixed) + `TextField("语音转文字模型", text: $settingsStore.settings.sttConfig.model)` + `TextField("Base URL", text: $settingsStore.settings.sttConfig.baseURL)`.

- [ ] **Step 2: Text-refinement section** — provider Picker that autofills defaults on change:

```swift
Picker("文本服务商", selection: $settingsStore.settings.textConfig.provider) {
    ForEach(LLMProvider.allCases, id: \.self) { p in Text(p.displayName).tag(p) }
}
.onChange(of: settingsStore.settings.textConfig.provider) { _, newValue in
    settingsStore.settings.textConfig.baseURL = newValue.defaultBaseURL
    settingsStore.settings.textConfig.model = newValue.defaultTextModel
    apiKey = KeychainStore.readAPIKey(for: newValue)
}
TextField("Base URL", text: $settingsStore.settings.textConfig.baseURL)
TextField("文本整理模型", text: $settingsStore.settings.textConfig.model)
```

- [ ] **Step 3: API Key fields** — show the STT (siliconflow) key and the text-provider key; collapse to one field when `textConfig.provider == .siliconflow`. Each field keeps 粘贴/清空/保存 wired to `KeychainStore.*(for:)` for the right provider. `@State private var apiKey` holds the *text-provider* key; add `@State private var sttApiKey = KeychainStore.readAPIKey(for: .siliconflow)`.

- [ ] **Step 4: Threshold stepper** in the 输入 section:

```swift
Stepper("短于 \(settingsStore.settings.refineMinLength) 字直接发送原文（0 = 始终润色）", value: $settingsStore.settings.refineMinLength, in: 0...50)
```

- [ ] **Step 5: Test button** — already builds `ChatRefinementClient` from `textConfig` (Task 5 Step 5). Confirm it saves the text-provider key first: `KeychainStore.saveAPIKey(apiKey, for: settingsStore.settings.textConfig.provider)`.

- [ ] **Step 6: Build + checks** — `swift build && swift run VoiceInputChecks` → passes. Manually confirm settings window opens and provider switching autofills.

- [ ] **Step 7: Commit**

```bash
git add Sources/VoiceInputCore/SettingsWindowController.swift
git commit -m "feat: settings UI for provider selection and short-skip threshold"
```

---

## Task 7: README + live verification

**Files:**
- Modify: `README.md`

- [ ] **Step 1: Update README** — document the STT vs text split, the three text providers + their default models, per-provider API keys, and the short-skip threshold. Update default model lines (`Pro/zai-org/GLM-5.1` is now STT-side only; text default is DeepSeek `deepseek-v4-flash`).

- [ ] **Step 2: Build the app** — `./scripts/build_app.sh` then `open build/VoiceInput.app`.

- [ ] **Step 3: Live verification** (keys provided out-of-band, entered in Settings, never committed):
  - DeepSeek `deepseek-v4-flash`: record a long sentence → refined output pastes.
  - Bailian `qwen3.7-plus`: switch provider, record → refined output pastes.
  - Short utterance (< threshold) → raw text pastes with no refine latency.

- [ ] **Step 4: Commit**

```bash
git add README.md
git commit -m "docs: document multi-provider text refinement and short-skip"
```

---

## Self-Review

- **Spec coverage:** provider model (T1), config+migration (T5), Keychain per-provider+migration (T3), client split+enable_thinking (T4), short-skip (T2+T5), settings UI (T6), testing (each task), README+verify (T7). All spec sections mapped.
- **Type consistency:** `LLMProvider.sendsEnableThinking` used in T1/T4; `ChatRefinementClient.chatRequestJSON` tested in T4 and used in T4 `refine`; `KeychainStore.readAPIKey(for:)` introduced T3, used T5/T6; `sttConfig`/`textConfig` introduced T5, consumed T5/T6.
- **Placeholders:** the two "copy verbatim" notes (refinement prompt, multipartBody) point at exact existing source in `SiliconFlowClient.swift` — concrete, not vague.
