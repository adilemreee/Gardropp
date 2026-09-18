import Foundation
import UIKit

/// FASHN fits one garment per call, so a full look is built by feeding each
/// result back in as the model image for the next piece.
struct FashnTryOnProvider: TryOnStillProvider {
    let apiKey: String

    private static let runURL = URL(string: "https://api.fashn.ai/v1/run")!
    private static let statusURL = "https://api.fashn.ai/v1/status/"

    func fit(person: UIImage, garments: [TryOnGarment], model: String) async throws -> UIImage {
        guard !apiKey.isEmpty else { throw TryOnError.missingKey("FASHN") }
        guard !garments.isEmpty else { throw TryOnError.noGarments }

        var current = person
        for garment in garments {
            current = try await fitOne(person: current, garment: garment, model: model)
        }
        return current
    }

    private func fitOne(person: UIImage, garment: TryOnGarment, model: String) async throws -> UIImage {
        guard let personURI = person.dataURI(), let garmentURI = garment.image.dataURI(maxEdge: 1024) else {
            throw AIError.imageEncodingFailed
        }

        let started = try await AIHTTP.postJSON(
            url: Self.runURL,
            body: [
                "model_name": model,
                "inputs": [
                    "model_image": personURI,
                    "garment_image": garmentURI,
                    "category": category(for: garment.category)
                ]
            ],
            headers: ["Authorization": "Bearer \(apiKey)"],
            timeout: 120
        )
        guard let id = started["id"] as? String else {
            throw TryOnError.noOutput(TryOnJSON.firstText(in: started) ?? "")
        }

        // Fittings take a few seconds; poll until the job reports back.
        for _ in 0..<60 {
            try? await Task.sleep(for: .seconds(2))
            guard let url = URL(string: Self.statusURL + id) else { break }
            let status = try await AIHTTP.getJSON(url: url, headers: ["Authorization": "Bearer \(apiKey)"])

            switch status["status"] as? String {
            case "completed":
                guard let output = TryOnJSON.firstFileURL(in: status["output"] ?? [:], extensions: [".png", ".jpg", ".jpeg", ".webp"]) else {
                    throw TryOnError.noOutput("")
                }
                let data = try await AIHTTP.download(url: output)
                guard let image = UIImage(data: data) else { throw TryOnError.noOutput("") }
                return image
            case "failed":
                throw TryOnError.noOutput(TryOnJSON.firstText(in: status) ?? "")
            default:
                continue
            }
        }
        throw TryOnError.noOutput(String(localized: "The fitting took too long."))
    }

    private func category(for category: ItemCategory) -> String {
        switch category {
        case .tops, .outerwear: "tops"
        case .bottoms: "bottoms"
        case .dresses: "one-pieces"
        default: "auto"
        }
    }
}
