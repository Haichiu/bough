import Darwin
import Foundation

/// Transactional autosave for the set of open tabs.
///
/// A save builds and validates a complete sibling snapshot, swaps directories
/// atomically, validates the new live directory, and only then prunes old
/// transaction directories.
public struct TabStore {
    public static let maximumEntries = 20
    public static let maximumRetainedTransactions = 3
    public static let transactionDirectoryPrefix = ".mindflow-tabs-transaction-"

    public struct Entry {
        public let id: UUID
        public let document: MindDocument

        public init(id: UUID, document: MindDocument) {
            self.id = id
            self.document = document
        }
    }

    public enum CleanupWarning: CustomStringConvertible {
        case cleanupFailed([URL])

        public var description: String {
            switch self {
            case .cleanupFailed(let urls):
                return "transaction cleanup failed: " + urls.map { $0.path }.joined(separator: ", ")
            }
        }
    }

    public enum SaveError: Swift.Error, CustomStringConvertible {
        case duplicateID(UUID)
        case tooManyEntries(Int)
        case encodingFailed(UUID, String)
        case liveDirectoryUnavailable(URL, String)
        case stagingDirectoryUnavailable(URL, String)
        case liveSnapshotFailed(URL, String)
        case writeFailed(URL, String)
        case validationFailed(URL, String)
        case exchangeFailed(URL, URL, String)
        case postCommitValidationFailed(URL, String)
        case rollbackFailed(live: URL, staging: URL, reason: String)
        case rollbackValidationFailed(URL, String)

        public var description: String {
            switch self {
            case .duplicateID(let id):
                return "duplicate tab ID: \(id.uuidString)"
            case .tooManyEntries(let count):
                return "tab snapshot has \(count) entries; maximum is \(TabStore.maximumEntries)"
            case .encodingFailed(let id, let reason):
                return "encoding failed for \(id.uuidString): \(reason)"
            case .liveDirectoryUnavailable(let url, let reason):
                return "live tab directory unavailable at \(url.path): \(reason)"
            case .stagingDirectoryUnavailable(let url, let reason):
                return "staging directory unavailable at \(url.path): \(reason)"
            case .liveSnapshotFailed(let url, let reason):
                return "live snapshot failed at \(url.path): \(reason)"
            case .writeFailed(let url, let reason):
                return "snapshot write failed at \(url.path): \(reason)"
            case .validationFailed(let url, let reason):
                return "snapshot validation failed at \(url.path): \(reason)"
            case .exchangeFailed(let live, let staging, let reason):
                return "directory exchange failed (live \(live.path), staging \(staging.path)): \(reason)"
            case .postCommitValidationFailed(let url, let reason):
                return "post-exchange validation failed at \(url.path), rollback completed: \(reason)"
            case .rollbackFailed(let live, let staging, let reason):
                return "SEVERE rollback failed; preserved live \(live.path) and staging \(staging.path): \(reason)"
            case .rollbackValidationFailed(let url, let reason):
                return "SEVERE rollback validation failed at \(url.path): \(reason)"
            }
        }
    }

    public enum SaveOutcome {
        case committed(warning: CleanupWarning?)
        case failed(SaveError)

        public var succeeded: Bool {
            if case .committed = self { return true }
            return false
        }
    }

    /// These are the only filesystem operations the transaction algorithm needs
    /// to replace in deterministic checks.
    public struct Dependencies {
        public var writeData: (Data, URL) throws -> Void
        public var exchangeDirectories: (URL, URL) throws -> Void

        public init(writeData: @escaping (Data, URL) throws -> Void,
                    exchangeDirectories: @escaping (URL, URL) throws -> Void) {
            self.writeData = writeData
            self.exchangeDirectories = exchangeDirectories
        }

        public static var production: Dependencies {
            Dependencies(
                writeData: { data, url in
                    try data.write(to: url, options: .atomic)
                },
                exchangeDirectories: { live, staging in
                    try TabStore.atomicExchange(live: live, staging: staging)
                }
            )
        }
    }

    public let directory: URL
    private let dependencies: Dependencies

    public init(directory: URL, dependencies: Dependencies = .production) {
        self.directory = directory
        self.dependencies = dependencies
    }

    @discardableResult
    public func save(_ entries: [Entry]) -> SaveOutcome {
        var ids = Set<UUID>()
        for entry in entries {
            guard ids.insert(entry.id).inserted else {
                return .failed(.duplicateID(entry.id))
            }
        }
        guard entries.count <= Self.maximumEntries else {
            return .failed(.tooManyEntries(entries.count))
        }

        let encoded: [EncodedEntry]
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            encoded = try entries.map { entry in
                EncodedEntry(id: entry.id,
                             document: entry.document,
                             filename: "\(entry.id.uuidString).mindmap",
                             data: try encoder.encode(entry.document))
            }
        } catch {
            let id = entries.first?.id ?? UUID()
            return .failed(.encodingFailed(id, String(describing: error)))
        }

