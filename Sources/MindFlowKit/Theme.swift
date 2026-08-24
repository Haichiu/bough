import SwiftUI

struct Theme: Identifiable, Equatable {
    let id: String
    let name: String
    let branchColors: [Color]

    func color(forIndex index: Int) -> Color {
        branchColors.isEmpty ? .accentColor : branchColors[((index % branchColors.count) + branchColors.count) % branchColors.count]
    }

    static let all: [Theme] = [
        Theme(id: "ocean", name: "海洋", branchColors: [
            Color(hex: 0x3B82C4), Color(hex: 0x2FA39A), Color(hex: 0x8A63C9),
            Color(hex: 0xD98A3D), Color(hex: 0xC75B6B), Color(hex: 0x5B8C5A),
        ]),
        Theme(id: "candy", name: "糖果", branchColors: [
            Color(hex: 0xF26D85), Color(hex: 0xF5A623), Color(hex: 0x7ED3A5),
            Color(hex: 0x5AA9E6), Color(hex: 0xB08BE0), Color(hex: 0xF0C05A),
        ]),
        Theme(id: "forest", name: "森林", branchColors: [
            Color(hex: 0x4E7C4E), Color(hex: 0x7A9A54), Color(hex: 0xA67B45),
            Color(hex: 0x557B83), Color(hex: 8_386_496), Color(hex: 0x6B8F71),
        ]),
        Theme(id: "mono", name: "極簡", branchColors: [
            Color(hex: 0x4A4A4A), Color(hex: 0x6E6E6E), Color(hex: 0x8C8C8C),
            Color(hex: 0x5A5A5A), Color(hex: 0x767676), Color(hex: 0x9A9A9A),
        ]),
    ]

    static func named(_ id: String) -> Theme {
        all.first { $0.id == id } ?? all[0]
    }
}

extension Color {
    init(hex: UInt32) {
        self.init(.sRGB,
                  red: Double((hex >> 16) & 0xFF) / 255.0,
                  green: Double((hex >> 8) & 0xFF) / 255.0,
                  blue: Double(hex & 0xFF) / 255.0,
                  opacity: 1)
    }
}
