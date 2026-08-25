import AppKit

/// Decodes and caches node images (data URLs) so layout passes stay cheap.
public final class ImageStore {
    public static let shared = ImageStore()
    private let cache = NSCache<NSString, NSImage>()

    private init() { cache.countLimit = 64 }

    public func image(forDataURL raw: String?) -> NSImage? {
        guard let raw, !raw.isEmpty else { return nil }
        if let cached = cache.object(forKey: raw as NSString) { return cached }
        // Accept both full data URLs (data:image/png;base64,…​) and bare base64.
        let payload = raw.contains(",") ? String(raw.split(separator: ",", maxSplits: 1).last ?? "") : raw
        guard let data = Data(base64Encoded: payload, options: [.ignoreUnknownCharacters]),
              let image = NSImage(data: data) else { return nil }
        cache.setObject(image, forKey: raw as NSString)
        return image
    }

    /// Encodes an image as a PNG data URL, auto-scaling down until it fits
    /// within maxBytes. Returns nil only when even heavy downscaling can't fit.
    public static func pngDataURL(from image: NSImage, maxBytes: Int) -> String? {
        var working = image
        var factor: CGFloat = 1.0
        while factor >= 0.12 {
            if let tiff = working.tiffRepresentation,
               let rep = NSBitmapImageRep(data: tiff),
               let png = rep.representation(using: .png, properties: [:]),
               png.count <= maxBytes {
                return "data:image/png;base64," + png.base64EncodedString()
            }
            factor *= 0.7
            let newSize = NSSize(width: max(image.size.width * factor, 16),
                                 height: max(image.size.height * factor, 16))
            let smaller = NSImage(size: newSize)
            smaller.lockFocus()
            image.draw(in: NSRect(origin: .zero, size: newSize))
            smaller.unlockFocus()
            working = smaller
        }
        return nil
    }
}