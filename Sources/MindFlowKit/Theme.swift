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

        /// The one final-value seam used by colors, hex serialization, and contrast.
        /// It deliberately rounds channels without clamping them.
        public var quantized8: RGB {
            RGB(red: (red * 255).rounded() / 255,
                green: (green * 255).rounded() / 255,
                blue: (blue * 255).rounded() / 255)
        }

        /// Lowercase is convenient for stable SVG diagnostics.
        public var hex: String {
            let q = quantized8
            return String(format: "#%02x%02x%02x",
                          Int((q.red * 255).rounded()),
                          Int((q.green * 255).rounded()),
                          Int((q.blue * 255).rounded()))
        }

        public var color: Color {
            let q = quantized8
            return Color(.sRGB, red: q.red, green: q.green, blue: q.blue, opacity: 1)
        }

        fileprivate var nsColor: NSColor {
            let q = quantized8
            return NSColor(srgbRed: CGFloat(q.red), green: CGFloat(q.green), blue: CGFloat(q.blue), alpha: 1)
        }

        /// WCAG relative luminance for this final sRGB value.
        public var relativeLuminance: Double {
            let q = quantized8
            let r = Palette.toLinear(q.red)
            let g = Palette.toLinear(q.green)
            let b = Palette.toLinear(q.blue)
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

    private enum GamutMapping {
        case step
        case boundary
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
    public var statusHighlightOKLCh: OKLCh { resolvedValues.statusHighlight.oklch }
    public static var statusHighlightSourceRGB: RGB { statusHighlightSourceRGBValue }
    public static var statusHighlightSourceOKLCh: OKLCh { statusHighlightSourceOKLChValue }
    public static var lightStatusHighlightOKLCh: OKLCh { lightStatusHighlightSample.oklch }
    public static var darkStatusHighlightOKLCh: OKLCh { darkStatusHighlightSample.oklch }
    public var branchRGB: [RGB] { resolvedValues.branches.map(\.rgb) }
    public var branchOKLCh: [OKLCh] { resolvedValues.branches.map(\.oklch) }
    public static var accentOKLCh: OKLCh { baseOKLCh }
    /// App Icon bottom stop: same accent hue/chroma, with OKLCh lightness × 0.70.
    /// The shared gamut mapper may lower chroma, but never clamps RGB channels.
    public static var iconGradientBottomRGB: RGB { iconGradientBottomSample.rgb }
    public static var iconGradientBottomOKLCh: OKLCh { iconGradientBottomSample.oklch }

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

    private static let statusHighlightSourceRGBValue = RGB(hex: 0xF5C542)
    private static let statusHighlightSourceOKLChValue = rgbToOKLCh(statusHighlightSourceRGBValue)

    /// The theme every palette lookup follows. Assigning it changes what the
    /// existing static palettes resolve to; it does not create new Palette
    /// instances, because call sites all over the canvas hold `Palette.screen`.
    public static var active: MindTheme = .classic

    /// Everything a single theme resolves to. Built once per theme and cached:
    /// branch generation runs a contrast bisection per branch, which is far too
    /// much work to repeat on every colour read during rendering.
    private struct ThemeValues {
        let light: Values
        let dark: Values
        let accent: RGB
        let base: OKLCh
        let iconBottom: Sample
    }

    private static let themeCache: [MindTheme: ThemeValues] = {
        var out: [MindTheme: ThemeValues] = [:]
        for theme in MindTheme.allCases { out[theme] = buildTheme(theme) }
        return out
    }()

    private static func buildTheme(_ theme: MindTheme) -> ThemeValues {
        let spec = theme.spec
        let accent = RGB(hex: spec.accent)
        let base = rgbToOKLCh(accent)
        let lightCanvas = RGB(hex: spec.lightCanvas)
        let lightCard = RGB(hex: spec.lightCard)
        let darkCanvas = RGB(hex: spec.darkCanvas)

        // The marked-node highlight keeps one meaning across every theme: it is
        // always the same amber source hue. Only its lightness is re-solved, so
        // that it still clears the 3.1:1 floor against this theme's surfaces. A
        // status colour that stays legible is doing its job; one that keeps a
        // fixed RGB and disappears into a dark canvas is not.
        let lightHighlight = makeLightStatusHighlightSample(lightCanvas: lightCanvas, lightCard: lightCard)
        let darkHighlight = Sample(oklch: statusHighlightSourceOKLChValue, rgb: statusHighlightSourceRGBValue)

        return ThemeValues(
            light: Values(
                canvas: lightCanvas,
                card: lightCard,
                textPrimary: RGB(hex: spec.lightTextPrimary),
                textSecondary: RGB(hex: spec.lightTextSecondary),
                accent: accent,
                creamText: RGB(hex: spec.lightOnAccent),
                secondarySurface: RGB(hex: spec.lightSecondarySurface),
                statusHighlight: lightHighlight.rgb,
                branches: makeBranchSamples(base: base, darkCanvas: darkCanvas, dark: false)),
            dark: Values(
                canvas: darkCanvas,
                card: RGB(hex: spec.darkCard),
                textPrimary: RGB(hex: spec.darkTextPrimary),
                textSecondary: RGB(hex: spec.darkTextSecondary),
                accent: accent,
                creamText: RGB(hex: spec.darkOnAccent),
                secondarySurface: RGB(hex: spec.darkSecondarySurface),
                statusHighlight: darkHighlight.rgb,
                branches: makeBranchSamples(base: base, darkCanvas: darkCanvas, dark: true)),
            accent: accent,
            base: base,
            iconBottom: gamutMapped(lightness: base.lightness * 0.70,
                                    chroma: base.chroma,
                                    hue: base.hue,
                                    mapping: .boundary))
    }

    private static var currentTheme: ThemeValues { themeCache[active] ?? buildTheme(.classic) }

    private static var accentRGBValue: RGB { currentTheme.accent }
    private static var baseOKLCh: OKLCh { currentTheme.base }
    private static var iconGradientBottomSample: Sample { currentTheme.iconBottom }
    private static var lightStatusHighlightSample: Sample {
        Sample(oklch: rgbToOKLCh(currentTheme.light.statusHighlight), rgb: currentTheme.light.statusHighlight)
    }
    private static var darkStatusHighlightSample: Sample {
        Sample(oklch: rgbToOKLCh(currentTheme.dark.statusHighlight), rgb: currentTheme.dark.statusHighlight)
    }
    private static var lightValues: Values { currentTheme.light }
    private static var darkValues: Values { currentTheme.dark }

    private static func makeLightStatusHighlightSample(lightCanvas: RGB, lightCard: RGB) -> Sample {
        let source = statusHighlightSourceOKLChValue
        func passes(_ sample: Sample) -> Bool {
            sample.rgb.contrastRatio(with: lightCanvas) >= 3.1
                && sample.rgb.contrastRatio(with: lightCard) >= 3.1
        }
        let initial = gamutMapped(lightness: source.lightness,
                                  chroma: source.chroma, hue: source.hue)
        guard !passes(initial) else { return initial }

        // Keep source hue/chroma, search only lower L, and let the shared mapper lower C
        // only when the requested OKLCh sample leaves sRGB.
        var low = 0.0
        var high = source.lightness
        for _ in 0..<48 {
            let middle = (low + high) / 2
            let probe = gamutMapped(lightness: middle,
                                    chroma: source.chroma, hue: source.hue)
            if passes(probe) {
                low = middle
            } else {
                high = middle
            }
        }
        return gamutMapped(lightness: low, chroma: source.chroma, hue: source.hue)
    }

    private static func makeBranchSamples(base: OKLCh, darkCanvas: RGB, dark: Bool) -> [Sample] {
        return (0..<6).map { index in
            let hue = normalizedHue(base.hue + Double(index) * 60)
            var sample = gamutMapped(lightness: base.lightness, chroma: base.chroma, hue: hue)
            if dark && sample.rgb.contrastRatio(with: darkCanvas) < 3.1 {
                // Raise L only for the branches that miss the final 8-bit dark-canvas 3.1:1 floor.
                var low = base.lightness
                var high = 1.0
                for _ in 0..<32 {
                    let middle = (low + high) / 2
                    let probe = gamutMapped(lightness: middle, chroma: base.chroma, hue: hue)
                    if probe.rgb.contrastRatio(with: darkCanvas) >= 3.1 {
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

    private static func gamutMapped(lightness: Double, chroma: Double, hue: Double,
                                    mapping: GamutMapping = .step) -> Sample {
        var mappedChroma = chroma
        if case .boundary = mapping {
            var low = 0.0
            var high = chroma
            if !inGamut(oklchToLinearRGB(lightness: lightness, chroma: high, hue: hue)) {
                for _ in 0..<48 {
                    let middle = (low + high) / 2
                    if inGamut(oklchToLinearRGB(lightness: lightness,
                                                chroma: middle, hue: hue)) {
                        low = middle
                    } else {
                        high = middle
                    }
                }
                mappedChroma = low
            }
        } else {
            var linear = oklchToLinearRGB(lightness: lightness, chroma: mappedChroma, hue: hue)
            while mappedChroma > 0 && !inGamut(linear) {
                mappedChroma = max(0, mappedChroma - 0.005)
                linear = oklchToLinearRGB(lightness: lightness, chroma: mappedChroma, hue: hue)
            }
        }
        let linear = oklchToLinearRGB(lightness: lightness, chroma: mappedChroma, hue: hue)
        let rgb = RGB(red: fromLinear(linear.0),
                      green: fromLinear(linear.1),
                      blue: fromLinear(linear.2)).quantized8
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
