import Foundation
import UIKit

/// IDM-VTON through fal's synchronous endpoint. Like FASHN it fits one garment
/// at a time, so the look is layered piece by piece.
struct FalTryOnProvider: TryOnStillProvider {
    let apiKey: String

    func fit(person: UIImage, garments: [TryOnGarment], model: String) async throws -> UIImage {
        guard !apiKey.isEmpty else { throw TryOnError.missingKey("fal") }
        guard !garments.isEmpty else { throw TryOnError.noGarments }
        guard let url = URL(string: "https://fal.run/\(model)") else {
            throw AIError.malformedResponse("Invalid model name")
        }

        var current = person
        for garment in garments {
            guard let personURI = current.dataURI(), let garmentURI = garment.image.dataURI(maxEdge: 1024) else {
                throw AIError.imageEncodingFailed
            }
            let json = try await AIHTTP.postJSON(
                url: url,
                body: [
                    "human_image_url": personURI,
                    "garment_image_url": garmentURI,
                    "description": "\(garment.name), \(garment.category.title)"
                ],
                headers: ["Authorization": "Key \(apiKey)"],
                timeout: 240
            )
            guard let output = TryOnJSON.firstFileURL(in: json, extensions: [".png", ".jpg", ".jpeg", ".webp"]) else {
                throw TryOnError.noOutput(TryOnJSON.firstText(in: json) ?? "")
            }
            let data = try await AIHTTP.download(url: output)
            guard let image = UIImage(data: data) else { throw TryOnError.noOutput("") }
            current = image
        }
        return current
    }
}

/// Kling on fal, animating the finished still.
struct FalVideoProvider: TryOnVideoProvider {
    let apiKey: String

    func animate(still: UIImage, model: String, seconds: Int) async throws -> Data {
        guard !apiKey.isEmpty else { throw TryOnError.missingKey("fal") }
        guard let url = URL(string: "https://fal.run/\(model)"), let imageURI = still.dataURI() else {
            throw AIError.imageEncodingFailed
        }

        let json = try await AIHTTP.postJSON(
            url: url,
            body: [
                "prompt": TryOnPrompts.turnaround,
                "image_url": imageURI,
                "duration": "\(seconds)"
            ],
            headers: ["Authorization": "Key \(apiKey)"],
            timeout: 600
        )
        guard let output = TryOnJSON.firstFileURL(in: json, extensions: [".mp4", ".webm", ".mov"]) else {
            throw TryOnError.noOutput(TryOnJSON.firstText(in: json) ?? "")
        }
        return try await AIHTTP.download(url: output)
    }
}

enum TryOnPrompts {
    static let turnaround = """
    The person slowly turns around on the spot to show the outfit from every side, \
    then faces the camera again. Steady camera, plain studio background, soft lighting, \
    fashion lookbook footage. Keep the person and the clothes exactly as they are.
    """
}
