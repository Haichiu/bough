import AppKit
import SwiftUI

/// The one visual palette used by MindFlow.
///
/// `screen` resolves through AppKit's appearance-aware named colours while `light` and
/// `dark` are explicit, stable values for rendering and diagnostics. Documents retain their
/// legacy themeName only as metadata; it no longer selects a different colour system.
public struct Palette {
    public enum Appearance: Equatable {
        case light
        case dark
        case screen
    }

    /// A small, inspectable sRGB value used for colour math and export diagnostics.
    public struct RGB: Equatable {
        public let red: Double
        public let green: Double
        public let blue: Double

        /// Values are sRGB channels already proven to be in the [0, 1] gamut.
        /// Gamut mapping changes OKLCh chroma rather than repairing channels here.
        public init(red: Double, green: Double, blue: Double) {
            self.red = red
            self.green = green
            self.blue = blue
        }

        public init(hex: UInt32) {
            self.init(red: Double((hex >> 16) & 0xFF) / 255,
                      green: Double((hex >> 8) & 0xFF) / 255,
                      blue: Double(hex & 0xFF) / 255)
        }

        /// Lowercase is convenient for stable SVG diagnostics.
        public var hex: String {
            String(format: "#%02x%02x%02x",
                   Int((red * 255).rounded()),
                   Int((green * 255).rounded()),
                   Int((blue * 255).rounded()))
        }

        public var color: Color {
            Color(.sRGB, red: red, green: green, blue: blue, opacity: 1)
        }

        fileprivate var nsColor: NSColor {
            NSColor(srgbRed: CGFloat(red), green: CGFloat(green), blue: CGFloat(blue), alpha: 1)
        }

        /// WCAG relative luminance for this sRGB value.
        public var relativeLuminance: Double {
            let r = Palette.toLinear(red)
            let g = Palette.toLinear(green)
            let b = Palette.toLinear(blue)
            return 0.2126 * r + 0.7152 * g + 0.0722 * b
        }

        public func contrastRatio(with other: RGB) -> Double {
            let lighter = max(relativeLuminance, other.relativeLuminance)
            let darker = min(relativeLuminance, other.relativeLuminance)
            return (lighter + 0.05) / (darker + 0.05)
        }

        /// The actual OKLCh coordinates of this resolved sRGB value.
        public var oklch: OKLCh { Palette.rgbToOKLCh(self) }
    }

    /// OKLCh coordinates used to derive the six branch hues.
    public struct OKLCh: Equatable {
        public let lightness: Double
        public let chroma: Double
        public let hue: Double

        public init(lightness: Double, chroma: Double, hue: Double) {
            self.lightness = lightness
            self.chroma = chroma
            self.hue = Palette.normalizedHue(hue)
        }
    }

    private struct Sample {
        let oklch: OKLCh
        let rgb: RGB
    }

    private struct Values {
        let canvas: RGB
        let card: RGB
        let textPrimary: RGB
        let textSecondary: RGB
        let accent: RGB
        let creamText: RGB
        let secondarySurface: RGB
        let statusHighlight: RGB
        let branches: [Sample]
    }

    public let appearance: Appearance

    public static let light = Palette(appearance: .light)
    public static let dark = Palette(appearance: .dark)
    public static let screen = Palette(appearance: .screen)

    public var canvasBackground: Color { resolve(light: Self.lightValues.canvas, dark: Self.darkValues.canvas) }
    public var card: Color { resolve(light: Self.lightValues.card, dark: Self.darkValues.card) }
    public var textPrimary: Color { resolve(light: Self.lightValues.textPrimary, dark: Self.darkValues.textPrimary) }
    public var textSecondary: Color { resolve(light: Self.lightValues.textSecondary, dark: Self.darkValues.textSecondary) }
    public var accent: Color { resolve(light: Self.lightValues.accent, dark: Self.darkValues.accent) }
    public var rootFill: Color { accent }
    public var creamText: Color { resolve(light: Self.lightValues.creamText, dark: Self.darkValues.creamText) }
    public var secondarySurface: Color {
        resolve(light: Self.lightValues.secondarySurface, dark: Self.darkValues.secondarySurface)
    }
    /// Semantic highlight retained for the existing marked-node affordance.
    public var statusHighlight: Color {
        resolve(light: Self.lightValues.statusHighlight, dark: Self.darkValues.statusHighlight)
    }

