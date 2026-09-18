import Foundation
import UIKit
import Vision

/// Works with no API key and no network: Vision classifies the garment,
/// `ColorAnalyzer` reads its colour, and a rule engine builds the outfits.
/// It is also the safety net whenever a cloud provider fails.
///
/// Vision's general classifier has no "t-shirt" or "trousers" label — its
/// clothing vocabulary stops at `clothing`, `textile`, `jeans`, `hoodie`,
/// `polo`, `jacket`, `sneaker` and friends — so the guess combines every
/// matching label's confidence and falls back to the garment's proportions.
struct OnDeviceProvider: AIProvider {
    let kind: AIProviderKind = .onDevice
    let model = ""

    func analyzeGarment(image: UIImage, context: AnalysisContext) async throws -> GarmentAnalysis {
        let swatch = ColorAnalyzer.dominantSwatch(of: image)
        async let guessTask = classify(image, shape: context.shape)
        async let brandTask = readBrand(image)
        let (guess, brand) = await (guessTask, brandTask)

        // Turkish lowercasing differs from English ("I" → "ı"), so go through the locale.
        let name = "\(swatch.name) \(guess.subcategory.lowercased(with: .current))"

        return GarmentAnalysis(
            name: name.trimmingCharacters(in: .whitespaces),
            category: guess.category.rawValue,
            subcategory: guess.subcategory,
            brand: brand,
            colorName: swatch.name,
            colorHex: swatch.hex,
            style: guess.style.rawValue,
            seasons: seasons(for: guess.category).map(\.rawValue),
            material: nil,
            confidence: guess.confidence
        )
    }

    func suggestOutfits(_ request: OutfitRequest) async throws -> [OutfitSuggestionDTO] {
        LocalOutfitEngine.suggest(request)
    }

    // MARK: - Classification

    private struct Guess {
        var category: ItemCategory
        var subcategory: String
        var style: StyleTag
        var confidence: Double
    }

    /// Identifier → what it means. Only labels Vision actually knows are listed.
    private static let vocabulary: [(identifier: String, category: ItemCategory, key: String.LocalizationValue, style: StyleTag)] = [
        ("sneaker", .footwear, "Sneakers", .sport),
        ("ski_boot", .footwear, "Boots", .sport),
        ("snowshoe", .footwear, "Boots", .sport),
        ("boot", .footwear, "Boots", .casual),
        ("sandal", .footwear, "Sandals", .casual),
        ("high_heel", .footwear, "Heels", .party),
        ("shoes", .footwear, "Shoes", .smart),
        ("footwear", .footwear, "Shoes", .casual),
        ("jeans", .bottoms, "Jeans", .casual),
        ("hoodie", .tops, "Hoodies", .street),
        ("polo", .tops, "Polos", .smart),
        ("wedding_dress", .dresses, "Dresses", .formal),
        ("swimsuit", .dresses, "Swimwear", .casual),
        ("wetsuit", .dresses, "Swimwear", .sport),
        ("bathrobe", .outerwear, "Robes", .casual),
        ("lab_coat", .outerwear, "Coats", .smart),
        ("jacket", .outerwear, "Jackets", .casual),
        ("suit", .outerwear, "Suits", .formal),
        ("military_uniform", .outerwear, "Uniforms", .formal),
        ("safety_vest", .outerwear, "Vests", .sport),
        ("lifejacket", .outerwear, "Vests", .sport),
        ("baseball_hat", .accessories, "Hats", .street),
        ("cowboy_hat", .accessories, "Hats", .casual),
        ("sunhat", .accessories, "Hats", .casual),
        ("hardhat", .accessories, "Hats", .sport),
        ("hat", .accessories, "Hats", .casual),
        ("necktie", .accessories, "Ties", .formal),
        ("bowtie", .accessories, "Ties", .formal),
        ("scarf", .accessories, "Scarves", .casual),
        ("glove", .accessories, "Gloves", .casual),
        ("sock", .accessories, "Socks", .casual),
        ("suitcase", .accessories, "Bags", .casual),
        ("paper_bag", .accessories, "Bags", .casual),
        ("bag", .accessories, "Bags", .casual)
    ]

    /// Generic labels that only say "this is a piece of clothing".
    private static let genericIdentifiers: Set<String> = ["clothing", "textile", "costume", "clothesline"]

