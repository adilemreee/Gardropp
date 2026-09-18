import UIKit
import Vision

/// Shop pages carry several photos of the same product: the garment laid flat,
/// and the same garment on a model. The flat one crops and analyses far better,
/// so this picks it out of the candidates.
enum GarmentImagePicker {

    /// Highest scoring image, preferring garment-only shots.
    static func best(of images: [UIImage]) async -> UIImage? {
        guard images.count > 1 else { return images.first }

        var best: (image: UIImage, score: Double)?
        for image in images {
            let score = await score(image)
            if best == nil || score > best!.score {
                best = (image, score)
            }
        }
        return best?.image
    }

    /// 0...1, higher means "more likely to be just the garment".
    static func score(_ image: UIImage) async -> Double {
        var score = 0.5

        // A detected person is the strongest signal there is.
        if await containsPerson(image) {
            score -= 0.45
        }

        // Vision cannot always run — visible skin is a cheap second opinion,
        // and it is the thing that actually distinguishes the two shots.
        let skin = skinFraction(image)
        score -= min(0.4, skin * 3.0)

        // Packshots sit on a clean, even backdrop.
        score += uniformBackgroundBonus(image)

        return score
    }

    // MARK: - Signals

    private static func containsPerson(_ image: UIImage) async -> Bool {
        guard let cgImage = image.cgImage else { return false }
        return await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let people = VNDetectHumanRectanglesRequest()
                let faces = VNDetectFaceRectanglesRequest()
                let handler = VNImageRequestHandler(cgImage: cgImage, orientation: .up)
                try? handler.perform([people, faces])

                let hasPerson = (people.results ?? []).contains { $0.confidence > 0.5 }
                    || !(faces.results ?? []).isEmpty
                continuation.resume(returning: hasPerson)
            }
        }
    }

    /// Share of pixels that look like skin, in the loose HSB range photographs
    /// of people fall into.
    private static func skinFraction(_ image: UIImage) -> Double {
        let side = 48
        guard let cgImage = image.cgImage else { return 0 }
        var raw = [UInt8](repeating: 0, count: side * side * 4)
        guard let context = CGContext(
            data: &raw, width: side, height: side, bitsPerComponent: 8,
            bytesPerRow: side * 4, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return 0 }
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: side, height: side))

        var skin = 0
        let total = side * side
        for index in stride(from: 0, to: raw.count, by: 4) {
            let r = Double(raw[index]) / 255
            let g = Double(raw[index + 1]) / 255
            let b = Double(raw[index + 2]) / 255

            var hue: CGFloat = 0, saturation: CGFloat = 0, brightness: CGFloat = 0, alpha: CGFloat = 0
            UIColor(red: r, green: g, blue: b, alpha: 1)
                .getHue(&hue, saturation: &saturation, brightness: &brightness, alpha: &alpha)
            let degrees = Double(hue) * 360

            let looksLikeSkin = degrees >= 5 && degrees <= 45
                && saturation >= 0.15 && saturation <= 0.62
                && brightness >= 0.32 && brightness <= 0.97
                && r > b
            if looksLikeSkin { skin += 1 }
        }
        return Double(skin) / Double(total)
    }

    /// How close the border pixels are to a single flat colour.
    private static func uniformBackgroundBonus(_ image: UIImage) -> Double {
        let side = 40
        guard let cgImage = image.cgImage else { return 0 }
        var raw = [UInt8](repeating: 0, count: side * side * 4)
        guard let context = CGContext(
            data: &raw, width: side, height: side, bitsPerComponent: 8,
            bytesPerRow: side * 4, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return 0 }
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: side, height: side))

        var samples: [(Double, Double, Double)] = []
        let margin = 3
        for y in 0..<side {
            for x in 0..<side where x < margin || y < margin || x >= side - margin || y >= side - margin {
                let index = (y * side + x) * 4
                samples.append((Double(raw[index]) / 255, Double(raw[index + 1]) / 255, Double(raw[index + 2]) / 255))
            }
        }
        guard !samples.isEmpty else { return 0 }

        let count = Double(samples.count)
        let mean = samples.reduce((0.0, 0.0, 0.0)) { ($0.0 + $1.0, $0.1 + $1.1, $0.2 + $1.2) }
        let average = (mean.0 / count, mean.1 / count, mean.2 / count)
        let variance = samples.reduce(0.0) { total, sample in
            let dr = sample.0 - average.0, dg = sample.1 - average.1, db = sample.2 - average.2
            return total + (dr * dr + dg * dg + db * db)
        } / count

        return variance < 0.004 ? 0.2 : (variance < 0.02 ? 0.1 : 0)
    }
}
