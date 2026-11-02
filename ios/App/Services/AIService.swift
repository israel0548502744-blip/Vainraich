import Foundation
import UIKit
import PDFKit
import Vision
import FinanceCore
import DocumentAI
#if canImport(FoundationModels)
import FoundationModels
#endif

/// The AI engines the user can choose from. Free options first.
enum AIProviderID: String, CaseIterable, Identifiable {
    case onDevice, appleIntelligence, gemini, openRouter, groq, mistral, openAI, anthropic, custom

    var id: String { rawValue }

    var name: String {
        switch self {
        case .onDevice: return "זיהוי בסיסי במכשיר"
        case .appleIntelligence: return "Apple Intelligence"
        case .gemini: return "Google Gemini"
        case .openRouter: return "OpenRouter"
        case .groq: return "Groq"
        case .mistral: return "Mistral"
        case .openAI: return "OpenAI"
        case .anthropic: return "Anthropic Claude"
        case .custom: return "שרת משלך (Ollama / LM Studio)"
        }
    }

    var priceNote: String {
        switch self {
        case .onDevice: return "חינם · ללא אינטרנט · דיוק בסיסי"
        case .appleIntelligence: return "חינם · פרטי, במכשיר · רק באייפונים תומכים"
        case .gemini: return "יש מסלול חינמי עם מגבלת שימוש"
        case .openRouter: return "יש מודלים חינמיים (מסומנים free)"
        case .groq: return "יש מסלול חינמי עם מגבלת שימוש"
        case .mistral: return "יש מסלול ניסיון חינמי"
        case .openAI: return "בתשלום לפי שימוש"
        case .anthropic: return "בתשלום לפי שימוש"
        case .custom: return "חינם · רץ על מחשב שלך ברשת הביתית"
        }
    }

    var isFree: Bool { [.onDevice, .appleIntelligence, .gemini, .openRouter, .groq, .mistral, .custom].contains(self) }
    var needsKey: Bool { ![.onDevice, .appleIntelligence, .custom].contains(self) }
    var isRemote: Bool { ![.onDevice, .appleIntelligence].contains(self) }

    var keyURL: URL? {
        switch self {
        case .gemini: return URL(string: "https://aistudio.google.com/apikey")
        case .openRouter: return OpenAICompatibleProvider.Preset.openRouter.keyURL
        case .groq: return OpenAICompatibleProvider.Preset.groq.keyURL
        case .mistral: return OpenAICompatibleProvider.Preset.mistral.keyURL
        case .openAI: return OpenAICompatibleProvider.Preset.openAI.keyURL
        case .anthropic: return URL(string: "https://console.anthropic.com/settings/keys")
        default: return nil
        }
    }

    var privacyNote: String? {
        switch self {
        case .gemini: return "במסלול החינמי של Google, התוכן שנשלח עשוי לשמש לשיפור המוצרים שלהם. מומלץ להפעיל \"שליחת טקסט בלבד עם הסתרת מספרים\"."
        case .openRouter: return "חלק מהמודלים החינמיים ב-OpenRouter עשויים לשמור את התוכן. מומלץ להפעיל \"שליחת טקסט בלבד עם הסתרת מספרים\"."
        case .groq, .mistral, .openAI, .anthropic: return "המסמך נשלח לשרתי הספק לעיבוד. בדוק את מדיניות הפרטיות שלו."
        default: return nil
        }
    }

    var defaultModel: String {
        switch self {
        case .gemini: return GeminiProvider.defaultModel
        case .anthropic: return AnthropicProvider.defaultModel
        default: return ""
        }
    }

    var preset: OpenAICompatibleProvider.Preset? {
        switch self {
        case .openRouter: return .openRouter
        case .groq: return .groq
        case .mistral: return .mistral
        case .openAI: return .openAI
        case .custom: return .custom
        default: return nil
        }
    }
}

