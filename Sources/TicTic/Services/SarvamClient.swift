import Foundation

struct SarvamClient {
    var session: URLSession = .shared
    var baseURL = URL(string: "https://tictic-api.vercel.app/api/")!

    func usage(accessCode: String) async throws -> BetaUsage {
        let data = try await post(path: "usage", payload: UsageRequest(inviteCode: accessCode))
        return try decode(BetaUsage.self, from: data)
    }

    func transcribe(
        audioURL: URL,
        accessCode: String,
        language: IndicLanguage,
        mode: TranscriptionMode,
        durationSeconds: TimeInterval
    ) async throws -> SarvamTranscript {
        let audioData = try Data(contentsOf: audioURL)
        let payload = TranscriptionRequest(
            inviteCode: accessCode,
            audioBase64: audioData.base64EncodedString(),
            filename: audioURL.lastPathComponent,
            mimeType: Self.mimeType(for: audioURL),
            languageCode: language.rawValue,
            mode: mode.rawValue,
            durationSeconds: durationSeconds
        )
        let data = try await post(path: "transcribe", payload: payload, timeout: 75)
        return try decode(SarvamTranscript.self, from: data)
    }

    func polish(
        _ text: String,
        accessCode: String,
        formatToken: String,
        mode: TranscriptionMode,
        style: WritingStyle,
        applicationName: String?,
        vocabulary: String
    ) async throws -> String {
        try await format(
            text,
            accessCode: accessCode,
            formatToken: formatToken,
            mode: mode,
            style: style,
            applicationName: applicationName,
            vocabulary: vocabulary,
            operation: "polish"
        )
    }

    func romanize(
        _ text: String,
        accessCode: String,
        formatToken: String,
        vocabulary: String
    ) async throws -> String {
        try await format(
            text,
            accessCode: accessCode,
            formatToken: formatToken,
            mode: .translit,
            style: .clean,
            applicationName: nil,
            vocabulary: vocabulary,
            operation: "romanize"
        )
    }

    static func containsNativeIndicScript(_ text: String) -> Bool {
        for scalar in text.unicodeScalars {
            switch scalar.value {
            case 0x0600...0x077F,
                 0x0900...0x0D7F,
                 0x1C50...0x1C7F,
                 0xA8E0...0xA8FF,
                 0xABC0...0xABFF:
                return true
            default:
                continue
            }
        }
        return false
    }

    private func format(
        _ text: String,
        accessCode: String,
        formatToken: String,
        mode: TranscriptionMode,
        style: WritingStyle,
        applicationName: String?,
        vocabulary: String,
        operation: String
    ) async throws -> String {
        let payload = FormatRequest(
            inviteCode: accessCode,
            formatToken: formatToken,
            text: text,
            mode: mode.rawValue,
            style: style.rawValue,
            applicationName: applicationName,
            vocabulary: vocabulary,
            operation: operation
        )
        let data = try await post(path: "polish", payload: payload, timeout: 75)
        return try decode(FormatResponse.self, from: data).text
    }

    private func post<T: Encodable>(path: String, payload: T, timeout: TimeInterval = 30) async throws -> Data {
        var request = URLRequest(url: baseURL.appendingPathComponent(path))
        request.httpMethod = "POST"
        request.timeoutInterval = timeout
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(payload)

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw SarvamError.invalidResponse }
        guard (200..<300).contains(http.statusCode) else {
            throw SarvamError.http(status: http.statusCode, message: Self.extractErrorMessage(from: data))
        }
        return data
    }

    private func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        do {
            return try JSONDecoder().decode(type, from: data)
        } catch {
            throw SarvamError.decoding(error.localizedDescription)
        }
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
        return object["message"] as? String ?? object["detail"] as? String ?? object["error"] as? String
    }
}

private struct UsageRequest: Encodable {
    let inviteCode: String
    enum CodingKeys: String, CodingKey { case inviteCode = "invite_code" }
}

private struct TranscriptionRequest: Encodable {
    let inviteCode: String
    let audioBase64: String
    let filename: String
    let mimeType: String
    let languageCode: String
    let mode: String
    let durationSeconds: Double

    enum CodingKeys: String, CodingKey {
        case inviteCode = "invite_code"
        case audioBase64 = "audio_base64"
        case filename
        case mimeType = "mime_type"
        case languageCode = "language_code"
        case mode
        case durationSeconds = "duration_seconds"
    }
}

private struct FormatRequest: Encodable {
    let inviteCode: String
    let formatToken: String
    let text: String
    let mode: String
    let style: String
    let applicationName: String?
    let vocabulary: String
    let operation: String

    enum CodingKeys: String, CodingKey {
        case inviteCode = "invite_code"
        case formatToken = "format_token"
        case text, mode, style, vocabulary, operation
        case applicationName = "application_name"
    }
}

private struct FormatResponse: Decodable { let text: String }

enum SarvamError: LocalizedError {
    case invalidResponse
    case http(status: Int, message: String?)
    case decoding(String)

    var errorDescription: String? {
        switch self {
        case .invalidResponse: "TicTic returned an invalid response."
        case let .http(status, message):
            switch status {
            case 401: message ?? "This beta access code is not valid."
            case 402: message ?? "Your five-minute beta allowance has been used."
            case 413: message ?? "The audio segment is too large."
            case 429: message ?? "TicTic is busy. Please try again shortly."
            default: message ?? "TicTic request failed (HTTP \(status))."
            }
        case let .decoding(message): "Could not read TicTic's response: \(message)"
        }
    }
}
