import Foundation
import SwiftUI

/// Engines that put an outfit onto a photo of you.
enum TryOnEngine: String, CaseIterable, Identifiable, Codable {
    case gemini
    case fashn
    case idmVton

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .gemini: "Gemini"
        case .fashn: "FASHN"
        case .idmVton: "IDM-VTON"
        }
    }

    var blurb: LocalizedStringKey {
        switch self {
        case .gemini: "Dresses you in the whole outfit in one go — the cheapest option, and it uses the Gemini key you may already have."
        case .fashn: "Built for try-on, so fabric and print stay truest. One garment per call, so a full look costs a few runs."
        case .idmVton: "Open try-on model running on fal. One garment per call."
        }
    }

    /// Gemini takes every garment in a single request; the try-on models fit one
    /// piece at a time, so a look is built by feeding each result into the next.
    var fitsWholeOutfitAtOnce: Bool { self == .gemini }

    /// Only tops, bottoms and one-pieces are supported by the dedicated models.
    var supportedCategories: Set<ItemCategory> {
        switch self {
        case .gemini: Set(ItemCategory.allCases)
        case .fashn, .idmVton: [.tops, .bottoms, .dresses, .outerwear]
        }
    }

    var keychainAccount: String {
        switch self {
        // Reuses the Gemini key from the AI engine settings.
        case .gemini: AIProviderKind.gemini.keychainAccount
        case .fashn: "apikey.fashn"
        case .idmVton: "apikey.fal"
        }
    }

    var defaultModel: String {
        switch self {
        case .gemini: "gemini-3.1-flash-lite-image"
        case .fashn: "tryon-v1.6"
        case .idmVton: "fal-ai/idm-vton"
        }
    }

    var suggestedModels: [String] {
        switch self {
        case .gemini: ["gemini-3.1-flash-lite-image", "gemini-3.1-flash-image", "gemini-3-pro-image"]
        case .fashn: ["tryon-v1.6", "tryon-max"]
        case .idmVton: ["fal-ai/idm-vton"]
        }
    }

    /// Rough published price for one garment fitting, shown before you spend.
    func approximateCost(model: String) -> String {
        switch self {
        case .gemini:
            if model.contains("pro") { return "$0.13" }
            if model.contains("lite") { return "$0.03" }
            return "$0.07"
        case .fashn: return "$0.08"
        case .idmVton: return "$0.07"
        }
    }

    var consoleURL: URL? {
        switch self {
        case .gemini: URL(string: "https://aistudio.google.com/apikey")
        case .fashn: URL(string: "https://app.fashn.ai/api")
        case .idmVton: URL(string: "https://fal.ai/dashboard/keys")
        }
    }
}

/// Engines that turn the finished try-on still into a short turnaround clip.
enum TryOnVideoEngine: String, CaseIterable, Identifiable, Codable {
    case veo
    case kling

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .veo: "Veo"
        case .kling: "Kling"
        }
    }

    var blurb: LocalizedStringKey {
        switch self {
        case .veo: "Google's Veo, through the same Gemini key."
        case .kling: "Kling on fal, through the same fal key."
        }
    }

    var keychainAccount: String {
        switch self {
        case .veo: AIProviderKind.gemini.keychainAccount
        case .kling: "apikey.fal"
        }
    }

    var defaultModel: String {
        switch self {
        case .veo: "veo-3.1-lite-generate-preview"
        case .kling: "fal-ai/kling-video/v2.1/standard/image-to-video"
        }
    }

    var suggestedModels: [String] {
        switch self {
        case .veo: ["veo-3.1-lite-generate-preview", "veo-3.1-generate-preview"]
        case .kling: [
            "fal-ai/kling-video/v2.1/standard/image-to-video",
            "fal-ai/kling-video/v2.6/pro/image-to-video",
            "fal-ai/kling-video/v3/turbo/pro/image-to-video"
        ]
        }
    }

    /// Video is priced per second; this is the cost of the app's 4 second clip.
    func approximateCost(model: String) -> String {
        switch self {
        case .veo: model.contains("lite") ? "$0.20" : "$1.60"
        case .kling: model.contains("v3") ? "$0.56" : "$0.20"
        }
    }

    var consoleURL: URL? {
        switch self {
        case .veo: URL(string: "https://aistudio.google.com/apikey")
        case .kling: URL(string: "https://fal.ai/dashboard/keys")
        }
    }
}

/// What the user asked for.
enum TryOnMode: String, CaseIterable, Identifiable, Codable {
    case still
    case video

    var id: String { rawValue }

    var title: LocalizedStringKey {
        switch self {
        case .still: "Single frame"
        case .video: "Video"
        }
    }
}