    // Resolved values are public so checks can inspect the actual paint contract without
    // depending on SwiftUI's environment resolution.
    public var canvasRGB: RGB { resolvedValues.canvas }
    public var cardRGB: RGB { resolvedValues.card }
    public var textPrimaryRGB: RGB { resolvedValues.textPrimary }
    public var textSecondaryRGB: RGB { resolvedValues.textSecondary }
    public var accentRGB: RGB { resolvedValues.accent }
    public var creamTextRGB: RGB { resolvedValues.creamText }
    public var secondarySurfaceRGB: RGB { resolvedValues.secondarySurface }
    public var statusHighlightRGB: RGB { resolvedValues.statusHighlight }
    public var branchRGB: [RGB] { resolvedValues.branches.map(\.rgb) }
    public var branchOKLCh: [OKLCh] { resolvedValues.branches.map(\.oklch) }
    public static var accentOKLCh: OKLCh { baseOKLCh }

    public func color(forIndex index: Int) -> Color {
        let safeIndex = ((index % 6) + 6) % 6
        switch appearance {
        case .light:
            return Self.lightValues.branches[safeIndex].rgb.color
        case .dark:
            return Self.darkValues.branches[safeIndex].rgb.color
        case .screen:
            return dynamicColor(light: Self.lightValues.branches[safeIndex].rgb,
                                dark: Self.darkValues.branches[safeIndex].rgb)
        }
    }

    public func rgb(forIndex index: Int) -> RGB {
        let safeIndex = ((index % 6) + 6) % 6
        return resolvedValues.branches[safeIndex].rgb
    }

    private init(appearance: Appearance) {
        self.appearance = appearance
    }

    private var resolvedValues: Values {
        appearance == .dark ? Self.darkValues : Self.lightValues
    }

    private func resolve(light: RGB, dark: RGB) -> Color {
        switch appearance {
        case .light:
            return light.color
        case .dark:
            return dark.color
        case .screen:
            return dynamicColor(light: light, dark: dark)
        }
    }

