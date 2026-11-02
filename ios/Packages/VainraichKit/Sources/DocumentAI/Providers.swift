import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

// MARK: - Input / errors / protocol

/// What we send to an extractor.
public enum DocumentInput: Sendable {
    /// A photo / screenshot / scanned page.
    case image(Data, mimeType: String)
    /// Original PDF bytes.
    case pdf(Data)
    /// Text already extracted on the device (OCR or PDF text layer), optionally redacted.
    case text(String)

    public var kindDescription: String {
        switch self {
        case .image: return "image"
        case .pdf: return "pdf"
        case .text: return "text"
        }
    }
}

public enum AIProviderError: Error, Equatable, Sendable {
    case missingAPIKey
    case unsupportedInput(String)
    case rateLimited(retryAfterSeconds: Int?)
    case unauthorized
    case http(status: Int, message: String)
    case invalidResponse(String)
    case refused(String)
    case network(String)

    /// Hebrew message for the UI.
    public var hebrewMessage: String {
        switch self {
        case .missingAPIKey: return "לא הוגדר מפתח API לספק הזה. אפשר להוסיף אותו בהגדרות ← בינה מלאכותית."
        case .unsupportedInput(let s): return "הספק לא תומך בסוג הקובץ הזה (\(s))."
        case .rateLimited(let s): return "הגעת למכסה החינמית של הספק כרגע." + (s.map { " נסה שוב בעוד \($0) שניות." } ?? " נסה שוב מאוחר יותר.")
        case .unauthorized: return "המפתח נדחה על ידי הספק. בדוק שהעתקת אותו נכון ושהוא פעיל."
        case .http(let code, let m): return "שגיאה מהספק (\(code)): \(m)"
        case .invalidResponse(let m): return "לא הצלחתי להבין את תשובת הבינה המלאכותית: \(m)"
        case .refused(let m): return "הספק סירב לעבד את המסמך: \(m)"
        case .network(let m): return "בעיית רשת: \(m)"
        }
    }
}

public struct ProviderCapabilities: Sendable, Hashable {
    public var acceptsPDF: Bool
    public var acceptsImages: Bool
    public var runsOnDevice: Bool
    public init(acceptsPDF: Bool, acceptsImages: Bool, runsOnDevice: Bool = false) {
        self.acceptsPDF = acceptsPDF
        self.acceptsImages = acceptsImages
        self.runsOnDevice = runsOnDevice
    }
}

/// Anything that can turn a document into structured financial data.
public protocol DocumentExtractor: Sendable {
    var displayName: String { get }
    var capabilities: ProviderCapabilities { get }
    func extract(_ input: DocumentInput) async throws -> ExtractionResult
}

/// A remote AI service that can also list its models and verify a key.
public protocol RemoteAIProvider: DocumentExtractor {
    func listModels() async throws -> [String]
}

// MARK: - HTTP

public protocol HTTPClient: Sendable {
    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse)
}

public struct URLSessionHTTPClient: HTTPClient {
    public init() {}
    public func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        try await withCheckedThrowingContinuation { cont in
            let task = URLSession.shared.dataTask(with: request) { data, response, error in
                if let error {
                    cont.resume(throwing: AIProviderError.network(error.localizedDescription))
                } else if let http = response as? HTTPURLResponse {
                    cont.resume(returning: (data ?? Data(), http))
                } else {
                    cont.resume(throwing: AIProviderError.network("no response"))
                }
            }
            task.resume()
        }
    }
}

enum HTTP {
    static func jsonRequest(url: URL, method: String = "POST", headers: [String: String], body: Any?) throws -> URLRequest {
        var r = URLRequest(url: url, timeoutInterval: 180)
        r.httpMethod = method
        for (k, v) in headers { r.setValue(v, forHTTPHeaderField: k) }
        if let body {
            r.setValue("application/json", forHTTPHeaderField: "Content-Type")
            r.httpBody = try JSONSerialization.data(withJSONObject: body, options: [])
        }
        return r
    }

    static func checkStatus(_ data: Data, _ response: HTTPURLResponse) throws {
        guard !(200..<300).contains(response.statusCode) else { return }
        let message = errorMessage(from: data)
        switch response.statusCode {
        case 401, 403: throw AIProviderError.unauthorized
        case 429:
            let retry = (response.value(forHTTPHeaderField: "Retry-After")).flatMap { Int($0) }
            throw AIProviderError.rateLimited(retryAfterSeconds: retry)
        default:
            throw AIProviderError.http(status: response.statusCode, message: message)
        }
    }

