import Foundation
import Observation
import UIKit

/// Builds the stand-in: your face on a consistent body, made once and reused by
/// every try-on so you are the same person in every look.
@MainActor
@Observable
final class ModelBuilder {
    private(set) var isBuilding = false
    private(set) var errorMessage: String?

    /// The stand-in is always drawn by Gemini's image model — it is the only one
    /// of the engines that can invent a body, and it is the cheapest of them.
    static let engine = TryOnEngine.gemini

    func build(face: UIImage, spec: BodySpec, settings: TryOnSettings) async -> UIImage? {
        isBuilding = true
        errorMessage = nil
        defer { isBuilding = false }

        do {
            guard let faceData = face.resized(maxEdge: 1024).base64ForUpload(maxEdge: 1024) else {
                throw AIError.imageEncodingFailed
            }
            return try await GeminiTryOnProvider.generateImage(
                apiKey: settings.apiKey(for: Self.engine.keychainAccount),
                model: settings.model(for: Self.engine),
                prompt: spec.basePrompt,
                imagesBase64: [faceData]
            )
        } catch {
            errorMessage = error.localizedDescription
            return nil
        }
    }
}
