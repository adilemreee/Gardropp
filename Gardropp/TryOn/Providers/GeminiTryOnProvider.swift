import Foundation
import UIKit

/// Gemini's image models edit a photo from instructions, so the whole outfit
/// goes in one request: your photo first, then every garment.
struct GeminiTryOnProvider: TryOnStillProvider {
    let apiKey: String

    func fit(person: UIImage, garments: [TryOnGarment], model: String) async throws -> UIImage {
        guard !apiKey.isEmpty else { throw TryOnError.missingKey("Gemini") }
        guard !garments.isEmpty else { throw TryOnError.noGarments }
        guard let personData = person.base64ForUpload(maxEdge: 1280) else { throw AIError.imageEncodingFailed }

        var images = [personData]
        images.append(contentsOf: garments.compactMap { $0.image.base64ForUpload(maxEdge: 1024) })

        return try await Self.generateImage(
            apiKey: apiKey,
            model: model,
            prompt: prompt(for: garments),
            imagesBase64: images
        )
    }

    /// One text prompt plus any number of reference images, one image back.
    static func generateImage(
        apiKey: String,
        model: String,
        prompt: String,
        imagesBase64: [String]
    ) async throws -> UIImage {
        guard !apiKey.isEmpty else { throw TryOnError.missingKey("Gemini") }
        guard let url = URL(string: "https://generativelanguage.googleapis.com/v1beta/models/\(model):generateContent") else {
            throw AIError.malformedResponse("Invalid model name")
        }

        var parts: [[String: Any]] = [["text": prompt]]
        for data in imagesBase64 {
            parts.append(["inline_data": ["mime_type": "image/jpeg", "data": data]])
        }

        let json = try await AIHTTP.postJSON(
            url: url,
            body: ["contents": [["role": "user", "parts": parts]]],
            headers: ["x-goog-api-key": apiKey],
            timeout: 180
        )

        guard let base64 = TryOnJSON.firstInlineImage(in: json),
              let data = Data(base64Encoded: base64),
              let image = UIImage(data: data) else {
            throw TryOnError.noOutput(TryOnJSON.firstText(in: json) ?? "")
        }
        return image
    }

    private func prompt(for garments: [TryOnGarment]) -> String {
        let list = garments.map { "\($0.name) (\($0.category.title))" }.joined(separator: ", ")
        return """
        The first image is a photo of a person. The images after it are garments: \(list).
        Produce a single photorealistic full-body image of that same person wearing all of those garments together.
        Keep their face, hair, skin tone, body proportions and pose recognisably the same — this must still look like them.
        Replace whatever they are currently wearing. Keep each garment's exact colour, pattern, print and cut.
        Plain neutral studio background, soft even lighting, sharp focus, vertical framing.
        Return only the image.
        """
    }
}

/// The try-on services differ in small ways between versions, so results are
/// read by searching the response rather than by assuming one exact shape.
enum TryOnJSON {
    static func firstInlineImage(in json: Any) -> String? {
        if let object = json as? [String: Any] {
            for key in ["inlineData", "inline_data"] {
                if let inline = object[key] as? [String: Any], let data = inline["data"] as? String {
                    return data
                }
            }
            for value in object.values {
                if let found = firstInlineImage(in: value) { return found }
            }
        }
        if let array = json as? [Any] {
            for value in array {
                if let found = firstInlineImage(in: value) { return found }
            }
        }
        return nil
    }

    /// First http(s) link that looks like a produced file.
    static func firstFileURL(in json: Any, extensions: [String]) -> URL? {
        if let object = json as? [String: Any] {
            for key in ["url", "uri", "video_url", "image_url"] {
                if let text = object[key] as? String, let url = candidate(text, extensions) { return url }
            }
            for value in object.values {
                if let found = firstFileURL(in: value, extensions: extensions) { return found }
            }
        }
        if let array = json as? [Any] {
            for value in array {
                if let found = firstFileURL(in: value, extensions: extensions) { return found }
            }
        }
        if let text = json as? String { return candidate(text, extensions) }
        return nil
    }

    private static func candidate(_ text: String, _ extensions: [String]) -> URL? {
        guard text.hasPrefix("http") else { return nil }
        let lowered = text.lowercased()
        let matches = extensions.contains { lowered.contains($0) } || lowered.contains("/files/")
        return matches ? URL(string: text) : nil
    }

    static func firstText(in json: Any) -> String? {
        if let object = json as? [String: Any] {
            if let message = object["message"] as? String { return message }
            if let error = object["error"] as? String { return error }
            if let text = object["text"] as? String { return text }
            for value in object.values {
                if let found = firstText(in: value) { return found }
            }
        }
        if let array = json as? [Any] {
            for value in array {
                if let found = firstText(in: value) { return found }
            }
        }
        return nil
    }
}
