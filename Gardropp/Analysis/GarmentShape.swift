import UIKit

/// What a garment's outline says about it.
///
/// Vision's general classifier has no label for trousers or shorts, so when it
/// only manages "clothing" the silhouette decides. The useful signal is the gap
/// between the legs: trousers and shorts are split along the bottom edge and
/// solid at the waist, while a top's hem is a continuous line.
struct GarmentShape {
    /// Width / height of the garment's bounding box.
    var aspect: Double
    /// Width / height of the whole photo — always available, and the only thing
    /// left to go on when the outline could not be found.
    var imageAspect: Double
    /// A notch between two legs along the bottom edge.
    var hasLegSplit: Bool
    /// Share of the garment's pixels sitting in the lower half.
    var lowerMass: Double
    /// False when no sensible outline could be found — the caller should only
    /// trust `imageAspect` then.
    var isReliable: Bool

    static let unknown = GarmentShape(
        aspect: 1, imageAspect: 1, hasLegSplit: false, lowerMass: 0.5, isReliable: false
    )

    /// - Parameter usingAlpha: true after a successful cut-out. Otherwise the
    ///   outline is keyed off the photo's border colour, which works on a plain
    ///   backdrop and degrades quietly on a busy one.
    static func analyse(_ image: UIImage, usingAlpha: Bool) -> GarmentShape {
        let imageAspect = image.size.height > 0 ? Double(image.size.width / image.size.height) : 1

        guard let mask = Mask(image: image, usingAlpha: usingAlpha),
              let box = mask.boundingBox else {
            return GarmentShape(
                aspect: imageAspect, imageAspect: imageAspect,
                hasLegSplit: false, lowerMass: 0.5, isReliable: false
            )
        }

        let width = box.maxX - box.minX + 1
        let height = box.maxY - box.minY + 1

        // Keying off the border colour fails in two ways: it can mark the whole
        // frame as garment on a busy photo, or almost nothing when the garment
        // is the same shade as its backdrop. Both are worse than useless.
        let gridCoverage = Double(mask.coveredCount) / Double(mask.width * mask.height)
        // An outline that runs into all four edges is just the photo's frame.
        let touchesEveryEdge = box.minX <= 0 && box.minY <= 0
            && box.maxX >= mask.width - 1 && box.maxY >= mask.height - 1
        let usable = width > 6 && height > 6
            && (usingAlpha || (gridCoverage > 0.05 && gridCoverage < 0.9 && !touchesEveryEdge))

        guard usable else {
            return GarmentShape(
                aspect: imageAspect, imageAspect: imageAspect,
                hasLegSplit: false, lowerMass: 0.5, isReliable: false
            )
        }

        var lower = 0
        let middleRow = box.minY + height / 2
        for y in middleRow...box.maxY {
            for x in box.minX...box.maxX where mask[x, y] { lower += 1 }
        }

        return GarmentShape(
            aspect: Double(width) / Double(height),
            imageAspect: imageAspect,
            hasLegSplit: mask.hasLegSplit(in: box),
            lowerMass: mask.coveredCount == 0 ? 0.5 : Double(lower) / Double(mask.coveredCount),
            isReliable: true
        )
    }
}

// MARK: - Binary outline

private struct Mask {
    let width: Int
    let height: Int
    private let covered: [Bool]
    let coveredCount: Int

    /// Samples the image into a small grid that keeps its proportions.
    init?(image: UIImage, usingAlpha: Bool) {
        guard let cgImage = image.cgImage else { return nil }
        let longest = max(image.size.width, image.size.height)
        guard longest > 0 else { return nil }

        let scale = 96 / longest
        width = max(8, Int((image.size.width * scale).rounded()))
        height = max(8, Int((image.size.height * scale).rounded()))

        var raw = [UInt8](repeating: 0, count: width * height * 4)
        guard let context = CGContext(
            data: &raw,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))

        var flags = [Bool](repeating: false, count: width * height)

