import Foundation
import UIKit

/// Claude through the Anthropic Messages API.
/// Structured results come back as a tool call with a strict input schema.
struct AnthropicProvider: AIProvider {
    let kind: AIProviderKind = .anthropic
    let model: String
    let apiKey: String

    private static let endpoint = URL(string: "https://api.anthropic.com/v1/messages")!
    private static let version = "2023-06-01"

    func analyzeGarment(image: UIImage, context: AnalysisContext) async throws -> GarmentAnalysis {
        guard let base64 = image.base64ForUpload() else { throw AIError.imageEncodingFailed }

        let body: [String: Any] = [
            "model": model,
            "max_tokens": 16000,
            "system": AIPrompts.garmentSystemPrompt(context),
            "tools": [tool(named: "save_garment",
                           description: "Record the catalogue entry for the garment in the photo.",
                           schema: AIPrompts.garmentSchema(strict: true))],
            "tool_choice": ["type": "auto"],
            "messages": [[
                "role": "user",
                "content": [
                    ["type": "image", "source": ["type": "base64", "media_type": "image/jpeg", "data": base64]],
                    ["type": "text", "text": AIPrompts.garmentUserPrompt + " Use the save_garment tool."]
                ]
            ]]
        ]

        let json = try await send(body)
        return try AIHTTP.decode(GarmentAnalysis.self, from: try structuredPayload(from: json))
    }

    func suggestOutfits(_ request: OutfitRequest) async throws -> [OutfitSuggestionDTO] {
        let body: [String: Any] = [
            "model": model,
            "max_tokens": 16000,
            "system": AIPrompts.outfitSystemPrompt(request),
            "tools": [tool(named: "propose_outfits",
                           description: "Return the proposed outfits.",
                           schema: AIPrompts.outfitSchema(strict: true))],
            "tool_choice": ["type": "auto"],
            "messages": [[
                "role": "user",
                "content": AIPrompts.outfitUserPrompt(request) + "\n\nUse the propose_outfits tool."
            ]]
        ]

        let json = try await send(body)
        let payload = try structuredPayload(from: json)
        return try AIHTTP.decode(OutfitSuggestionList.self, from: payload).outfits
    }

    // MARK: - Plumbing

    private func tool(named name: String, description: String, schema: [String: Any]) -> [String: Any] {
        ["name": name, "description": description, "input_schema": schema, "strict": true]
    }

    private func send(_ body: [String: Any]) async throws -> [String: Any] {
        guard !apiKey.isEmpty else { throw AIError.missingKey(.anthropic) }
        return try await AIHTTP.postJSON(
            url: Self.endpoint,
            body: body,
            headers: ["x-api-key": apiKey, "anthropic-version": Self.version]
        )
    }

    /// Prefers the tool call; falls back to parsing JSON out of the text blocks.
    private func structuredPayload(from json: [String: Any]) throws -> [String: Any] {
        guard let content = json["content"] as? [[String: Any]] else {
            throw AIError.malformedResponse("\(json)")
        }
        if let toolUse = content.first(where: { $0["type"] as? String == "tool_use" }),
           let input = toolUse["input"] as? [String: Any] {
            return input
        }
        let text = content
            .filter { $0["type"] as? String == "text" }
            .compactMap { $0["text"] as? String }
            .joined()
        guard !text.isEmpty else {
            let stop = json["stop_reason"] as? String ?? "unknown"
            throw AIError.malformedResponse("Empty response (stop_reason: \(stop))")
        }
        return try AIHTTP.decodeJSONObject(from: text)
    }
}
