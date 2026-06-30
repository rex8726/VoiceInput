# Multi-Provider Text Refinement + Short-Transcript Skip — Design

**Status:** Approved design, pending spec review.

**Goal:** Let the text-refinement step use any of several OpenAI-compatible
providers (SiliconFlow, DeepSeek, Alibaba Bailian) with independent per-step
configuration, and skip refinement entirely for very short transcripts to cut
latency. Speech-to-text (STT) stays on SiliconFlow for now, with the provider
abstraction shaped so Bailian ASR can be added later.

**Motivation:** SiliconFlow's GLM-5.1 refinement model is slow. DeepSeek and
Bailian offer faster chat models. DeepSeek has no transcription endpoint, so STT
and text refinement must be configured independently.

**Tech Stack:** Swift 6.3, SwiftPM, AppKit, SwiftUI, Security Keychain,
OpenAI-compatible HTTP chat APIs. Regression gate: `swift run VoiceInputChecks`
(no XCTest/Swift Testing in this Command Line Tools environment).

---

## Decisions (locked)

- STT this round: SiliconFlow only; architecture reserves room for Bailian ASR.
- Text refinement: SiliconFlow / DeepSeek / Bailian, independently selectable.
- Keychain: store one API key **per provider** (`apikey-<provider>`), reused
  across steps that share a provider.
- Default text provider stays SiliconFlow (no behavior change on upgrade).
- Short-transcript skip is normal output, not a failure fallback.

## Provider Model

New `LLMProvider` enum, `String`-backed and `Codable`, cases `siliconflow`,
`deepseek`, `bailian`. Each case exposes:

| Provider    | displayName | defaultBaseURL                                      | defaultTextModel    | supportsSTT | supportsText |
|-------------|-------------|-----------------------------------------------------|---------------------|-------------|--------------|
| siliconflow | 硅基流动     | `https://api.siliconflow.cn/v1`                     | `Pro/zai-org/GLM-5.1` | yes       | yes          |
| deepseek    | DeepSeek    | `https://api.deepseek.com/v1`                       | `deepseek-chat`     | no          | yes          |
| bailian     | 阿里百炼     | `https://dashscope.aliyuncs.com/compatible-mode/v1` | `qwen-plus`         | no          | yes          |

Per-provider request quirk: `enable_thinking` is sent **only** for
`siliconflow`. DeepSeek and Bailian receive a standard OpenAI chat payload with
that field omitted, to avoid rejection.

## Configuration & Migration

`AppSettings` gains two nested configs and a refinement threshold; the flat
`baseURL` / `sttModel` / `textModel` fields are replaced:

```
AppSettings {
  sttConfig:  STTConfig  { baseURL, model }              // provider fixed to siliconflow for now
  textConfig: TextConfig { provider, baseURL, model }
  refineMinLength: Int                                    // 0 = always refine; default 8
  autoPaste, keepClipboardCopy, historyLimit, timeoutSeconds   // unchanged
}
```

`STTConfig` / `TextConfig` are `Codable` structs with their own defaults.

**Migration (backward-compatible decode):** `AppSettings.init(from:)` keeps using
`decodeIfPresent`. When the new nested keys are absent, it reads the legacy
flat keys:
- `sttConfig.baseURL` ← legacy `baseURL` (or siliconflow default)
- `sttConfig.model` ← legacy `sttModel`
- `textConfig.provider` ← `.siliconflow`
- `textConfig.baseURL` ← legacy `baseURL`
- `textConfig.model` ← legacy `textModel`
- `refineMinLength` ← default 8

**Keychain migration:** on first read, if no `apikey-siliconflow` entry exists
but the legacy `siliconflow-api-key` entry does, copy it to
`apikey-siliconflow`. Legacy entry left untouched (harmless).

## Keychain API

`KeychainStore` becomes provider-keyed:
- `readAPIKey(for: LLMProvider) -> String`
- `saveAPIKey(_:for:)` — empty value deletes the entry
- `deleteAPIKey(for:)`
- account string: `apikey-<provider.rawValue>`; service unchanged
  (`cn.local.voiceinput`).
- One-time legacy migration as above, triggered lazily on first siliconflow read.

## Client Split

`SiliconFlowClient` splits by responsibility; shared helpers move to a common
location:

- `TranscriptionClient` — STT. Holds `baseURL`, `model`, `apiKey`, `timeout`.
  Keeps the existing multipart `POST /audio/transcriptions` logic verbatim.
- `ChatRefinementClient` — OpenAI-compatible refinement. Holds `provider`,
  `baseURL`, `model`, `apiKey`, `timeout`. `refine(rawText:)` builds the chat
  payload, including `enable_thinking` only when `provider == .siliconflow`.
- Shared (static, reused, keep existing unit tests): `endpoint(baseURL:path:)`,
  `sanitizedErrorMessage(_:)`, response validation, and `refinementSystemPrompt`.

## Refinement Policy (短句跳过)

New pure helper:

```
enum RefinementPolicy {
    static func shouldRefine(_ text: String, minLength: Int) -> Bool {
        minLength <= 0 ? true : text.count >= minLength
    }
}
```

Pipeline change in `AppDelegate` processing task: after STT yields `rawText`,
if `RefinementPolicy.shouldRefine(rawText, minLength: settings.refineMinLength)`
is false, deliver `rawText` directly with `usedRawFallback: false` (normal
output). Otherwise refine as today, with the existing refine-failure fallback
(deliver raw with `usedRawFallback: true`) intact.

## Settings UI

- **语音转文字** section: provider shown as 硅基流动 (disabled for now) + model field.
- **文本润色** section: provider `Picker` (硅基流动 / DeepSeek / 阿里百炼). On
  change, fill that provider's default baseURL + model (still editable). baseURL
  + model fields below.
- **API Key** section: show a key field per provider currently in use (STT
  provider and text provider; one field if they share a provider). Reuse the
  existing 粘贴 / 清空 / 保存 / 测试 buttons. Test uses `ChatRefinementClient`
  for the selected text provider.
- New **Stepper**: "短于 N 字直接发送原文（0 = 始终润色）", default 8, range 0–50.

## Error Handling

- Per-provider key missing → existing `missingAPIKey` error, surfaced in overlay.
- Non-2xx responses → existing `badResponse` with `sanitizedErrorMessage`
  (bearer-token redaction retained for all providers).
- Short-skip path performs no network call and cannot fail at the refine step.
- Esc cancellation and clipboard/paste behavior from prior work are unchanged.

## Testing (VoiceInputChecks)

Add/keep pure-function checks:
- `LLMProvider` defaults: baseURL, defaultTextModel, supportsSTT for each case.
- `enable_thinking` inclusion: present for siliconflow payload, absent for
  deepseek/bailian (assert on encoded JSON).
- `RefinementPolicy.shouldRefine`: below/at/above threshold, and `minLength == 0`
  always true.
- Settings migration: legacy flat JSON decodes into nested configs with correct
  values and default `refineMinLength`.
- Retain existing endpoint-builder and `sanitizedErrorMessage` checks against
  their new (shared) home.

## Out of Scope

- Bailian ASR (STT) integration.
- Streaming refinement output.
- Changing the default text provider away from SiliconFlow.