    static func errorMessage(from data: Data) -> String {
        if let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            if let e = obj["error"] as? [String: Any], let m = e["message"] as? String { return m }
            if let m = obj["message"] as? String { return m }
            if let e = obj["error"] as? String { return e }
        }
        return String(data: data.prefix(300), encoding: .utf8) ?? "unknown"
    }

    static func object(_ data: Data) throws -> [String: Any] {
        guard let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw AIProviderError.invalidResponse("not a JSON object")
        }
        return obj
    }
}

// MARK: - Google Gemini

/// Google Gemini API (has a free tier; on the free tier Google may use the content to improve its products).
public struct GeminiProvider: RemoteAIProvider {
    public static let defaultModel = "gemini-flash-latest"
    public static let defaultBaseURL = URL(string: "https://generativelanguage.googleapis.com")!

    public var apiKey: String
    public var model: String
    public var baseURL: URL
    public var http: HTTPClient

    public init(apiKey: String, model: String = GeminiProvider.defaultModel, baseURL: URL = GeminiProvider.defaultBaseURL, http: HTTPClient = URLSessionHTTPClient()) {
        self.apiKey = apiKey
        self.model = model.isEmpty ? GeminiProvider.defaultModel : model
        self.baseURL = baseURL
        self.http = http
    }

    public var displayName: String { "Google Gemini (\(model))" }
    public var capabilities: ProviderCapabilities { ProviderCapabilities(acceptsPDF: true, acceptsImages: true) }

    public func makeRequest(_ input: DocumentInput) throws -> URLRequest {
        guard !apiKey.isEmpty else { throw AIProviderError.missingAPIKey }
        var parts: [[String: Any]] = []
        switch input {
        case .image(let data, let mime):
            parts.append(["inline_data": ["mime_type": mime, "data": data.base64EncodedString()]])
        case .pdf(let data):
            parts.append(["inline_data": ["mime_type": "application/pdf", "data": data.base64EncodedString()]])
        case .text(let text):
            parts.append(["text": "DOCUMENT TEXT:\n" + text])
        }
        parts.append(["text": ExtractionPrompt.user + "\n\n" + ExtractionPrompt.schemaDescription])
        let body: [String: Any] = [
            "systemInstruction": ["parts": [["text": ExtractionPrompt.system]]],
            "contents": [["role": "user", "parts": parts]],
            "generationConfig": ["responseMimeType": "application/json", "temperature": 0],
        ]
        let modelPath = model.hasPrefix("models/") ? model : "models/\(model)"
        let url = baseURL.appendingPathComponent("v1beta/\(modelPath):generateContent")
        return try HTTP.jsonRequest(url: url, headers: ["x-goog-api-key": apiKey], body: body)
    }

    public static func parseResponse(_ data: Data) throws -> String {
        let obj = try HTTP.object(data)
        if let feedback = obj["promptFeedback"] as? [String: Any], let reason = feedback["blockReason"] as? String {
            throw AIProviderError.refused(reason)
        }
        guard let candidates = obj["candidates"] as? [[String: Any]], let first = candidates.first else {
            throw AIProviderError.invalidResponse("no candidates")
        }
        let parts = ((first["content"] as? [String: Any])?["parts"] as? [[String: Any]]) ?? []
        let text = parts.compactMap { $0["text"] as? String }.joined()
        if text.isEmpty, let reason = first["finishReason"] as? String { throw AIProviderError.refused(reason) }
        return text
    }

    public func extract(_ input: DocumentInput) async throws -> ExtractionResult {
        let (data, response) = try await http.send(try makeRequest(input))
        try HTTP.checkStatus(data, response)
        return try ExtractionPrompt.parse(try GeminiProvider.parseResponse(data), producedBy: displayName)
    }

    public func listModels() async throws -> [String] {
        guard !apiKey.isEmpty else { throw AIProviderError.missingAPIKey }
        let url = baseURL.appendingPathComponent("v1beta/models")
        let (data, response) = try await http.send(try HTTP.jsonRequest(url: url, method: "GET", headers: ["x-goog-api-key": apiKey], body: nil))
        try HTTP.checkStatus(data, response)
        let models = (try HTTP.object(data)["models"] as? [[String: Any]]) ?? []
        return models.filter { (($0["supportedGenerationMethods"] as? [String]) ?? []).contains("generateContent") }
            .compactMap { ($0["name"] as? String)?.replacingOccurrences(of: "models/", with: "") }
            .sorted()
    }
}

// MARK: - OpenAI-compatible (OpenAI, Groq, OpenRouter, Mistral, local Ollama/LM Studio …)

public struct OpenAICompatibleProvider: RemoteAIProvider {
    public struct Preset: Hashable, Sendable, Identifiable {
        public var id: String
        public var name: String
        public var baseURL: URL
        public var suggestedModel: String
        public var hasFreeTier: Bool
        public var keyURL: URL?
        public var acceptsImages: Bool

