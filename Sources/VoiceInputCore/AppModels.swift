import Foundation

enum CaptureState: Equatable {
    case idle
    case recording(startedAt: Date)
    case processing
    case done(String)
    case failed(String)
}

public struct STTConfig: Codable, Equatable, Sendable {
    public var baseURL: String
    public var model: String

    public static let defaults = STTConfig(
        baseURL: LLMProvider.siliconflow.defaultBaseURL,
        model: "FunAudioLLM/SenseVoiceSmall"
    )

    public init(baseURL: String, model: String) {
        self.baseURL = baseURL
        self.model = model
    }
}

public struct TextConfig: Codable, Equatable, Sendable {
    public var provider: LLMProvider
    public var baseURL: String
    public var model: String

    public static let defaults = TextConfig(
        provider: .deepseek,
        baseURL: LLMProvider.deepseek.defaultBaseURL,
        model: LLMProvider.deepseek.defaultTextModel
    )

    public init(provider: LLMProvider, baseURL: String, model: String) {
        self.provider = provider
        self.baseURL = baseURL
        self.model = model
    }
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
        sttConfig: .defaults,
        textConfig: .defaults,
        autoPaste: true,
        keepClipboardCopy: true,
        historyLimit: 10,
        timeoutSeconds: 45,
        refineMinLength: 8
    )

    public init(
        sttConfig: STTConfig,
        textConfig: TextConfig,
        autoPaste: Bool,
        keepClipboardCopy: Bool,
        historyLimit: Int,
        timeoutSeconds: Double,
        refineMinLength: Int
    ) {
        self.sttConfig = sttConfig
        self.textConfig = textConfig
        self.autoPaste = autoPaste
        self.keepClipboardCopy = keepClipboardCopy
        self.historyLimit = historyLimit
        self.timeoutSeconds = timeoutSeconds
        self.refineMinLength = refineMinLength
    }

    enum CodingKeys: String, CodingKey {
        case sttConfig
        case textConfig
        case autoPaste
        case keepClipboardCopy
        case historyLimit
        case timeoutSeconds
        case refineMinLength
    }

    private enum LegacyCodingKeys: String, CodingKey {
        case baseURL
        case sttModel
        case textModel
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let legacy = try decoder.container(keyedBy: LegacyCodingKeys.self)
        let legacyBaseURL = try legacy.decodeIfPresent(String.self, forKey: .baseURL)

        if let stt = try c.decodeIfPresent(STTConfig.self, forKey: .sttConfig) {
            sttConfig = stt
        } else {
            sttConfig = STTConfig(
                baseURL: legacyBaseURL ?? STTConfig.defaults.baseURL,
                model: try legacy.decodeIfPresent(String.self, forKey: .sttModel) ?? STTConfig.defaults.model
            )
        }

        if let text = try c.decodeIfPresent(TextConfig.self, forKey: .textConfig) {
            textConfig = text
        } else {
            textConfig = TextConfig(
                provider: .siliconflow,
                baseURL: legacyBaseURL ?? LLMProvider.siliconflow.defaultBaseURL,
                model: try legacy.decodeIfPresent(String.self, forKey: .textModel) ?? LLMProvider.siliconflow.defaultTextModel
            )
        }

        autoPaste = try c.decodeIfPresent(Bool.self, forKey: .autoPaste) ?? Self.defaults.autoPaste
        keepClipboardCopy = try c.decodeIfPresent(Bool.self, forKey: .keepClipboardCopy) ?? Self.defaults.keepClipboardCopy
        historyLimit = try c.decodeIfPresent(Int.self, forKey: .historyLimit) ?? Self.defaults.historyLimit
        timeoutSeconds = try c.decodeIfPresent(Double.self, forKey: .timeoutSeconds) ?? Self.defaults.timeoutSeconds
        refineMinLength = try c.decodeIfPresent(Int.self, forKey: .refineMinLength) ?? Self.defaults.refineMinLength
    }
}

public struct HistoryItem: Codable, Identifiable, Equatable, Sendable {
    public let id: UUID
    public let createdAt: Date
    public let rawText: String
    public let refinedText: String
}

public enum DeliveryMessage {
    public static func message(didPaste: Bool, usedRawFallback: Bool) -> String {
        if usedRawFallback {
            return "整理失败，已复制原文"
        }
        return didPaste ? "已复制并粘贴" : "已复制到剪贴板"
    }
}

public enum RecordingDurationFormatter {
    public static func text(elapsed: TimeInterval) -> String {
        let totalSeconds = max(0, Int(elapsed.rounded(.down)))
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60
        return String(format: "已录 %02d:%02d", minutes, seconds)
    }
}

public enum RefinementPolicy {
    public static func shouldRefine(_ text: String, minLength: Int) -> Bool {
        guard minLength > 0 else { return true }
        return text.count >= minLength
    }
}

public enum AudioLevelNormalizer {
    public static func normalizedPower(_ averagePower: Float) -> Double {
        guard averagePower > -60 else { return 0 }
        let clamped = min(0, max(-60, averagePower))
        return Double((clamped + 60) / 60)
    }
}
