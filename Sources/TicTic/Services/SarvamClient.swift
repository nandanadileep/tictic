import Foundation

struct SarvamClient {
    var session: URLSession = .shared
    var endpoint = URL(string: "https://api.sarvam.ai/speech-to-text")!
    var chatEndpoint = URL(string: "https://api.sarvam.ai/v1/chat/completions")!

    func transcribe(
        audioURL: URL,
        apiKey: String,
        language: IndicLanguage,
        mode: TranscriptionMode
    ) async throws -> SarvamTranscript {
        let audioData = try Data(contentsOf: audioURL)
        let boundary = "TicTic-\(UUID().uuidString)"
        let body = Self.multipartBody(
            audioData: audioData,
            filename: audioURL.lastPathComponent,
            mimeType: Self.mimeType(for: audioURL),
            language: language.rawValue,
            mode: mode.rawValue,
            boundary: boundary
        )
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = 60
        request.setValue(apiKey, forHTTPHeaderField: "api-subscription-key")
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.httpBody = body

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw SarvamError.invalidResponse }
        guard (200..<300).contains(http.statusCode) else {
            let serverMessage = Self.extractErrorMessage(from: data)
            throw SarvamError.http(status: http.statusCode, message: serverMessage)
        }
        do {
            return try JSONDecoder().decode(SarvamTranscript.self, from: data)
        } catch {
            throw SarvamError.decoding(error.localizedDescription)
        }
    }

    func polish(
        _ text: String,
        apiKey: String,
        style: WritingStyle,
        applicationName: String?,
        vocabulary: String
    ) async throws -> String {
        let context = applicationName ?? "a general writing app"
        let styleInstruction: String
        switch style {
        case .automatic: styleInstruction = "Infer an appropriate tone and formatting for \(context)."
        case .clean: styleInstruction = "Use clean, natural phrasing with correct punctuation."
        case .concise: styleInstruction = "Be concise and remove repetition without losing information."
        case .professional: styleInstruction = "Use a polished, professional tone."
        case .casual: styleInstruction = "Use a relaxed, friendly, natural tone."
        }
        let vocabularyInstruction = vocabulary.isEmpty ? "" : " Preserve these preferred terms exactly: \(vocabulary)."
        let system = """
        You format voice dictation. Return only the final text, with no explanation or quotation marks. \
        Preserve every fact, name, number, intent, and the original language/script. Never answer the content. \
        Apply spoken formatting instructions such as new paragraph, bullet list, comma, or question mark. \
        Fix obvious speech-recognition punctuation and remove accidental filler words. \(styleInstruction)\(vocabularyInstruction)
        """
        let payload = ChatRequest(
            model: "sarvam-105b",
            messages: [
                .init(role: "system", content: system),
                .init(role: "user", content: text)
            ],
            temperature: 0.1,
            maxTokens: max(256, min(2_048, text.count * 2))
        )
        var request = URLRequest(url: chatEndpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = 60
        request.setValue(apiKey, forHTTPHeaderField: "api-subscription-key")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(payload)

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw SarvamError.invalidResponse }
        guard (200..<300).contains(http.statusCode) else {
            throw SarvamError.http(status: http.statusCode, message: Self.extractErrorMessage(from: data))
        }
        do {
            let decoded = try JSONDecoder().decode(ChatResponse.self, from: data)
            guard let content = decoded.choices.first?.message.content.trimmingCharacters(in: .whitespacesAndNewlines),
                  !content.isEmpty else { return text }
            return content
        } catch {
            throw SarvamError.decoding(error.localizedDescription)
        }
    }

    static func multipartBody(
        audioData: Data,
        filename: String,
        mimeType: String = "audio/mp4",
        language: String,
        mode: String,
        boundary: String
    ) -> Data {
        var body = Data()
        func append(_ string: String) { body.append(Data(string.utf8)) }
        func field(_ name: String, _ value: String) {
            append("--\(boundary)\r\n")
            append("Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n")
            append("\(value)\r\n")
        }
        field("model", "saaras:v3")
        field("mode", mode)
        field("language_code", language)
        append("--\(boundary)\r\n")
        append("Content-Disposition: form-data; name=\"file\"; filename=\"\(filename)\"\r\n")
        append("Content-Type: \(mimeType)\r\n\r\n")
        body.append(audioData)
        append("\r\n--\(boundary)--\r\n")
        return body
    }

    static func mimeType(for audioURL: URL) -> String {
        switch audioURL.pathExtension.lowercased() {
        case "wav": "audio/wav"
        case "mp3": "audio/mpeg"
        default: "audio/mp4"
        }
    }

    private static func extractErrorMessage(from data: Data) -> String? {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        return object["detail"] as? String ?? object["message"] as? String ?? object["error"] as? String
    }
}

private struct ChatRequest: Encodable {
    struct Message: Encodable {
        let role: String
        let content: String
    }
    let model: String
    let messages: [Message]
    let temperature: Double
    let maxTokens: Int

    enum CodingKeys: String, CodingKey {
        case model, messages, temperature
        case maxTokens = "max_tokens"
    }
}

private struct ChatResponse: Decodable {
    struct Choice: Decodable {
        struct Message: Decodable { let content: String }
        let message: Message
    }
    let choices: [Choice]
}

enum SarvamError: LocalizedError {
    case invalidResponse
    case http(status: Int, message: String?)
    case decoding(String)

    var errorDescription: String? {
        switch self {
        case .invalidResponse: "Sarvam returned an invalid response."
        case let .http(status, message):
            switch status {
            case 403: "Sarvam rejected the API key. Check it in Settings."
            case 413, 422: message ?? "The audio could not be processed. Try a shorter recording."
            case 429: "Sarvam's rate limit was reached. Please try again shortly."
            default: message ?? "Sarvam request failed (HTTP \(status))."
            }
        case let .decoding(message): "Could not read Sarvam's response: \(message)"
        }
    }
}
