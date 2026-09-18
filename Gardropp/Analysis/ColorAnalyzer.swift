import UIKit

/// Finds the garment's dominant colour.
///
/// When the subject was cut out, transparent pixels are simply skipped. When it
/// was not — the mask can fail on a busy photo — the border of the image is
/// treated as background and excluded, and pixels near the centre count for
/// more, because that is where the garment is.
enum ColorAnalyzer {

    struct Swatch {
        let hex: String
        let family: ColorFamily
        /// Human readable name such as "Olive green".
        let name: String
    }

    static func dominantSwatch(of image: UIImage) -> Swatch {
        guard let rgb = dominantRGB(of: image) else {
            return Swatch(hex: "#808080", family: .grey, name: ColorFamily.grey.title)
        }
        let hex = String(format: "#%02X%02X%02X", Int(rgb.r * 255), Int(rgb.g * 255), Int(rgb.b * 255))
        let family = family(forR: rgb.r, g: rgb.g, b: rgb.b)
        return Swatch(hex: hex, family: family, name: family.title)
    }

    private struct Pixel {
        var r = 0.0, g = 0.0, b = 0.0
    }

    private static func dominantRGB(of image: UIImage) -> (r: Double, g: Double, b: Double)? {
        let side = 64
        guard let cgImage = image.cgImage else { return nil }
        var raw = [UInt8](repeating: 0, count: side * side * 4)
        guard let context = CGContext(
            data: &raw,
            width: side,
            height: side,
            bitsPerComponent: 8,
            bytesPerRow: side * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: side, height: side))

        var pixels = [(pixel: Pixel, x: Int, y: Int)]()
        pixels.reserveCapacity(side * side)
        var opaqueCount = 0

        for y in 0..<side {
            for x in 0..<side {
                let index = (y * side + x) * 4
                let alpha = Double(raw[index + 3]) / 255
                guard alpha > 0.6 else { continue }
                opaqueCount += 1
                // Un-premultiply so soft edges keep their real colour.
                let pixel = Pixel(
                    r: min(1, Double(raw[index]) / 255 / alpha),
                    g: min(1, Double(raw[index + 1]) / 255 / alpha),
                    b: min(1, Double(raw[index + 2]) / 255 / alpha)
                )
                pixels.append((pixel, x, y))
            }
        }
        guard !pixels.isEmpty else { return nil }

        // No transparency anywhere means the cut-out did not happen.
        let isFlat = opaqueCount > side * side * 9 / 10
        let background: Pixel? = isFlat ? borderColor(of: pixels, side: side) : nil

        var buckets: [Int: (weight: Double, r: Double, g: Double, b: Double)] = [:]
        let centre = Double(side - 1) / 2

        for (pixel, x, y) in pixels {
            if let background, distance(pixel, background) < 0.11 { continue }

            var hue: CGFloat = 0, saturation: CGFloat = 0, brightness: CGFloat = 0, alpha: CGFloat = 0
            UIColor(red: pixel.r, green: pixel.g, blue: pixel.b, alpha: 1)
                .getHue(&hue, saturation: &saturation, brightness: &brightness, alpha: &alpha)

            // Bucket coarsely so a printed logo cannot outvote the fabric.
            let key = Int(hue * 12) * 100 + Int(saturation * 4) * 10 + Int(brightness * 4)

            let offset = max(abs(Double(x) - centre), abs(Double(y) - centre)) / centre
            let weight = isFlat ? max(0.15, 1 - offset * 0.85) : 1

            var bucket = buckets[key] ?? (0, 0, 0, 0)
            bucket.weight += weight
            bucket.r += pixel.r * weight
            bucket.g += pixel.g * weight
            bucket.b += pixel.b * weight
            buckets[key] = bucket
        }

        guard let winner = buckets.values.max(by: { $0.weight < $1.weight }), winner.weight > 0 else { return nil }
        return (winner.r / winner.weight, winner.g / winner.weight, winner.b / winner.weight)
    }

    /// Average of the outer frame of the image — a decent guess at the backdrop.
    private static func borderColor(of pixels: [(pixel: Pixel, x: Int, y: Int)], side: Int) -> Pixel? {
        let margin = max(2, side / 14)
        var sum = Pixel()
        var count = 0.0
        for (pixel, x, y) in pixels where x < margin || y < margin || x >= side - margin || y >= side - margin {
            sum.r += pixel.r; sum.g += pixel.g; sum.b += pixel.b
            count += 1
        }
        guard count > 0 else { return nil }
        return Pixel(r: sum.r / count, g: sum.g / count, b: sum.b / count)
    }

    private static func distance(_ lhs: Pixel, _ rhs: Pixel) -> Double {
        let dr = lhs.r - rhs.r, dg = lhs.g - rhs.g, db = lhs.b - rhs.b
        return (dr * dr + dg * dg + db * db).squareRoot()
    }

    private static func family(forR r: Double, g: Double, b: Double) -> ColorFamily {
        var hue: CGFloat = 0, saturation: CGFloat = 0, brightness: CGFloat = 0, alpha: CGFloat = 0
        UIColor(red: r, green: g, blue: b, alpha: 1)
            .getHue(&hue, saturation: &saturation, brightness: &brightness, alpha: &alpha)
        let degrees = Double(hue) * 360

        if brightness < 0.16 { return .black }
        if saturation < 0.11 { return brightness > 0.82 ? .white : .grey }
        // Camel, sand and tan sit at a higher saturation than one would expect.
        if saturation < 0.45, brightness > 0.55, degrees > 15, degrees < 65 { return .beige }
        if saturation < 0.6, brightness < 0.5, degrees > 10, degrees < 50 { return .brown }

        switch degrees {
        case ..<14: return .red
        case ..<42: return brightness < 0.55 ? .brown : .orange
        case ..<70: return .yellow
        case ..<165: return .green
        case ..<255: return .blue
        case ..<290: return .purple
        case ..<340: return .pink
        default: return .red
        }
    }
}
