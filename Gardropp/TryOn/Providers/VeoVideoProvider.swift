import Foundation
import UIKit

/// Veo animates the try-on still into a turnaround. The job is long-running, so
/// the request returns an operation name that gets polled until the clip is ready.
struct VeoVideoProvider: TryOnVideoProvider {
    let apiKey: String

    func animate(still: UIImage, model: String, seconds: Int) async throws -> Data {
        guard !apiKey.isEmpty else { throw TryOnError.missingKey("Gemini") }
        guard let start = URL(string: "https://generativelanguage.googleapis.com/v1beta/models/\(model):predictLongRunning"),
              let base64 = still.base64ForUpload(maxEdge: 1280) else {
            throw AIError.imageEncodingFailed
        }

        let started = try await AIHTTP.postJSON(
            url: start,
            body: [
                "instances": [[
                    "prompt": TryOnPrompts.turnaround,
                    "image": ["inlineData": ["mimeType": "image/jpeg", "data": base64]]
                ]],
                "parameters": [
                    "aspectRatio": "9:16",
                    "durationSeconds": "\(seconds)",
                    "resolution": "720p"
                ]
            ],
            headers: ["x-goog-api-key": apiKey],
            timeout: 120
        )
        guard let operation = started["name"] as? String else {
            throw TryOnError.noOutput(TryOnJSON.firstText(in: started) ?? "")
        }
        guard let pollURL = URL(string: "https://generativelanguage.googleapis.com/v1beta/\(operation)") else {
            throw TryOnError.noOutput("")
        }

        for _ in 0..<90 {
            try? await Task.sleep(for: .seconds(4))
            let status = try await AIHTTP.getJSON(url: pollURL, headers: ["x-goog-api-key": apiKey])
            if let error = status["error"] {
                throw TryOnError.noOutput(TryOnJSON.firstText(in: error) ?? "")
            }
            guard (status["done"] as? Bool) == true else { continue }

            guard let file = TryOnJSON.firstFileURL(in: status, extensions: [".mp4", ".webm", ".mov"]) else {
                throw TryOnError.noOutput(TryOnJSON.firstText(in: status) ?? "")
            }
            return try await AIHTTP.download(url: file, headers: ["x-goog-api-key": apiKey], timeout: 300)
        }
        throw TryOnError.noOutput(String(localized: "The clip took too long."))
    }
}