        public static let openRouter = Preset(id: "openrouter", name: "OpenRouter", baseURL: URL(string: "https://openrouter.ai/api/v1")!,
                                              suggestedModel: "", hasFreeTier: true,
                                              keyURL: URL(string: "https://openrouter.ai/keys"), acceptsImages: true)
        public static let groq = Preset(id: "groq", name: "Groq", baseURL: URL(string: "https://api.groq.com/openai/v1")!,
                                        suggestedModel: "", hasFreeTier: true, keyURL: URL(string: "https://console.groq.com/keys"), acceptsImages: true)
        public static let openAI = Preset(id: "openai", name: "OpenAI", baseURL: URL(string: "https://api.openai.com/v1")!,
                                          suggestedModel: "", hasFreeTier: false, keyURL: URL(string: "https://platform.openai.com/api-keys"), acceptsImages: true)
        public static let mistral = Preset(id: "mistral", name: "Mistral", baseURL: URL(string: "https://api.mistral.ai/v1")!,
                                           suggestedModel: "", hasFreeTier: true, keyURL: URL(string: "https://console.mistral.ai/api-keys"), acceptsImages: true)
        public static let custom = Preset(id: "custom", name: "שרת מותאם (Ollama / LM Studio)", baseURL: URL(string: "http://192.168.1.10:11434/v1")!,
                                          suggestedModel: "", hasFreeTier: true, keyURL: nil, acceptsImages: true)

        public static let all: [Preset] = [.openRouter, .groq, .mistral, .openAI, .custom]
    }

    public var name: String
    public var apiKey: String
    public var model: String
    public var baseURL: URL
    public var useJSONMode: Bool
    public var acceptsImages: Bool
    public var http: HTTPClient

    public init(name: String, apiKey: String, model: String, baseURL: URL, useJSONMode: Bool = true, acceptsImages: Bool = true, http: HTTPClient = URLSessionHTTPClient()) {
        self.name = name
        self.apiKey = apiKey
        self.model = model
        self.baseURL = baseURL
        self.useJSONMode = useJSONMode
        self.acceptsImages = acceptsImages
        self.http = http
    }

    public var displayName: String { "\(name) (\(model))" }
    /// PDFs are converted to text/images on the device first.
    public var capabilities: ProviderCapabilities { ProviderCapabilities(acceptsPDF: false, acceptsImages: acceptsImages) }

    var headers: [String: String] {
        var h: [String: String] = [:]
        if !apiKey.isEmpty { h["Authorization"] = "Bearer \(apiKey)" }
        h["X-Title"] = "Vainraich Finance" // OpenRouter attribution header; ignored elsewhere
        return h
    }

    public func makeRequest(_ input: DocumentInput) throws -> URLRequest {
        guard !model.isEmpty else { throw AIProviderError.invalidResponse("לא נבחר מודל") }
        var content: [[String: Any]] = [["type": "text", "text": ExtractionPrompt.user + "\n\n" + ExtractionPrompt.schemaDescription]]
        switch input {
        case .image(let data, let mime):
            guard acceptsImages else { throw AIProviderError.unsupportedInput("image") }
            content.append(["type": "image_url", "image_url": ["url": "data:\(mime);base64,\(data.base64EncodedString())"]])
        case .pdf:
            throw AIProviderError.unsupportedInput("pdf")
        case .text(let text):
            content.insert(["type": "text", "text": "DOCUMENT TEXT:\n" + text], at: 0)
        }
        var body: [String: Any] = [
            "model": model,
            "messages": [
                ["role": "system", "content": ExtractionPrompt.system],
                ["role": "user", "content": content],
            ],
        ]
        if useJSONMode { body["response_format"] = ["type": "json_object"] }
        return try HTTP.jsonRequest(url: baseURL.appendingPathComponent("chat/completions"), headers: headers, body: body)
    }

    public static func parseResponse(_ data: Data) throws -> String {
        let obj = try HTTP.object(data)
        guard let choices = obj["choices"] as? [[String: Any]], let first = choices.first,
              let message = first["message"] as? [String: Any] else {
            throw AIProviderError.invalidResponse("no choices")
        }
        if let refusal = message["refusal"] as? String, !refusal.isEmpty { throw AIProviderError.refused(refusal) }
        if let text = message["content"] as? String { return text }
        if let parts = message["content"] as? [[String: Any]] { return parts.compactMap { $0["text"] as? String }.joined() }
        throw AIProviderError.invalidResponse("empty content")
    }

