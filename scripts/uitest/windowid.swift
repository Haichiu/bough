import CoreGraphics
import Foundation

let owner = CommandLine.arguments.dropFirst().first ?? "Finder"
let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
let windows = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] ?? []
var best: (id: UInt32, area: CGFloat)?

for window in windows {
    guard window[kCGWindowOwnerName as String] as? String == owner,
          (window[kCGWindowLayer as String] as? NSNumber)?.intValue == 0,
          let id = (window[kCGWindowNumber as String] as? NSNumber)?.uint32Value,
          let map = window[kCGWindowBounds as String] as? [String: Any],
          let bounds = CGRect(dictionaryRepresentation: map as CFDictionary),
          bounds.width > 200, bounds.height > 100 else { continue }
    let area = bounds.width * bounds.height
    if best == nil || area > best!.area { best = (id, area) }
}

guard let best else {
    fputs("no on-screen layer-0 window owned by \(owner)\n", stderr)
    exit(2)
}
print(best.id)
