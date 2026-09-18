import SwiftUI

/// The build of the stand-in body that carries your face in every try-on.
enum BodyBuild: String, CaseIterable, Identifiable, Codable {
    case slim, average, athletic, curvy

    var id: String { rawValue }

    var title: LocalizedStringKey {
        switch self {
        case .slim: "Slim"
        case .average: "Average"
        case .athletic: "Athletic"
        case .curvy: "Curvy"
        }
    }

    var promptPhrase: String {
        switch self {
        case .slim: "a slim, slender build"
        case .average: "an average, everyday build"
        case .athletic: "an athletic, toned build"
        case .curvy: "a curvy build"
        }
    }
}

/// Everything needed to draw the stand-in body.
struct BodySpec {
    var heightCM: Int
    var build: BodyBuild

    static let `default` = BodySpec(heightCM: 160, build: .average)

    /// Height reads as a silhouette cue to an image model rather than a
    /// measurement, so it is phrased the way a photographer would say it.
    var heightPhrase: String {
        switch heightCM {
        case ..<155: "petite, roughly \(heightCM) cm tall, short stature with proportionally short legs"
        case 155..<168: "petite to average, roughly \(heightCM) cm tall"
        case 168..<180: "average to tall, roughly \(heightCM) cm tall"
        default: "tall, roughly \(heightCM) cm tall with long legs"
        }
    }

    /// The one prompt that defines the stand-in. Kept stable on purpose: the
    /// same words plus the same face give the same person every time.
    var basePrompt: String {
        """
        Create a single full-body studio photograph of one person.

        Face: use the face in the provided image exactly as it is. Keep the same features, \
        skin tone, hair colour and hairstyle, and facial proportions. The result must be \
        recognisable as that person. Neutral, relaxed expression.

        Body: \(heightPhrase), with \(build.promptPhrase). Realistic, natural human proportions \
        for that height.

        Pose: standing straight and squarely facing the camera, arms relaxed at the sides, \
        feet together, whole body visible from the top of the head to the feet.

        Clothing: plain, close-fitting light grey basics — a simple short-sleeved top and \
        plain leggings — plus plain white trainers. Nothing patterned, no logos, no jacket.

        Setting: seamless light grey studio backdrop, soft even frontal lighting, no harsh \
        shadows, sharp focus, photorealistic, vertical framing.

        Return only the photograph.
        """
    }
}
