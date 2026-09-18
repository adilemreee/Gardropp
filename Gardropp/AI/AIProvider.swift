import Foundation
import SwiftUI
import UIKit

// MARK: - Provider catalogue

enum AIProviderKind: String, CaseIterable, Identifiable, Codable {
    case onDevice
    case anthropic
    case openai
    case gemini
    case deepseek

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .onDevice: String(localized: "On-device")
        case .anthropic: "Claude"
        case .openai: "OpenAI"
        case .gemini: "Gemini"
        case .deepseek: "DeepSeek"
        }
    }

    var blurb: LocalizedStringKey {
        switch self {
        case .onDevice: "Free and private. Recognises colour, shape and type without leaving your phone."
        case .anthropic: "Anthropic's Claude models. Strong at reading logos and naming garments."
        case .openai: "GPT models through the OpenAI API."
        case .gemini: "Google's Gemini models."
        case .deepseek: "DeepSeek models. deepseek-flash supports images."
        }
    }

    var requiresKey: Bool { self != .onDevice }

    var defaultModel: String {
        switch self {
        case .onDevice: ""
        case .anthropic: "claude-opus-5"
        case .openai: "gpt-6-astra"
        case .gemini: "gemini-3.8-flash"
        case .deepseek: "deepseek-flash"
        }
    }

    /// Shown in the model picker; the field stays editable for anything newer.
    var suggestedModels: [String] {
        switch self {
        case .onDevice: []
        case .anthropic: ["claude-opus-5", "claude-sonnet-5", "claude-haiku-4-5"]
        case .openai: ["gpt-6-astra", "gpt-5.6-terra", "gpt-5.6-luna"]
        case .gemini: ["gemini-3.8-flash", "gemini-3.5-flash-lite", "gemini-2.5-pro"]
        case .deepseek: ["deepseek-flash", "deepseek-v4-pro"]
        }
    }

    /// `deepseek-v4-pro` is text-only; everything else in the list reads images.
    func supportsVision(model: String) -> Bool {
        switch self {
        case .onDevice: true
        case .deepseek: !model.contains("v4-pro")
        default: true
        }
    }

    var keychainAccount: String { "apikey.\(rawValue)" }

    var consoleURL: URL? {
        switch self {
        case .onDevice: nil
        case .anthropic: URL(string: "https://console.anthropic.com/settings/keys")
        case .openai: URL(string: "https://platform.openai.com/api-keys")
        case .gemini: URL(string: "https://aistudio.google.com/apikey")
        case .deepseek: URL(string: "https://platform.deepseek.com/api_keys")
        }
    }
}

// MARK: - Provider protocol

protocol AIProvider {
    var kind: AIProviderKind { get }
    var model: String { get }
    func analyzeGarment(image: UIImage, context: AnalysisContext) async throws -> GarmentAnalysis
    func suggestOutfits(_ request: OutfitRequest) async throws -> [OutfitSuggestionDTO]
}

// MARK: - Errors

enum AIError: LocalizedError {
    case missingKey(AIProviderKind)
    case http(status: Int, message: String)
    case malformedResponse(String)
    case imageEncodingFailed
    case notEnoughItems

    var errorDescription: String? {
        switch self {
        case .missingKey(let kind):
            String(localized: "Add your \(kind.displayName) API key in Settings to use it.")
        case .http(let status, let message):
            message.isEmpty ? String(localized: "The service replied with error \(status).") : message
        case .malformedResponse:
            String(localized: "The model's answer could not be read.")
        case .imageEncodingFailed:
            String(localized: "The photo could not be prepared for analysis.")
        case .notEnoughItems:
            String(localized: "Add a few more items before asking for outfits.")
        }
    }
}

// MARK: - Shared HTTP plumbing

enum AIHTTP {
    static func postJSON(
        url: URL,
        body: [String: Any],
        headers: [String: String],
        timeout: TimeInterval = 90
    ) async throws -> [String: Any] {
        var request = URLRequest(url: url, timeoutInterval: timeout)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        for (field, value) in headers { request.setValue(value, forHTTPHeaderField: field) }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else {
            throw AIError.http(status: status, message: errorMessage(from: data))
        }
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw AIError.malformedResponse(String(data: data, encoding: .utf8) ?? "")
        }
        return json
    }

    /// Digs the human readable reason out of the various error envelopes.
    private static func errorMessage(from data: Data) -> String {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return String(data: data, encoding: .utf8)?.prefix(200).description ?? ""
        }
        if let error = json["error"] as? [String: Any] {
            if let message = error["message"] as? String { return message }
            if let message = error["type"] as? String { return message }
        }
        if let message = json["message"] as? String { return message }
        return ""
    }

    /// Pulls the first JSON object out of a chatty reply that may be fenced.
    static func decodeJSONObject(from text: String) throws -> [String: Any] {
        var cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if cleaned.hasPrefix("```") {
            cleaned = cleaned
                .replacingOccurrences(of: "```json", with: "")
                .replacingOccurrences(of: "```", with: "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }
        guard let start = cleaned.firstIndex(of: "{"), let end = cleaned.lastIndex(of: "}") else {
            throw AIError.malformedResponse(text)
        }
        let slice = String(cleaned[start...end])
        guard let data = slice.data(using: .utf8),
              let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw AIError.malformedResponse(text)
        }
        return json
    }

    static func decode<T: Decodable>(_ type: T.Type, from json: [String: Any]) throws -> T {
        let data = try JSONSerialization.data(withJSONObject: json)
        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            throw AIError.malformedResponse(String(data: data, encoding: .utf8) ?? "")
        }
    }
}
