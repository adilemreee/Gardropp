import Foundation
import UIKit

/// One client for every OpenAI-shaped `/chat/completions` API.
/// OpenAI itself takes a strict `json_schema`; DeepSeek uses `json_object`
/// with the schema described in the prompt.
struct OpenAICompatibleProvider: AIProvider {
    let kind: AIProviderKind
    let model: String
    let apiKey: String
    let baseURL: URL
    /// True when the service supports `response_format.json_schema`.
    let supportsJSONSchema: Bool

    static func openAI(model: String, apiKey: String) -> Self {
        Self(kind: .openai,
             model: model,
             apiKey: apiKey,
             baseURL: URL(string: "https://api.openai.com/v1/chat/completions")!,
             supportsJSONSchema: true)
    }

    static func deepSeek(model: String, apiKey: String) -> Self {
        Self(kind: .deepseek,
             model: model,
             apiKey: apiKey,
             baseURL: URL(string: "https://api.deepseek.com/chat/completions")!,
             supportsJSONSchema: false)
    }

    func analyzeGarment(image: UIImage, context: AnalysisContext) async throws -> GarmentAnalysis {
        guard let base64 = image.base64ForUpload() else { throw AIError.imageEncodingFailed }
        let schema = AIPrompts.garmentSchema(strict: supportsJSONSchema)
        var system = AIPrompts.garmentSystemPrompt(context)
        if !supportsJSONSchema { system += "\n\n" + AIPrompts.schemaHint(schema) }

        let body = requestBody(
            system: system,
            userContent: [
                ["type": "text", "text": AIPrompts.garmentUserPrompt],
                ["type": "image_url", "image_url": ["url": "data:image/jpeg;base64,\(base64)", "detail": "high"]]
            ],
            schemaName: "garment",
            schema: schema
        )

        let json = try await send(body)
        return try AIHTTP.decode(GarmentAnalysis.self, from: try payload(from: json))
    }

    func suggestOutfits(_ request: OutfitRequest) async throws -> [OutfitSuggestionDTO] {
        let schema = AIPrompts.outfitSchema(strict: supportsJSONSchema)
        var system = AIPrompts.outfitSystemPrompt(request)
        if !supportsJSONSchema { system += "\n\n" + AIPrompts.schemaHint(schema) }

        let body = requestBody(
            system: system,
            userContent: [["type": "text", "text": AIPrompts.outfitUserPrompt(request)]],
            schemaName: "outfits",
            schema: schema
        )

        let json = try await send(body)
        return try AIHTTP.decode(OutfitSuggestionList.self, from: try payload(from: json)).outfits
    }

    // MARK: - Plumbing

    private func requestBody(
        system: String,
        userContent: [[String: Any]],
        schemaName: String,
        schema: [String: Any]
    ) -> [String: Any] {
        var body: [String: Any] = [
            "model": model,
            "messages": [
                ["role": "system", "content": system],
                ["role": "user", "content": userContent]
            ]
        ]
        if supportsJSONSchema {
            body["response_format"] = [
                "type": "json_schema",
                "json_schema": ["name": schemaName, "strict": true, "schema": schema]
            ]
        } else {
            body["response_format"] = ["type": "json_object"]
        }
        return body
    }

    private func send(_ body: [String: Any]) async throws -> [String: Any] {
        guard !apiKey.isEmpty else { throw AIError.missingKey(kind) }
        return try await AIHTTP.postJSON(
            url: baseURL,
            body: body,
            headers: ["Authorization": "Bearer \(apiKey)"]
        )
    }

    private func payload(from json: [String: Any]) throws -> [String: Any] {
        guard let choices = json["choices"] as? [[String: Any]],
              let message = choices.first?["message"] as? [String: Any] else {
            throw AIError.malformedResponse("\(json)")
        }
        // Reasoning models may return content as an array of parts.
        if let text = message["content"] as? String, !text.isEmpty {
            return try AIHTTP.decodeJSONObject(from: text)
        }
        if let parts = message["content"] as? [[String: Any]] {
            let text = parts.compactMap { $0["text"] as? String }.joined()
            if !text.isEmpty { return try AIHTTP.decodeJSONObject(from: text) }
        }
        throw AIError.malformedResponse("\(message)")
    }
}