    private func classify(_ image: UIImage, shape: GarmentShape?) async -> Guess {
        guard let cgImage = image.cgImage else { return fallbackGuess(shape: shape, confidence: 0.2) }

        let results: [(String, Double)] = await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let request = VNClassifyImageRequest()
                let handler = VNImageRequestHandler(cgImage: cgImage, orientation: .up)
                try? handler.perform([request])
                let rows = (request.results ?? [])
                    .filter { $0.confidence > 0.02 }
                    .map { ($0.identifier.lowercased(), Double($0.confidence)) }
                continuation.resume(returning: rows)
            }
        }

        // Add up every specific label that points at the same garment type.
        var scores: [String: (score: Double, entry: (identifier: String, category: ItemCategory, key: String.LocalizationValue, style: StyleTag))] = [:]
        var genericSignal = 0.0

        for (identifier, confidence) in results {
            if Self.genericIdentifiers.contains(identifier) {
                genericSignal += confidence
                continue
            }
            guard let entry = Self.vocabulary.first(where: { identifier.contains($0.identifier) }) else { continue }
            let key = "\(entry.category.rawValue)|\(entry.identifier)"
            scores[key] = ((scores[key]?.score ?? 0) + confidence, entry)
        }

        if let best = scores.values.max(by: { $0.score < $1.score }), best.score >= 0.05 {
            return Guess(
                category: best.entry.category,
                subcategory: String(localized: best.entry.key),
                style: best.entry.style,
                confidence: min(1, best.score)
            )
        }

        // Nothing specific: the outline is the only clue left.
        return fallbackGuess(shape: shape, confidence: genericSignal > 0.08 ? 0.45 : 0.25)
    }

    /// Reads the silhouette: a bottom edge split in two is a pair of legs, wide
    /// and bottom-heavy is footwear, and everything else is a top. When no
    /// outline could be measured, the photo's own proportions are all that is left.
    private func fallbackGuess(shape: GarmentShape?, confidence: Double) -> Guess {
        func guess(_ category: ItemCategory, _ subcategory: String.LocalizationValue, _ certainty: Double) -> Guess {
            Guess(
                category: category,
                subcategory: String(localized: subcategory),
                style: .casual,
                confidence: certainty
            )
        }

        guard let shape else { return guess(.tops, "Top", confidence * 0.8) }

        if shape.isReliable {
            if shape.hasLegSplit, shape.aspect < 1.8 {
                // Wide legs mean shorts, long ones mean trousers.
                return guess(.bottoms, shape.aspect > 0.75 ? "Shorts" : "Trousers", confidence)
            }
            if shape.aspect > 1.25, shape.lowerMass > 0.52 {
                return guess(.footwear, "Shoes", confidence)
            }
            if shape.aspect < 0.5 {
                return guess(.bottoms, "Trousers", confidence)
            }
            return guess(.tops, "Top", confidence)
        }

        // Only the framing to go on, so keep it coarse and less certain.
        let weaker = confidence * 0.8
        if shape.imageAspect > 1.3 { return guess(.footwear, "Shoes", weaker) }
        if shape.imageAspect < 0.45 { return guess(.bottoms, "Trousers", weaker) }
        return guess(.tops, "Top", weaker)
    }

    // MARK: - Brand

    /// Reads a brand only when the print is unambiguous. A stylised logo tends
    /// to come back as confident-looking nonsense, so the bar is deliberately high.
    private func readBrand(_ image: UIImage) async -> String? {
        guard let cgImage = image.cgImage else { return nil }

        let candidates: [(String, Double)] = await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let request = VNRecognizeTextRequest()
                request.recognitionLevel = .accurate
                request.usesLanguageCorrection = false
                try? VNImageRequestHandler(cgImage: cgImage, orientation: .up).perform([request])
                let rows = (request.results ?? []).compactMap { observation -> (String, Double)? in
                    guard let best = observation.topCandidates(1).first else { return nil }
                    return (best.string, Double(best.confidence))
                }
                continuation.resume(returning: rows)
            }
        }

        let noise: Set<String> = [
            "xs", "s", "m", "l", "xl", "xxl", "size", "cotton", "polyester", "wool",
            "made", "in", "china", "italy", "turkey", "portugal", "wash", "care", "eu", "us", "uk"
        ]

        return candidates
            .filter { text, confidence in
                let word = text.trimmingCharacters(in: .whitespacesAndNewlines)
                return confidence >= 0.8
                    && word.count >= 3 && word.count <= 14
                    && !word.contains(" ")
                    && word.allSatisfy { $0.isLetter }
                    && !noise.contains(word.lowercased())
            }
            .max { $0.1 < $1.1 }
            .map { $0.0.trimmingCharacters(in: .whitespacesAndNewlines).capitalized }
    }

    private func seasons(for category: ItemCategory) -> [Season] {
        switch category {
        case .outerwear: [.autumn, .winter]
        case .dresses: [.spring, .summer]
        default: Season.allCases
        }
    }
}
