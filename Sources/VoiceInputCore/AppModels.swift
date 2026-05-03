import Foundation

enum CaptureState: Equatable {
    case idle
    case recording(startedAt: Date)
    case processing
    case done(String)
    case failed(String)
}

public struct AppSettings: Codable, Equatable, Sendable {
    public var baseURL: String
    public var sttModel: String
    public var textModel: String
    public var autoPaste: Bool
    public var keepClipboardCopy: Bool
    public var historyLimit: Int
    public var timeoutSeconds: Double

    public static let defaults = AppSettings(
        baseURL: "https://api.siliconflow.cn/v1",
        sttModel: "FunAudioLLM/SenseVoiceSmall",
        textModel: "Pro/zai-org/GLM-5.1",
        autoPaste: true,
        keepClipboardCopy: true,
        historyLimit: 10,
        timeoutSeconds: 45
    )

    public init(
        baseURL: String,
        sttModel: String,
        textModel: String,
        autoPaste: Bool,
        keepClipboardCopy: Bool,
        historyLimit: Int,
        timeoutSeconds: Double
    ) {
        self.baseURL = baseURL
        self.sttModel = sttModel
        self.textModel = textModel
        self.autoPaste = autoPaste
        self.keepClipboardCopy = keepClipboardCopy
        self.historyLimit = historyLimit
        self.timeoutSeconds = timeoutSeconds
    }

    enum CodingKeys: String, CodingKey {
        case baseURL
        case sttModel
        case textModel
        case autoPaste
        case keepClipboardCopy
        case historyLimit
        case timeoutSeconds
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        baseURL = try container.decodeIfPresent(String.self, forKey: .baseURL) ?? Self.defaults.baseURL
        sttModel = try container.decodeIfPresent(String.self, forKey: .sttModel) ?? Self.defaults.sttModel
        textModel = try container.decodeIfPresent(String.self, forKey: .textModel) ?? Self.defaults.textModel
        autoPaste = try container.decodeIfPresent(Bool.self, forKey: .autoPaste) ?? Self.defaults.autoPaste
        keepClipboardCopy = try container.decodeIfPresent(Bool.self, forKey: .keepClipboardCopy) ?? Self.defaults.keepClipboardCopy
        historyLimit = try container.decodeIfPresent(Int.self, forKey: .historyLimit) ?? Self.defaults.historyLimit
        timeoutSeconds = try container.decodeIfPresent(Double.self, forKey: .timeoutSeconds) ?? Self.defaults.timeoutSeconds
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

public enum AudioLevelNormalizer {
    public static func normalizedPower(_ averagePower: Float) -> Double {
        guard averagePower > -60 else { return 0 }
        let clamped = min(0, max(-60, averagePower))
        return Double((clamped + 60) / 60)
    }
}
