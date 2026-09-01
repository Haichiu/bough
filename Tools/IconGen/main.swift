import Foundation
import MindFlowKit

private enum IconGenError: Error, CustomStringConvertible {
    case usage
    case iconutilFailed(String)
    case outputMissing

    var description: String {
        switch self {
        case .usage:
            return "usage: MindFlowIconGen OUTPUT.icns [--preview PREVIEW.png]"
        case .iconutilFailed(let detail):
            return "iconutil failed: \(detail)"
        case .outputMissing:
            return "iconutil produced no non-empty output"
        }
    }
}

private func runIconutil(iconset: URL, output: URL) throws {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
    process.arguments = ["-c", "icns", iconset.path, "-o", output.path]
    let errorPipe = Pipe()
    process.standardError = errorPipe
    try process.run()
    process.waitUntilExit()
    guard process.terminationStatus == 0 else {
        let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
        let detail = String(data: errorData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
            ?? "exit \(process.terminationStatus)"
        throw IconGenError.iconutilFailed(detail)
    }
}

private func generate(output: URL, preview: URL?) throws {
    let fileManager = FileManager.default
    let temporaryRoot = fileManager.temporaryDirectory
        .appendingPathComponent("mindflow-iconset-\(UUID().uuidString)", isDirectory: true)
    var temporaryRootExists = false

    func cleanup() throws {
        guard temporaryRootExists, fileManager.fileExists(atPath: temporaryRoot.path) else { return }
        try fileManager.removeItem(at: temporaryRoot)
        temporaryRootExists = false
    }

    do {
        try fileManager.createDirectory(at: temporaryRoot, withIntermediateDirectories: false)
        temporaryRootExists = true
        let iconset = temporaryRoot.appendingPathComponent("AppIcon.iconset", isDirectory: true)
        try fileManager.createDirectory(at: iconset, withIntermediateDirectories: false)

        for slot in AppIconArtwork.slots {
            let data = try AppIconArtwork.pngData(for: slot)
            try data.write(to: iconset.appendingPathComponent(slot.fileName), options: .atomic)
        }
        try runIconutil(iconset: iconset, output: output)

        guard fileManager.fileExists(atPath: output.path),
              let size = try output.resourceValues(forKeys: [.fileSizeKey]).fileSize,
              size > 0 else {
            throw IconGenError.outputMissing
        }
        if let preview {
            let previewData = try AppIconArtwork.previewPNGData()
            try previewData.write(to: preview, options: .atomic)
        }
        try cleanup()
    } catch {
        do {
            try cleanup()
        } catch {
            fputs("MindFlowIconGen cleanup failed: \(error)\n", stderr)
        }
        throw error
    }
}

func main() throws {
    var arguments = Array(CommandLine.arguments.dropFirst())
    guard let outputPath = arguments.first else { throw IconGenError.usage }
    arguments.removeFirst()

    var preview: URL?
    if arguments.isEmpty {
        preview = nil
    } else if arguments.count == 2, arguments[0] == "--preview" {
        preview = URL(fileURLWithPath: arguments[1])
    } else {
        throw IconGenError.usage
    }
    try generate(output: URL(fileURLWithPath: outputPath), preview: preview)
}

do {
    try main()
} catch {
    fputs("MindFlowIconGen: \(error)\n", stderr)
    exit(EXIT_FAILURE)
}