        let fileManager = FileManager.default
        do {
            try Self.ensureDirectory(directory, fileManager: fileManager)
        } catch {
            return .failed(.liveDirectoryUnavailable(directory, String(describing: error)))
        }

        let staging = Self.transactionURL(for: directory, fileManager: fileManager)
        do {
            try fileManager.createDirectory(at: staging, withIntermediateDirectories: false)
            guard Self.isDirectory(staging, fileManager: fileManager) else {
                throw DirectoryFailure("path is not a directory")
            }
        } catch {
            return .failed(.stagingDirectoryUnavailable(staging, String(describing: error)))
        }

        for file in encoded {
            do {
                try dependencies.writeData(file.data, staging.appendingPathComponent(file.filename))
            } catch {
                return .failed(.writeFailed(staging.appendingPathComponent(file.filename),
                                            String(describing: error)))
            }
        }

        do {
            try Self.validate(directory: staging, expected: encoded, fileManager: fileManager)
        } catch let error as ValidationFailure {
            return .failed(.validationFailed(staging, error.reason))
        } catch {
            return .failed(.validationFailed(staging, String(describing: error)))
        }

        let oldLive: DirectoryState
        do {
            oldLive = try Self.snapshot(directory: directory, fileManager: fileManager)
        } catch {
            return .failed(.liveSnapshotFailed(directory, String(describing: error)))
        }

        do {
            try dependencies.exchangeDirectories(directory, staging)
        } catch {
            // Keep the complete staging directory as evidence. Production's
            // renamex_np is atomic: a failed exchange leaves live untouched.
            return .failed(.exchangeFailed(directory, staging, String(describing: error)))
        }

        do {
            try Self.validate(directory: directory, expected: encoded, fileManager: fileManager)
        } catch let error as ValidationFailure {
            do {
                try dependencies.exchangeDirectories(directory, staging)
            } catch {
                // Both paths are intentionally preserved for forensic recovery.
                return .failed(.rollbackFailed(live: directory, staging: staging,
                                               reason: String(describing: error)))
            }
            do {
                let restored = try Self.snapshot(directory: directory, fileManager: fileManager)
                guard restored == oldLive else {
                    throw ValidationFailure(reason: "restored live bytes or mtimes differ from the pre-exchange snapshot")
                }
            } catch {
                return .failed(.rollbackValidationFailed(directory, String(describing: error)))
            }
            return .failed(.postCommitValidationFailed(directory, error.reason))
        } catch {
            do {
                try dependencies.exchangeDirectories(directory, staging)
            } catch {
                return .failed(.rollbackFailed(live: directory, staging: staging,
                                               reason: String(describing: error)))
            }
            return .failed(.postCommitValidationFailed(directory, String(describing: error)))
        }

