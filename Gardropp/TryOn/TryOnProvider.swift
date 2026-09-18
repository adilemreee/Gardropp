import Foundation
import UIKit

/// One garment being fitted, already flattened for upload.
struct TryOnGarment {
    var image: UIImage
    var category: ItemCategory
    var name: String
}

protocol TryOnStillProvider {
    /// Fits `garments` onto `person` and returns the resulting photo.
    func fit(person: UIImage, garments: [TryOnGarment], model: String) async throws -> UIImage
}

protocol TryOnVideoProvider {
    /// Animates a finished try-on still into a short clip, returned as file data.
    func animate(still: UIImage, model: String, seconds: Int) async throws -> Data
}

enum TryOnError: LocalizedError {
    case missingPersonPhoto
    case missingKey(String)
    case noGarments
    case noOutput(String)

    var errorDescription: String? {
        switch self {
        case .missingPersonPhoto:
            String(localized: "Add a photo of yourself in Profile first.")
        case .missingKey(let name):
            String(localized: "Add your \(name) API key to use it.")
        case .noGarments:
            String(localized: "This outfit has nothing this engine can fit.")
        case .noOutput(let detail):
            detail.isEmpty ? String(localized: "The engine returned no image.") : detail
        }
    }
}

// MARK: - Shared plumbing

extension AIHTTP {
    static func getJSON(url: URL, headers: [String: String], timeout: TimeInterval = 60) async throws -> [String: Any] {
        var request = URLRequest(url: url, timeoutInterval: timeout)
        for (field, value) in headers { request.setValue(value, forHTTPHeaderField: field) }
        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else {
            throw AIError.http(status: status, message: String(data: data, encoding: .utf8)?.prefix(200).description ?? "")
        }
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw AIError.malformedResponse("")
        }
        return json
    }

    static func download(url: URL, headers: [String: String] = [:], timeout: TimeInterval = 180) async throws -> Data {
        var request = URLRequest(url: url, timeoutInterval: timeout)
        for (field, value) in headers { request.setValue(value, forHTTPHeaderField: field) }
        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else {
            throw AIError.http(status: status, message: "")
        }
        return data
    }
}

extension UIImage {
    /// `data:` URI, which every try-on service accepts in place of a hosted file.
    func dataURI(maxEdge: CGFloat = 1280, quality: CGFloat = 0.9) -> String? {
        guard let base64 = base64ForUpload(maxEdge: maxEdge, quality: quality) else { return nil }
        return "data:image/jpeg;base64,\(base64)"
    }
}
