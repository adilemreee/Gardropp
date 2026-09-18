import Foundation
import UIKit

/// Google Gemini through the Generative Language API, using `responseSchema`
/// so the model answers with schema-valid JSON.
struct GeminiProvider: AIProvider {
    let kind: AIProviderKind = .gemini
    let model: String
    let apiKey: String

    func analyzeGarment(image: UIImage, context: AnalysisContext) async throws -> GarmentAnalysis {
        guard let base64 = image.base64ForUpload() else { throw AIError.imageEncodingFailed }
        let body: [String: Any] = [
            "systemInstruction": ["parts": [["text": AIPrompts.garmentSystemPrompt(context)]]],
            "contents": [[
                "role": "user",
                "parts": [
                    ["inline_data": ["mime_type": "image/jpeg", "data": base64]],
                    ["text": AIPrompts.garmentUserPrompt]
                ]
            ]],
            "generationConfig": [
                "responseMimeType": "application/json",
                "responseSchema": AIPrompts.geminiGarmentSchema
            ]
        ]
        return try AIHTTP.decode(GarmentAnalysis.self, from: try payload(from: try await send(body)))
    }

    func suggestOutfits(_ request: OutfitRequest) async throws -> [OutfitSuggestionDTO] {
        let body: [String: Any] = [
            "systemInstruction": ["parts": [["text": AIPrompts.outfitSystemPrompt(request)]]],
            "contents": [["role": "user", "parts": [["text": AIPrompts.outfitUserPrompt(request)]]]],
            "generationConfig": [
                "responseMimeType": "application/json",
                "responseSchema": AIPrompts.geminiOutfitSchema
            ]
        ]
        let json = try await send(body)
        return try AIHTTP.decode(OutfitSuggestionList.self, from: try payload(from: json)).outfits
    }

    // MARK: - Plumbing

    private func send(_ body: [String: Any]) async throws -> [String: Any] {
        guard !apiKey.isEmpty else { throw AIError.missingKey(.gemini) }
        guard let url = URL(string: "https://generativelanguage.googleapis.com/v1beta/models/\(model):generateContent") else {
            throw AIError.malformedResponse("Invalid model name")
        }
        return try await AIHTTP.postJSON(url: url, body: body, headers: ["x-goog-api-key": apiKey])
    }

    private func payload(from json: [String: Any]) throws -> [String: Any] {
        guard let candidates = json["candidates"] as? [[String: Any]],
              let content = candidates.first?["content"] as? [String: Any],
              let parts = content["parts"] as? [[String: Any]] else {
            throw AIError.malformedResponse("\(json)")
        }
        let text = parts.compactMap { $0["text"] as? String }.joined()
        guard !text.isEmpty else { throw AIError.malformedResponse("\(json)") }
        return try AIHTTP.decodeJSONObject(from: text)
    }
}