        let warning = Self.pruneTransactions(directory: directory, current: staging,
                                              fileManager: fileManager)
        return .committed(warning: warning)
    }

    private struct EncodedEntry {
        let id: UUID
        let document: MindDocument
        let filename: String
        let data: Data
    }

    private struct DirectoryFailure: Swift.Error {
        let reason: String

        init(_ reason: String) {
            self.reason = reason
        }
    }

    private struct ValidationFailure: Swift.Error {
        let reason: String
    }

    private struct DirectoryState: Equatable {
        let files: [String: Data]
        let modificationDates: [String: Date]
    }

    private static func ensureDirectory(_ url: URL, fileManager: FileManager) throws {
        var isDirectory: ObjCBool = false
        if !fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory) {
            try fileManager.createDirectory(at: url, withIntermediateDirectories: true)
            isDirectory = false
            guard fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory),
                  isDirectory.boolValue else {
                throw DirectoryFailure("path is not a real directory")
            }
        } else {
            guard isDirectory.boolValue else { throw DirectoryFailure("path is not a real directory") }
        }
    }

    private static func isDirectory(_ url: URL, fileManager: FileManager) -> Bool {
        var isDirectory: ObjCBool = false
        return fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory)
            && isDirectory.boolValue
    }

    private static func transactionURL(for directory: URL, fileManager: FileManager) -> URL {
        let parent = directory.deletingLastPathComponent()
        var candidate: URL
        repeat {
            candidate = parent.appendingPathComponent(
                "\(transactionDirectoryPrefix)\(UUID().uuidString)", isDirectory: true)
        } while fileManager.fileExists(atPath: candidate.path)
        return candidate
    }

    private static func validate(directory: URL, expected: [EncodedEntry],
                                 fileManager: FileManager) throws {
        guard isDirectory(directory, fileManager: fileManager) else {
            throw ValidationFailure(reason: "path is not a directory; " + diagnostics(expected))
        }
        let urls: [URL]
        do {
            urls = try fileManager.contentsOfDirectory(at: directory,
                                                        includingPropertiesForKeys: nil,
                                                        options: [])
        } catch {
            throw ValidationFailure(reason: "cannot list directory: \(error); " + diagnostics(expected))
        }
        let actualNames = Set(urls.map(\.lastPathComponent))
        let expectedNames = Set(expected.map(\.filename))
        guard actualNames == expectedNames else {
            throw ValidationFailure(reason: "filename set expected=\(expectedNames.sorted()) actual=\(actualNames.sorted()); "
                                    + diagnostics(expected))
        }

        let decoder = JSONDecoder()
        for file in expected {
            let url = directory.appendingPathComponent(file.filename)
            let data: Data
            do {
                data = try Data(contentsOf: url)
            } catch {
                throw ValidationFailure(reason: "cannot read \(file.filename): \(error); "
                                        + diagnostics(expected))
            }
            let decoded: MindDocument
            do {
                decoded = try decoder.decode(MindDocument.self, from: data)
            } catch {
                throw ValidationFailure(reason: "cannot decode \(file.filename): \(error); "
                                        + diagnostics(expected))
            }
            guard decoded == file.document else {
                throw ValidationFailure(reason: "document mismatch for \(file.filename); expected "
                                        + documentSummary(file.document) + ", actual "
                                        + documentSummary(decoded))
            }
        }
    }

    private static func snapshot(directory: URL, fileManager: FileManager) throws -> DirectoryState {
        guard isDirectory(directory, fileManager: fileManager) else {
            throw DirectoryFailure("path is not a directory")
        }
        let urls = try fileManager.contentsOfDirectory(at: directory,
                                                        includingPropertiesForKeys: [.contentModificationDateKey],
                                                        options: [])
        var files: [String: Data] = [:]
        var dates: [String: Date] = [:]
        for url in urls {
            let name = url.lastPathComponent
            do {
                files[name] = try Data(contentsOf: url)
                let values = try url.resourceValues(forKeys: [.contentModificationDateKey])
                guard let date = values.contentModificationDate else {
                    throw DirectoryFailure("missing modification date for \(name)")
                }
                dates[name] = date
            } catch {
                throw DirectoryFailure("cannot snapshot \(name): \(error)")
            }
        }
        return DirectoryState(files: files, modificationDates: dates)
    }

    private static func pruneTransactions(directory: URL, current: URL,
                                          fileManager: FileManager) -> CleanupWarning? {
        let parent = directory.deletingLastPathComponent()
        let urls: [URL]
        do {
            urls = try fileManager.contentsOfDirectory(at: parent,
                                                        includingPropertiesForKeys: [.contentModificationDateKey],
                                                        options: [])
        } catch {
            return .cleanupFailed([parent])
        }
        var candidates = urls.filter {
            $0.lastPathComponent.hasPrefix(transactionDirectoryPrefix)
                && isDirectory($0, fileManager: fileManager)
        }
        if !candidates.contains(where: { $0.path == current.path }) {
            candidates.append(current)
        }
        let others = candidates
            .filter { $0.path != current.path }
            .sorted {
                let lhs = (try? $0.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate)
                    ?? .distantPast
                let rhs = (try? $1.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate)
                    ?? .distantPast
                if lhs != rhs { return lhs > rhs }
                return $0.lastPathComponent > $1.lastPathComponent
            }
        let retained = Set(([current] + Array(others.prefix(max(0, maximumRetainedTransactions - 1))))
            .map(\.path))
        var failed: [URL] = []
        for url in candidates where !retained.contains(url.path) {
            do {
                try fileManager.removeItem(at: url)
            } catch {
                failed.append(url)
            }
        }
        return failed.isEmpty ? nil : .cleanupFailed(failed)
    }

    private static func diagnostics(_ entries: [EncodedEntry]) -> String {
        entries.map { "\($0.filename) " + documentSummary($0.document) }
            .joined(separator: "; ")
    }

    private static func documentSummary(_ document: MindDocument) -> String {
        "rootTitle=\(document.root.text.debugDescription) nodeCount=\(nodeCount(document.root))"
    }

    private static func nodeCount(_ node: MindNode) -> Int {
        1 + node.children.reduce(0) { $0 + nodeCount($1) }
    }

    private static func atomicExchange(live: URL, staging: URL) throws {
        let result = live.path.withCString { livePath in
            staging.path.withCString { stagingPath in
                renamex_np(livePath, stagingPath, UInt32(RENAME_SWAP))
            }
        }
        guard result == 0 else {
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }
    }
}