    public func extract(_ input: DocumentInput) async throws -> ExtractionResult {
        let (data, response) = try await http.send(try makeRequest(input))
        // Some models reject JSON mode — retry once without it.
        if response.statusCode == 400, useJSONMode, HTTP.errorMessage(from: data).lowercased().contains("response_format") {
            var copy = self
            copy.useJSONMode = false
            return try await copy.extract(input)
        }
        try HTTP.checkStatus(data, response)
        return try ExtractionPrompt.parse(try OpenAICompatibleProvider.parseResponse(data), producedBy: displayName)
    }

    public func listModels() async throws -> [String] {
        let (data, response) = try await http.send(try HTTP.jsonRequest(url: baseURL.appendingPathComponent("models"), method: "GET", headers: headers, body: nil))
        try HTTP.checkStatus(data, response)
        let list = (try HTTP.object(data)["data"] as? [[String: Any]]) ?? []
        return list.compactMap { $0["id"] as? String }.sorted()
    }
}

// MARK: - Anthropic Claude (paid)

public struct AnthropicProvider: RemoteAIProvider {
    public static let defaultModel = "claude-opus-5-5"
    public static let apiVersion = "2026-10-21"

    public var apiKey: String
    public var model: String
    public var baseURL: URL
    public var http: HTTPClient

    public init(apiKey: String, model: String = AnthropicProvider.defaultModel, baseURL: URL = URL(string: "https://api.anthropic.com")!, http: HTTPClient = URLSessionHTTPClient()) {
        self.apiKey = apiKey
        self.model = model.isEmpty ? AnthropicProvider.defaultModel : model
        self.baseURL = baseURL
        self.http = http
    }

    public var displayName: String { "Anthropic Claude (\(model))" }
    public var capabilities: ProviderCapabilities { ProviderCapabilities(acceptsPDF: true, acceptsImages: true) }

    var headers: [String: String] {
        [
            "x-api-key": apiKey,
            "anthropic-version": AnthropicProvider.apiVersion,
            // Server-side fallback if a safety classifier declines the request.
            "anthropic-beta": "server-side-fallback-2026-07-01",
        ]
    }

    public func makeRequest(_ input: DocumentInput) throws -> URLRequest {
        guard !apiKey.isEmpty else { throw AIProviderError.missingAPIKey }
        var content: [[String: Any]] = []
        switch input {
        case .image(let data, let mime):
            content.append(["type": "image", "source": ["type": "base64", "media_type": mime, "data": data.base64EncodedString()]])
        case .pdf(let data):
            content.append(["type": "document", "source": ["type": "base64", "media_type": "application/pdf", "data": data.base64EncodedString()]])
        case .text(let text):
            content.append(["type": "text", "text": "DOCUMENT TEXT:\n" + text])
        }
        content.append(["type": "text", "text": ExtractionPrompt.user])
        let body: [String: Any] = [
            "model": model,
            "max_tokens": 16000,
            "system": ExtractionPrompt.system,
            "messages": [["role": "user", "content": content]],
            "output_config": ["format": ["type": "json_schema", "schema": ExtractionPrompt.jsonSchema]],
            "fallbacks": "default",
        ]
        return try HTTP.jsonRequest(url: baseURL.appendingPathComponent("v1/messages"), headers: headers, body: body)
    }

    public static func parseResponse(_ data: Data) throws -> String {
        let obj = try HTTP.object(data)
        if (obj["stop_reason"] as? String) == "refusal" {
            let explanation = ((obj["stop_details"] as? [String: Any])?["explanation"] as? String) ?? "refusal"
            throw AIProviderError.refused(explanation)
        }
        let blocks = (obj["content"] as? [[String: Any]]) ?? []
        let text = blocks.filter { ($0["type"] as? String) == "text" }.compactMap { $0["text"] as? String }.joined()
        guard !text.isEmpty else { throw AIProviderError.invalidResponse("empty content") }
        return text
    }

    public func extract(_ input: DocumentInput) async throws -> ExtractionResult {
        let (data, response) = try await http.send(try makeRequest(input))
        try HTTP.checkStatus(data, response)
        return try ExtractionPrompt.parse(try AnthropicProvider.parseResponse(data), producedBy: displayName)
    }

    public func listModels() async throws -> [String] {
        guard !apiKey.isEmpty else { throw AIProviderError.missingAPIKey }
        var h = headers
        h.removeValue(forKey: "anthropic-beta")
        let (data, response) = try await http.send(try HTTP.jsonRequest(url: baseURL.appendingPathComponent("v1/models"), method: "GET", headers: h, body: nil))
        try HTTP.checkStatus(data, response)
        let list = (try HTTP.object(data)["data"] as? [[String: Any]]) ?? []
        return list.compactMap { $0["id"] as? String }
    }
}