    /// Every screen colour is an AppKit named colour so light/dark changes resolve live.
    private func dynamicColor(light: RGB, dark: RGB) -> Color {
        Color(NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            return (isDark ? dark : light).nsColor
        })
    }

    private static let accentRGBValue = RGB(hex: 0x3368A0)
    private static let baseOKLCh = rgbToOKLCh(accentRGBValue)
    private static let darkCanvasRGBValue = RGB(hex: 0x101819)

    private static let lightBranchSamples = makeBranchSamples(dark: false)
    private static let darkBranchSamples = makeBranchSamples(dark: true)

    private static let lightValues = Values(
        canvas: RGB(hex: 0xF2EFE7),
        card: RGB(hex: 0xFFFFFF),
        textPrimary: RGB(hex: 0x2A2A28),
        textSecondary: RGB(hex: 0x5E6C6F),
        accent: accentRGBValue,
        creamText: RGB(hex: 0xF2EFE7),
        secondarySurface: RGB(hex: 0xC8DFDB),
        statusHighlight: RGB(hex: 0xF5C542),
        branches: lightBranchSamples
    )

    private static let darkValues = Values(
        canvas: RGB(hex: 0x101819),
        card: RGB(hex: 0x1B2628),
        textPrimary: RGB(hex: 0xE2E9EB),
        textSecondary: RGB(hex: 0x9AA7AA),
        accent: accentRGBValue,
        creamText: RGB(hex: 0xF2EFE7),
        secondarySurface: RGB(hex: 0xC8DFDB),
        statusHighlight: RGB(hex: 0xF5C542),
        branches: darkBranchSamples
    )

    private static func makeBranchSamples(dark: Bool) -> [Sample] {
        let base = baseOKLCh
        return (0..<6).map { index in
            let hue = normalizedHue(base.hue + Double(index) * 60)
            var sample = gamutMapped(lightness: base.lightness, chroma: base.chroma, hue: hue)
            if dark && sample.rgb.contrastRatio(with: darkCanvasRGBValue) < 3.0 {
                // Raise L only for the branches that miss the dark-canvas 3:1 floor.
                var low = base.lightness
                var high = 1.0
                for _ in 0..<32 {
                    let middle = (low + high) / 2
                    let probe = gamutMapped(lightness: middle, chroma: base.chroma, hue: hue)
                    if probe.rgb.contrastRatio(with: darkCanvasRGBValue) >= 3.0 {
                        high = middle
                    } else {
                        low = middle
                    }
                }
                sample = gamutMapped(lightness: high, chroma: base.chroma, hue: hue)
            }
            return sample
        }
    }

    private static func gamutMapped(lightness: Double, chroma: Double, hue: Double) -> Sample {
        var mappedChroma = chroma
        var linear = oklchToLinearRGB(lightness: lightness, chroma: mappedChroma, hue: hue)
        while mappedChroma > 0 && !inGamut(linear) {
            mappedChroma = max(0, mappedChroma - 0.005)
            linear = oklchToLinearRGB(lightness: lightness, chroma: mappedChroma, hue: hue)
        }
        let rgb = RGB(red: fromLinear(linear.0),
                      green: fromLinear(linear.1),
                      blue: fromLinear(linear.2))
        return Sample(oklch: OKLCh(lightness: lightness, chroma: mappedChroma, hue: hue), rgb: rgb)
    }

    private static func rgbToOKLCh(_ rgb: RGB) -> OKLCh {
        let r = toLinear(rgb.red)
        let g = toLinear(rgb.green)
        let b = toLinear(rgb.blue)
        let l = cubeRoot(0.4122214708 * r + 0.5363325363 * g + 0.0514459929 * b)
        let m = cubeRoot(0.2119034982 * r + 0.6806995451 * g + 0.1073969566 * b)
        let s = cubeRoot(0.0883024619 * r + 0.2817188376 * g + 0.6299787005 * b)
        let lightness = 0.2104542553 * l + 0.7936177850 * m - 0.0040720468 * s
        let a = 1.9779984951 * l - 2.4285922050 * m + 0.4505937099 * s
        let bValue = 0.0259040371 * l + 0.7827717662 * m - 0.8086757660 * s
        return OKLCh(lightness: lightness, chroma: hypot(a, bValue), hue: atan2(bValue, a) * 180 / .pi)
    }

    private static func oklchToLinearRGB(lightness: Double, chroma: Double, hue: Double)
        -> (Double, Double, Double) {
        let radians = hue * .pi / 180
        let a = chroma * cos(radians)
        let b = chroma * sin(radians)
        let l = pow(lightness + 0.3963377774 * a + 0.2158037573 * b, 3)
        let m = pow(lightness - 0.1055613458 * a - 0.0638541728 * b, 3)
        let s = pow(lightness - 0.0894841775 * a - 1.2914855480 * b, 3)
        return (4.0767416621 * l - 3.3077115913 * m + 0.2309699292 * s,
                -1.2684380046 * l + 2.6097574011 * m - 0.3413193965 * s,
                -0.0041960863 * l - 0.7034186147 * m + 1.7076147010 * s)
    }

    private static func inGamut(_ rgb: (Double, Double, Double)) -> Bool {
        [rgb.0, rgb.1, rgb.2].allSatisfy { $0 >= 0 && $0 <= 1 }
    }

    private static func toLinear(_ value: Double) -> Double {
        value <= 0.04045 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4)
    }

    private static func fromLinear(_ value: Double) -> Double {
        value <= 0.0031308 ? 12.92 * value : 1.055 * pow(value, 1 / 2.4) - 0.055
    }

    private static func cubeRoot(_ value: Double) -> Double {
        value >= 0 ? pow(value, 1 / 3) : -pow(-value, 1 / 3)
    }

    private static func normalizedHue(_ hue: Double) -> Double {
        let result = hue.truncatingRemainder(dividingBy: 360)
        return result >= 0 ? result : result + 360
    }

}

/// Compatibility namespace for documents and color-tag UI. Legacy IDs intentionally all
/// resolve to the same dynamic Palette A; tags are semantic markers, not themes.
public enum Theme {
    public static func named(_ id: String) -> Palette {
        _ = id
        return .screen
    }

    /// Named marker colors for color-tagging nodes. These remain outside Palette A.
    public static let colorTags: [(name: String, key: String, color: Color)] = [
        ("紅", "red", Color(hex: 0xE05252)),
        ("橙", "orange", Color(hex: 0xF08C3A)),
        ("黃", "yellow", Color(hex: 0xF0C542)),
        ("綠", "green", Color(hex: 0x51B573)),
        ("藍", "blue", Color(hex: 0x4A90D9)),
        ("紫", "purple", Color(hex: 0x9B6FD0)),
    ]

    public static func colorTag(named key: String) -> Color? {
        colorTags.first(where: { $0.key == key })?.color
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