/// Reads AI settings and builds the chosen extractor.
enum AISettings {
    static var provider: AIProviderID {
        get { AIProviderID(rawValue: UserDefaults.standard.string(forKey: "ai.provider") ?? "") ?? .onDevice }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: "ai.provider") }
    }
    static func model(for p: AIProviderID) -> String {
        UserDefaults.standard.string(forKey: "ai.model.\(p.rawValue)") ?? p.defaultModel
    }
    static func setModel(_ m: String, for p: AIProviderID) { UserDefaults.standard.set(m, forKey: "ai.model.\(p.rawValue)") }
    static var customBaseURL: String {
        get { UserDefaults.standard.string(forKey: "ai.baseURL.custom") ?? OpenAICompatibleProvider.Preset.custom.baseURL.absoluteString }
        set { UserDefaults.standard.set(newValue, forKey: "ai.baseURL.custom") }
    }
    /// Privacy mode: convert to text on the phone and mask ID/account numbers before sending.
    static var textOnlyRedacted: Bool {
        get { UserDefaults.standard.object(forKey: "ai.textOnly") as? Bool ?? false }
        set { UserDefaults.standard.set(newValue, forKey: "ai.textOnly") }
    }
    static func apiKey(for p: AIProviderID) -> String { KeychainStore.get("key.\(p.rawValue)") ?? "" }
    static func setAPIKey(_ k: String, for p: AIProviderID) { KeychainStore.set(k.trimmingCharacters(in: .whitespacesAndNewlines), for: "key.\(p.rawValue)") }

    static var appleIntelligenceAvailable: Bool {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *) { return AppleIntelligenceExtractor.isAvailable }
        #endif
        return false
    }

    static func extractor(for p: AIProviderID = provider) -> DocumentExtractor {
        switch p {
        case .onDevice:
            return RuleBasedExtractor()
        case .appleIntelligence:
            #if canImport(FoundationModels)
            if #available(iOS 26.0, *), AppleIntelligenceExtractor.isAvailable { return AppleIntelligenceExtractor() }
            #endif
            return RuleBasedExtractor()
        case .gemini:
            return GeminiProvider(apiKey: apiKey(for: p), model: model(for: p))
        case .anthropic:
            return AnthropicProvider(apiKey: apiKey(for: p), model: model(for: p))
        case .openRouter, .groq, .mistral, .openAI, .custom:
            let preset = p.preset!
            let base = p == .custom ? (URL(string: customBaseURL) ?? preset.baseURL) : preset.baseURL
            return OpenAICompatibleProvider(name: preset.name, apiKey: apiKey(for: p), model: model(for: p), baseURL: base, acceptsImages: preset.acceptsImages)
        }
    }

    static func remote(for p: AIProviderID) -> RemoteAIProvider? { extractor(for: p) as? RemoteAIProvider }
}

#if canImport(FoundationModels)
/// Apple's on-device model (iOS 26+, Apple Intelligence devices). Free and private; text input only.
@available(iOS 26.0, *)
struct AppleIntelligenceExtractor: DocumentExtractor {
    static var isAvailable: Bool {
        if case .available = SystemLanguageModel.default.availability { return true }
        return false
    }

    var displayName: String { "Apple Intelligence (במכשיר)" }
    var capabilities: ProviderCapabilities { ProviderCapabilities(acceptsPDF: false, acceptsImages: false, runsOnDevice: true) }

    func extract(_ input: DocumentInput) async throws -> ExtractionResult {
        guard case .text(let text) = input else { throw AIProviderError.unsupportedInput(input.kindDescription) }
        let session = LanguageModelSession(instructions: ExtractionPrompt.system)
        // The on-device model has a small context window — send the beginning of long documents.
        let prompt = ExtractionPrompt.user + "\n" + ExtractionPrompt.schemaDescription + "\n\nDOCUMENT TEXT:\n" + String(text.prefix(6000))
        let response = try await session.respond(to: prompt)
        return try ExtractionPrompt.parse(response.content, producedBy: displayName)
    }
}
#endif

// MARK: - Turning files into extractor input

/// A document the user picked, before processing.
enum PickedDocument {
    case images([UIImage])
    case pdf(Data)
    case text(String)
}

enum DocumentPreprocessor {
    /// Text recognition languages available on this device (Hebrew support depends on iOS version).
    static var ocrSupportsHebrew: Bool {
        let req = VNRecognizeTextRequest()
        req.recognitionLevel = .accurate
        let langs = (try? req.supportedRecognitionLanguages()) ?? []
        return langs.contains { $0.hasPrefix("he") }
    }

    static func recognizeText(in image: UIImage) async throws -> String {
        guard let cg = image.cgImage else { return "" }
        return try await withCheckedThrowingContinuation { cont in
            let request = VNRecognizeTextRequest { req, error in
                if let error { cont.resume(throwing: error); return }
                let lines = (req.results as? [VNRecognizedTextObservation] ?? [])
                    .sorted { $0.boundingBox.minY > $1.boundingBox.minY }
                    .compactMap { $0.topCandidates(1).first?.string }
                cont.resume(returning: lines.joined(separator: "\n"))
            }
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = false
            let supported = (try? request.supportedRecognitionLanguages()) ?? []
            request.recognitionLanguages = ["he-IL", "en-US"].filter { supported.contains($0) }
            DispatchQueue.global(qos: .userInitiated).async {
                do { try VNImageRequestHandler(cgImage: cg, orientation: .up).perform([request]) } catch { cont.resume(throwing: error) }
            }
        }
    }