        if usingAlpha {
            for index in 0..<(width * height) {
                flags[index] = raw[index * 4 + 3] > 128
            }
        } else {
            // Average the outer frame and call everything unlike it "garment".
            var sum = (r: 0.0, g: 0.0, b: 0.0)
            var samples = 0.0
            let margin = max(1, min(width, height) / 14)
            for y in 0..<height {
                for x in 0..<width where x < margin || y < margin || x >= width - margin || y >= height - margin {
                    let index = (y * width + x) * 4
                    sum.r += Double(raw[index]) / 255
                    sum.g += Double(raw[index + 1]) / 255
                    sum.b += Double(raw[index + 2]) / 255
                    samples += 1
                }
            }
            guard samples > 0 else { return nil }
            let background = (r: sum.r / samples, g: sum.g / samples, b: sum.b / samples)

            for index in 0..<(width * height) {
                let offset = index * 4
                let dr = Double(raw[offset]) / 255 - background.r
                let dg = Double(raw[offset + 1]) / 255 - background.g
                let db = Double(raw[offset + 2]) / 255 - background.b
                flags[index] = (dr * dr + dg * dg + db * db).squareRoot() > 0.16
            }
        }

        covered = flags
        coveredCount = flags.lazy.filter { $0 }.count
        if coveredCount == 0 { return nil }
    }

    subscript(x: Int, y: Int) -> Bool {
        guard x >= 0, y >= 0, x < width, y < height else { return false }
        // A bitmap context stores its first scanline as the top row, so row 0
        // is already the top of the garment.
        return covered[y * width + x]
    }

    var boundingBox: (minX: Int, minY: Int, maxX: Int, maxY: Int)? {
        var minX = width, minY = height, maxX = -1, maxY = -1
        for y in 0..<height {
            for x in 0..<width where self[x, y] {
                minX = min(minX, x); maxX = max(maxX, x)
                minY = min(minY, y); maxY = max(maxY, y)
            }
        }
        return maxX >= minX && maxY >= minY ? (minX, minY, maxX, maxY) : nil
    }

    /// True when the bottom edge is split in two and the top is not — the
    /// signature of a pair of legs. A pair of shoes is gapped all the way up,
    /// which is why the top has to be solid.
    func hasLegSplit(in box: (minX: Int, minY: Int, maxX: Int, maxY: Int)) -> Bool {
        let height = box.maxY - box.minY + 1
        let width = box.maxX - box.minX + 1
        // The legs only have to part a little; the waist has to be clearly open
        // before it counts against them.
        let legThreshold = max(3, Int(Double(width) * 0.07))
        let waistThreshold = max(3, Int(Double(width) * 0.10))

        func rows(_ from: Double, _ to: Double) -> ClosedRange<Int> {
            let lower = box.minY + Int(Double(height) * from)
            let upper = box.minY + min(height - 1, Int(Double(height) * to))
            return min(lower, upper)...max(lower, upper)
        }

        // The waist must be continuous — an open jacket parts at the collar too.
        for y in rows(0.02, 0.28) where largestInteriorGap(row: y, box: box) >= waistThreshold {
            return false
        }

        var split = 0
        var sampled = 0
        for y in rows(0.70, 0.99) {
            sampled += 1
            if largestInteriorGap(row: y, box: box) >= legThreshold { split += 1 }
        }
        return sampled >= 3 && Double(split) / Double(sampled) > 0.5
    }

    /// Longest run of empty cells strictly between the first and last filled one.
    private func largestInteriorGap(row y: Int, box: (minX: Int, minY: Int, maxX: Int, maxY: Int)) -> Int {
        var first = -1, last = -1
        for x in box.minX...box.maxX where self[x, y] {
            if first < 0 { first = x }
            last = x
        }
        guard first >= 0, last > first else { return 0 }

        var longest = 0, run = 0
        for x in first...last {
            if self[x, y] {
                run = 0
            } else {
                run += 1
                longest = max(longest, run)
            }
        }
        return longest
    }
}
