import UIKit

/// Garment photos are kept as files on disk; SwiftData only stores the file name.
/// Keeping multi-megabyte images out of the store keeps queries and the grid fast.
final class ImageStore {
    static let shared = ImageStore()

    private let directory: URL
    private let cache = NSCache<NSString, UIImage>()

    private init() {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        directory = base.appending(path: "GarmentImages", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        cache.countLimit = 120
        // A batch import can decode a couple of dozen full-size cut-outs at
        // once, so cap the cache by bytes as well as by count.
        cache.totalCostLimit = 64 * 1024 * 1024
    }

    func url(for filename: String) -> URL {
        directory.appending(path: filename)
    }

    enum Format {
        /// Keeps transparency — used for the cut-out product shots.
        case png
        case jpeg(quality: CGFloat)
    }

    @discardableResult
    func save(_ image: UIImage, format: Format = .jpeg(quality: 0.9)) throws -> String {
        let data: Data?
        let ext: String
        switch format {
        case .png:
            data = image.pngData()
            ext = "png"
        case .jpeg(let quality):
            data = image.jpegData(compressionQuality: quality)
            ext = "jpg"
        }
        guard let data else { throw ImageStoreError.encodingFailed }
        let filename = "\(UUID().uuidString).\(ext)"
        try data.write(to: url(for: filename), options: .atomic)
        cache.setObject(image, forKey: filename as NSString, cost: image.byteCost)
        return filename
    }

    func image(named filename: String) -> UIImage? {
        guard !filename.isEmpty else { return nil }
        if let cached = cache.object(forKey: filename as NSString) { return cached }
        guard let image = UIImage(contentsOfFile: url(for: filename).path) else { return nil }
        cache.setObject(image, forKey: filename as NSString, cost: image.byteCost)
        return image
    }

    func delete(_ filename: String?) {
        guard let filename, !filename.isEmpty else { return }
        cache.removeObject(forKey: filename as NSString)
        try? FileManager.default.removeItem(at: url(for: filename))
    }

    enum ImageStoreError: Error {
        case encodingFailed
    }
}

extension UIImage {
    /// Rough decoded size in bytes, used as the image cache's cost.
    var byteCost: Int {
        Int(size.width * scale * size.height * scale) * 4
    }

    /// Downscales so the longest edge is at most `maxEdge`, preserving aspect ratio.
    func resized(maxEdge: CGFloat) -> UIImage {
        let longest = max(size.width, size.height)
        guard longest > maxEdge else { return self }
        let scale = maxEdge / longest
        let target = CGSize(width: size.width * scale, height: size.height * scale)
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        return UIGraphicsImageRenderer(size: target, format: format).image { _ in
            draw(in: CGRect(origin: .zero, size: target))
        }
    }

    /// JPEG base64 payload for the vision APIs, capped so requests stay small.
    func base64ForUpload(maxEdge: CGFloat = 1024, quality: CGFloat = 0.8) -> String? {
        resized(maxEdge: maxEdge).jpegData(compressionQuality: quality)?.base64EncodedString()
    }

    /// Fixes the orientation flag so Vision and the encoders see upright pixels.
    func normalizedOrientation() -> UIImage {
        guard imageOrientation != .up else { return self }
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = scale
        return UIGraphicsImageRenderer(size: size, format: format).image { _ in
            draw(in: CGRect(origin: .zero, size: size))
        }
    }
}
