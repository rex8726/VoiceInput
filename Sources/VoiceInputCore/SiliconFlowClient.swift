import Foundation

public struct SiliconFlowClient: Sendable {
    enum ClientError: Error, LocalizedError {
        case missingAPIKey
        case invalidBaseURL
        case emptyTranscription
        case emptyRefinement
        case badResponse(Int, String)

        var errorDescription: String? {
            switch self {
            case .missingAPIKey:
                "请先在设置里填写 API Key。"
            case .invalidBaseURL:
                "API Base URL 无效。"
            case .emptyTranscription:
                "语音转文字结果为空。"
            case .emptyRefinement:
                "文本整理结果为空。"
            case let .badResponse(code, message):
                "API 请求失败：\(code) \(message)"
            }
        }
    }

    let settings: AppSettings
    let apiKey: String

    func transcribe(audioURL: URL) async throws -> String {
        guard !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ClientError.missingAPIKey
        }
        guard let url = Self.endpoint(baseURL: settings.baseURL, path: "audio/transcriptions") else {
            throw ClientError.invalidBaseURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = settings.timeoutSeconds
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")

        let boundary = "Boundary-\(UUID().uuidString)"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.httpBody = try multipartBody(audioURL: audioURL, model: settings.sttModel, boundary: boundary)

        let (data, response) = try await URLSession.shared.data(for: request)
        try validate(response: response, data: data)

        let decoded = try JSONDecoder().decode(TranscriptionResponse.self, from: data)
        let text = decoded.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { throw ClientError.emptyTranscription }
        return text
    }

    func refine(rawText: String) async throws -> String {
        guard !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ClientError.missingAPIKey
        }
        guard let url = Self.endpoint(baseURL: settings.baseURL, path: "chat/completions") else {
            throw ClientError.invalidBaseURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = settings.timeoutSeconds
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let payload = ChatRequest(
            model: settings.textModel,
            messages: [
                .init(role: "system", content: Self.refinementSystemPrompt),
                .init(role: "user", content: rawText)
            ],
            temperature: 0.2,
            max_tokens: 2048,
            stream: false,
            enable_thinking: false
        )
        request.httpBody = try JSONEncoder().encode(payload)

        let (data, response) = try await URLSession.shared.data(for: request)
        try validate(response: response, data: data)

        let decoded = try JSONDecoder().decode(ChatResponse.self, from: data)
        let text = decoded.choices.first?.message.content.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !text.isEmpty else { throw ClientError.emptyRefinement }
        return text
    }

    private func multipartBody(audioURL: URL, model: String, boundary: String) throws -> Data {
        var body = Data()
        func append(_ string: String) {
            body.append(Data(string.utf8))
        }

        append("--\(boundary)\r\n")
        append("Content-Disposition: form-data; name=\"model\"\r\n\r\n")
        append("\(model)\r\n")

        let audioData = try Data(contentsOf: audioURL)
        append("--\(boundary)\r\n")
        append("Content-Disposition: form-data; name=\"file\"; filename=\"recording.m4a\"\r\n")
        append("Content-Type: audio/mp4\r\n\r\n")
        body.append(audioData)
        append("\r\n--\(boundary)--\r\n")
        return body
    }

    private func validate(response: URLResponse, data: Data) throws {
        guard let http = response as? HTTPURLResponse else { return }
        guard (200..<300).contains(http.statusCode) else {
            let message = Self.sanitizedErrorMessage(String(data: data, encoding: .utf8) ?? "")
            throw ClientError.badResponse(http.statusCode, message)
        }
    }

    public static func endpoint(baseURL: String, path: String) -> URL? {
        let trimmedBase = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let trimmedPath = path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard !trimmedBase.isEmpty, !trimmedPath.isEmpty else { return nil }
        return URL(string: "\(trimmedBase)/\(trimmedPath)")
    }

    public static func sanitizedErrorMessage(_ message: String) -> String {
        let redacted = message.replacing(
            /Bearer\s+[A-Za-z0-9._\-]+/,
            with: "Bearer [REDACTED]"
        )
        let singleLine = redacted
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\r", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if singleLine.count <= 200 {
            return singleLine
        }
        return String(singleLine.prefix(200)) + "..."
    }

    public static let refinementSystemPrompt = """
    你是一个语音输入文本结构化整理器。你的任务是把语音转写文本整理成清晰、自然、可直接发送的中文文本。

    要求：
    1. 忠实保留用户原意。
    2. 不添加用户没有表达的新信息。
    3. 去除口水词、停顿词和无意义重复。
    4. 自动添加标点。
    5. 根据语义自然分段。
    6. 轻微调整语序，使文本更顺畅。
    7. 保留数字、人名、产品名、代码名和专有名词。
    8. 如果原文是中英混合，保留自然的中英混合表达。
    9. 如果用户表达了多个并列事项、步骤、原因、问题或需求，即使用户没有说“第一、第二、第三”，也要主动识别结构，并用编号列表或短段落结构化表达。
    10. 如果内容只是一个短句或简单消息，不要强行编号。
    11. 只输出整理后的文本，不解释。
    """
}

private struct TranscriptionResponse: Decodable {
    let text: String
}

private struct ChatRequest: Encodable {
    let model: String
    let messages: [ChatMessage]
    let temperature: Double
    let max_tokens: Int
    let stream: Bool
    let enable_thinking: Bool
}

private struct ChatMessage: Codable {
    let role: String
    let content: String
}

private struct ChatResponse: Decodable {
    let choices: [Choice]

    struct Choice: Decodable {
        let message: ChatMessage
    }
}
