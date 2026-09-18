import CoreImage
import OSLog
import UIKit
import Vision

/// Turns a raw phone photo of a garment into the clean, centred cut-out the
/// wardrobe grid shows. Everything here runs on device.
enum GarmentImageProcessor {

    private static let log = Logger(subsystem: "com.gardropp", category: "imaging")

    struct Result {
        /// Subject on a transparent background, trimmed and padded.
        let cutout: UIImage
        /// Whether the subject mask actually succeeded; false means we fell back
        /// to the untouched photo and the caller may want to say so.
        let didIsolateSubject: Bool
        /// What the outline says about the garment; the on-device analyser
        /// leans on it to tell shorts from a T-shirt.
        let shape: GarmentShape
    }

    /// Lifts the garment off its background and centres it on a square canvas.
    static func process(_ input: UIImage) async -> Result {
        let upright = input.normalizedOrientation()

        guard let cgImage = upright.cgImage,
              let masked = await isolateSubject(in: cgImage) else {
            // No cut-out: read the outline off the photo's background instead.
            return Result(
                cutout: square(upright),
                didIsolateSubject: false,
                shape: GarmentShape.analyse(upright, usingAlpha: false)
            )
        }

        let trimmed = trimTransparentEdges(masked) ?? masked
        return Result(
            cutout: square(trimmed),
            didIsolateSubject: true,
            shape: GarmentShape.analyse(trimmed, usingAlpha: true)
        )
    }

    // MARK: - Subject isolation

    private static func isolateSubject(in cgImage: CGImage) async -> UIImage? {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                continuation.resume(returning: performSubjectMask(on: cgImage))
            }
        }
    }

    private static func performSubjectMask(on cgImage: CGImage) -> UIImage? {
        let request = VNGenerateForegroundInstanceMaskRequest()
        let handler = VNImageRequestHandler(cgImage: cgImage, orientation: .up)
        do {
            try handler.perform([request])
            guard let observation = request.results?.first,
                  !observation.allInstances.isEmpty else {
                log.notice("Subject mask found no instances")
                return nil
            }
            let buffer = try observation.generateMaskedImage(
                ofInstances: observation.allInstances,
                from: handler,
                croppedToInstancesExtent: true
            )
            let ciImage = CIImage(cvPixelBuffer: buffer)
            let context = CIContext()
            guard let output = context.createCGImage(ciImage, from: ciImage.extent) else { return nil }
            return UIImage(cgImage: output)
        } catch {
            log.error("Subject mask failed: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    // MARK: - Canvas

    /// Trims empty margins, then centres the subject on a transparent square
    /// with a little breathing room, so every tile in the grid lines up.
    static func square(_ image: UIImage, edge: CGFloat = 1024, inset: CGFloat = 0.1) -> UIImage {
        let trimmed = trimTransparentEdges(image) ?? image
        let target = CGSize(width: edge, height: edge)
        let available = edge * (1 - inset * 2)
        let scale = min(available / trimmed.size.width, available / trimmed.size.height)
        let drawn = CGSize(width: trimmed.size.width * scale, height: trimmed.size.height * scale)
        let origin = CGPoint(x: (edge - drawn.width) / 2, y: (edge - drawn.height) / 2)

        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        format.opaque = false
        return UIGraphicsImageRenderer(size: target, format: format).image { _ in
            trimmed.draw(in: CGRect(origin: origin, size: drawn))
        }
    }

    /// Crops away fully transparent borders left by the mask.
    private static func trimTransparentEdges(_ image: UIImage) -> UIImage? {
        guard let cgImage = image.cgImage else { return nil }
        let width = cgImage.width
        let height = cgImage.height
        guard width > 0, height > 0 else { return nil }

        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        guard let context = CGContext(
            data: &pixels,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))

        var minX = width, minY = height, maxX = 0, maxY = 0
        for y in 0..<height {
            for x in 0..<width where pixels[(y * width + x) * 4 + 3] > 12 {
                minX = min(minX, x); maxX = max(maxX, x)
                minY = min(minY, y); maxY = max(maxY, y)
            }
        }
        guard minX < maxX, minY < maxY else { return nil }

        let padding = 4
        let rect = CGRect(
            x: max(0, minX - padding),
            y: max(0, minY - padding),
            width: min(width, maxX + padding) - max(0, minX - padding),
            height: min(height, maxY + padding) - max(0, minY - padding)
        )
        guard let cropped = cgImage.cropping(to: rect) else { return nil }
        return UIImage(cgImage: cropped)
    }
}

extension GarmentImageProcessor {
    /// Flattens a transparent cut-out onto a flat colour — the vision models
    /// see JPEG, where transparency would otherwise turn black.
    static func flatten(_ image: UIImage, on color: UIColor = .white) -> UIImage {
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        format.opaque = true
        return UIGraphicsImageRenderer(size: image.size, format: format).image { context in
            color.setFill()
            context.fill(CGRect(origin: .zero, size: image.size))
            image.draw(in: CGRect(origin: .zero, size: image.size))
        }
    }
}
