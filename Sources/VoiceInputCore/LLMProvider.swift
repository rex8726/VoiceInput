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

    /// Keychain account name for this provider's API key.
    public var keychainAccount: String { "apikey-\(rawValue)" }
}
