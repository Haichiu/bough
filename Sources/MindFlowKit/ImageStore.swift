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
}