    static func pdfText(_ data: Data) -> String {
        PDFDocument(data: data)?.string ?? ""
    }

    static func renderPDFPages(_ data: Data, maxPages: Int = 5) -> [UIImage] {
        guard let doc = PDFDocument(data: data) else { return [] }
        return (0..<min(doc.pageCount, maxPages)).compactMap { i in
            guard let page = doc.page(at: i) else { return nil }
            let rect = page.bounds(for: .mediaBox)
            let scale: CGFloat = 2
            let size = CGSize(width: rect.width * scale, height: rect.height * scale)
            return UIGraphicsImageRenderer(size: size).image { ctx in
                UIColor.white.setFill()
                ctx.fill(CGRect(origin: .zero, size: size))
                ctx.cgContext.translateBy(x: 0, y: size.height)
                ctx.cgContext.scaleBy(x: scale, y: -scale)
                page.draw(with: .mediaBox, to: ctx.cgContext)
            }
        }
    }

    static func makePDF(from images: [UIImage]) -> Data {
        let doc = PDFDocument()
        for (i, img) in images.enumerated() {
            if let page = PDFPage(image: img.downscaled(maxDimension: 2000)) { doc.insert(page, at: i) }
        }
        return doc.dataRepresentation() ?? Data()
    }

    static func jpeg(_ image: UIImage) -> Data {
        image.downscaled(maxDimension: 2000).jpegData(compressionQuality: 0.8) ?? Data()
    }

    /// Converts the picked document into one or more inputs the chosen extractor accepts.
    static func inputs(for doc: PickedDocument, extractor: DocumentExtractor, textOnlyRedacted: Bool) async throws -> [DocumentInput] {
        let caps = extractor.capabilities
        let wantsText = textOnlyRedacted || (!caps.acceptsImages && !caps.acceptsPDF)

        func textInput(_ s: String) -> DocumentInput { .text(textOnlyRedacted ? Redactor.redact(s) : s) }

        switch doc {
        case .text(let s):
            return [textInput(s)]

        case .pdf(let data):
            if !wantsText && caps.acceptsPDF { return [.pdf(data)] }
            let text = pdfText(data)
            if text.trimmingCharacters(in: .whitespacesAndNewlines).count > 40 { return [textInput(text)] }
            // Scanned PDF without a text layer.
            let pages = renderPDFPages(data)
            if !wantsText && caps.acceptsImages { return pages.map { .image(jpeg($0), mimeType: "image/jpeg") } }
            var all: [String] = []
            for p in pages { all.append(try await recognizeText(in: p)) }
            return [textInput(all.joined(separator: "\n"))]

        case .images(let images):
            if !wantsText && caps.acceptsPDF && images.count > 1 { return [.pdf(makePDF(from: images))] }
            if !wantsText && caps.acceptsImages { return images.map { .image(jpeg($0), mimeType: "image/jpeg") } }
            var all: [String] = []
            for img in images { all.append(try await recognizeText(in: img)) }
            return [textInput(all.joined(separator: "\n"))]
        }
    }

    /// Runs the extractor on every input and merges the results.
    static func extract(_ doc: PickedDocument, using extractor: DocumentExtractor, textOnlyRedacted: Bool) async throws -> ExtractionResult {
        let inputs = try await inputs(for: doc, extractor: extractor, textOnlyRedacted: textOnlyRedacted)
        var merged: ExtractionResult?
        for input in inputs {
            let r = try await extractor.extract(input)
            if var m = merged {
                m.transactions += r.transactions
                m.balances += r.balances
                m.warnings += r.warnings
                merged = m
            } else {
                merged = r
            }
        }
        guard var result = merged else { throw AIProviderError.invalidResponse("המסמך ריק") }
        if result.transactions.isEmpty && result.balances.isEmpty {
            result.warnings.append("לא נמצאו תנועות או יתרות. אם זה סריקה בעברית, נסה ספק בינה מלאכותית אחר או צילום ברור יותר.")
        }
        return result
    }
}

extension AIProviderError: DocumentAIErrorBridge {
    var message: String { hebrewMessage }
}
