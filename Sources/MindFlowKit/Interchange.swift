import Foundation

/// Safety limits shared by interchange import and export.
/// Native `.mindmap` persistence intentionally does not use this type.
public struct ImportLimits: Equatable {
    public static let standard = ImportLimits(maxBytes: 8 * 1024 * 1024, maxLevels: 128)

    public let maxBytes: Int
    public let maxLevels: Int

    public init(maxBytes: Int = 8 * 1024 * 1024, maxLevels: Int = 128) {
        precondition(maxBytes > 0 && maxBytes < Int.max, "interchange byte limit must be positive")
        precondition(maxLevels > 0, "interchange level limit must be positive")
        self.maxBytes = maxBytes
        self.maxLevels = maxLevels
    }
}

public enum InterchangeError: Error, Equatable, CustomStringConvertible {
    case cancelled
    case unreadable(String)
    case invalidUTF8
    case invalidFormat
    case tooLarge(limit: Int, observed: Int)
    case tooDeep(limit: Int, observedLevel: Int)

    public var description: String {
        switch self {
        case .cancelled:
            return "interchange operation cancelled"
        case .unreadable(let reason):
            return "interchange file is unreadable: \(reason)"
        case .invalidUTF8:
            return "interchange text is not valid UTF-8"
        case .invalidFormat:
            return "interchange format is invalid"
        case .tooLarge(let limit, let observed):
            return "interchange input is \(observed) bytes; limit is \(limit) bytes"
        case .tooDeep(let limit, let observedLevel):
            return "interchange level \(observedLevel) exceeds limit \(limit)"
        }
    }

    public var isCancellation: Bool {
        if case .cancelled = self { return true }
        return false
    }

    /// A concise message for the user-facing ViewModel status path.
    public func userMessage(format: String) -> String {
        switch self {
        case .cancelled:
            return ""
        case .unreadable:
            return "無法讀取\(format)檔案"
        case .invalidUTF8:
            return "\(format)檔案不是有效的 UTF-8"
        case .invalidFormat:
            return "無法解析\(format)格式"
        case .tooLarge(let limit, _):
            return "\(format)超過 \(Self.byteLimitDescription(limit)) 大小上限"
        case .tooDeep(let limit, _):
            return "\(format)超過 \(limit) 層深度上限"
        }
    }

    private static func byteLimitDescription(_ bytes: Int) -> String {
        let mebibyte = 1024 * 1024
        if bytes % mebibyte == 0 {
            return "\(bytes / mebibyte) MiB"
        }
        return "\(bytes) bytes"
    }
}

/// File input with metadata preflight and a hard maxBytes+1 read window.
/// The dependencies are intentionally small so checks can simulate misleading
/// metadata, short reads, unreadable files, and cancellation-free file input.
public struct BoundedInterchangeReader {
    public struct Dependencies {
        public var metadataSize: (URL) throws -> Int?
        public var read: (URL, Int) throws -> Data

        public init(metadataSize: @escaping (URL) throws -> Int?,
                    read: @escaping (URL, Int) throws -> Data) {
            self.metadataSize = metadataSize
            self.read = read
        }

        public static var production: Dependencies {
            Dependencies(
                metadataSize: { url in
                    try url.resourceValues(forKeys: [.fileSizeKey]).fileSize
                },
                read: { url, byteWindow in
                    try readInterchangeBytes(at: url, byteWindow: byteWindow)
                })
        }
    }

    public let limits: ImportLimits
    private let dependencies: Dependencies

    public init(limits: ImportLimits = .standard,
                dependencies: Dependencies = .production) {
        self.limits = limits
        self.dependencies = dependencies
    }

    public func readData(from url: URL) throws -> Data {
        do {
            if let size = try dependencies.metadataSize(url), size >= 0,
               size > limits.maxBytes {
                throw InterchangeError.tooLarge(limit: limits.maxBytes, observed: size)
            }
        } catch let error as InterchangeError {
            throw error
        } catch {
            throw InterchangeError.unreadable(String(describing: error))
        }

        let data: Data
        do {
            data = try dependencies.read(url, limits.maxBytes + 1)
        } catch let error as InterchangeError {
            throw error
        } catch {
            throw InterchangeError.unreadable(String(describing: error))
        }
        guard data.count <= limits.maxBytes else {
            throw InterchangeError.tooLarge(limit: limits.maxBytes, observed: data.count)
        }
        return data
    }

    public func readText(from url: URL) throws -> String {
        let data = try readData(from: url)
        guard let text = String(data: data, encoding: .utf8) else {
            throw InterchangeError.invalidUTF8
        }
        return text
    }
}

/// Streaming-ish bounded output accumulator. It never appends a fragment that
/// would exceed the configured UTF-8 byte budget.
struct BoundedTextEmitter {
    let limits: ImportLimits
    private(set) var byteCount = 0
    private var chunks: [String] = []

    init(limits: ImportLimits) {
        self.limits = limits
    }

    mutating func append(_ text: String) throws {
        let count = text.utf8.count
        guard count <= limits.maxBytes - byteCount else {
            throw InterchangeError.tooLarge(limit: limits.maxBytes,
                                             observed: byteCount + count)
        }
        chunks.append(text)
        byteCount += count
    }

    mutating func appendEscapedXML(_ text: String) throws {
        for character in text {
            switch character {
            case "&": try append("&amp;")
            case "<": try append("&lt;")
            case ">": try append("&gt;")
            case "\"": try append("&quot;")
            default: try append(String(character))
            }
        }
    }

    func output() -> String {
        chunks.joined()
    }
}

private func readInterchangeBytes(at url: URL, byteWindow: Int) throws -> Data {
    let handle = try FileHandle(forReadingFrom: url)
    defer { try? handle.close() }
    var data = Data()
    while data.count < byteWindow {
        guard let chunk = try handle.read(upToCount: byteWindow - data.count),
              !chunk.isEmpty else { break }
        data.append(chunk)
    }
    return data
}
