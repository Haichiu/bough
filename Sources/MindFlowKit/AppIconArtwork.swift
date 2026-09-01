import AppKit
import CoreGraphics
import Foundation

/// Programmatic source of truth for the macOS app icon.
///
/// Geometry is authored in the 1024-point DESIGN coordinate system and rasterized at each
/// slot's physical pixel size. The generator and offline checks both call this renderer; no
/// generated image is part of the source tree.
public enum AppIconArtwork {
    public enum SizeBand: String, Equatable {
        case small
        case mid
        case large
    }

    public struct Metrics: Equatable {
        public let lineWidth: CGFloat
        public let dotDiameter: CGFloat
        public let hubWidth: CGFloat
        public let spread: CGFloat
        public let translationX: CGFloat

        public init(lineWidth: CGFloat, dotDiameter: CGFloat, hubWidth: CGFloat, spread: CGFloat,
                    translationX: CGFloat = 0) {
            self.lineWidth = lineWidth
            self.dotDiameter = dotDiameter
            self.hubWidth = hubWidth
            self.spread = spread
            self.translationX = translationX
        }
    }

    public struct Slot: Equatable {
        public let fileName: String
        public let pixelSize: Int
        public let band: SizeBand

        public init(fileName: String, pixelSize: Int, band: SizeBand) {
            self.fileName = fileName
            self.pixelSize = pixelSize
            self.band = band
        }
    }

    public enum RenderError: Error {
        case invalidPixelSize
        case contextUnavailable
        case gradientUnavailable
        case imageUnavailable
        case pngEncodingFailed
    }

    /// The ten names required by `iconutil`; physical size does not choose the band by itself.
    public static let slots: [Slot] = [
        Slot(fileName: "icon_16x16.png", pixelSize: 16, band: .small),
        Slot(fileName: "icon_16x16@2x.png", pixelSize: 32, band: .small),
        Slot(fileName: "icon_32x32.png", pixelSize: 32, band: .mid),
        Slot(fileName: "icon_32x32@2x.png", pixelSize: 64, band: .mid),
        Slot(fileName: "icon_128x128.png", pixelSize: 128, band: .large),
        Slot(fileName: "icon_128x128@2x.png", pixelSize: 256, band: .large),
        Slot(fileName: "icon_256x256.png", pixelSize: 256, band: .large),
        Slot(fileName: "icon_256x256@2x.png", pixelSize: 512, band: .large),
        Slot(fileName: "icon_512x512.png", pixelSize: 512, band: .large),
        Slot(fileName: "icon_512x512@2x.png", pixelSize: 1024, band: .large),
    ]

    public static let previewSlot = Slot(fileName: "preview.png", pixelSize: 1024, band: .large)

    public static func metrics(for band: SizeBand) -> Metrics {
        switch band {
        case .small:
            return Metrics(lineWidth: 112, dotDiameter: 158, hubWidth: 190, spread: 200,
                           translationX: -101.75)
        case .mid:
            return Metrics(lineWidth: 78, dotDiameter: 132, hubWidth: 200, spread: 215,
                           translationX: -82.50)
        case .large:
            return Metrics(lineWidth: 40, dotDiameter: 104, hubWidth: 210, spread: 230,
                           translationX: -56.75)
        }
    }

    /// Returns the final 8-bit PNG for a logical icon slot. `backgroundOnly` is an offline
    /// oracle for endpoint contrast; the generator always leaves it false.
    public static func pngData(for slot: Slot, backgroundOnly: Bool = false,
                               translationOverride: CGFloat? = nil) throws -> Data {
        guard slot.pixelSize > 0 else { throw RenderError.invalidPixelSize }
        let pixelSize = slot.pixelSize
        guard let context = makeContext(pixelSize: pixelSize) else {
            throw RenderError.contextUnavailable
        }
        context.setAllowsAntialiasing(true)
        context.setShouldAntialias(true)
        context.clear(CGRect(x: 0, y: 0, width: pixelSize, height: pixelSize))

        let scale = CGFloat(pixelSize) / 1024
        context.saveGState()
        context.scaleBy(x: scale, y: scale)
        try drawBackground(in: context)
        if !backgroundOnly {
            drawGlyph(in: context, band: slot.band, translationOverride: translationOverride)
        }
        context.restoreGState()

        guard let image = context.makeImage() else { throw RenderError.imageUnavailable }
        let representation = NSBitmapImageRep(cgImage: image)
        guard let data = representation.representation(using: .png, properties: [:]) else {
            throw RenderError.pngEncodingFailed
        }
        return data
    }

    public static func previewPNGData() throws -> Data {
        try pngData(for: previewSlot)
    }

    private static let canvasBounds = CGRect(x: 100, y: 100, width: 824, height: 824)
    private static let canvasCornerRadius: CGFloat = 185
    private static let mid: CGFloat = 512
    private static let hubY: CGFloat = 447
    private static let hubHeight: CGFloat = 130
    private static let hubCornerRadius: CGFloat = 34
    private static let branchControl1 = CGPoint(x: 600, y: mid)
    private static let branchControl2X: CGFloat = 610

    private static func makeContext(pixelSize: Int) -> CGContext? {
        guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) else { return nil }
        let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue
            | CGBitmapInfo.byteOrder32Big.rawValue
        return CGContext(data: nil,
                         width: pixelSize,
                         height: pixelSize,
                         bitsPerComponent: 8,
                         bytesPerRow: pixelSize * 4,
                         space: colorSpace,
                         bitmapInfo: bitmapInfo)
    }

    private static func cgColor(_ rgb: Palette.RGB) -> CGColor {
        let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!
        return CGColor(colorSpace: colorSpace,
                       components: [CGFloat(rgb.red), CGFloat(rgb.green), CGFloat(rgb.blue), 1])!
    }

    private static func drawBackground(in context: CGContext) throws {
        guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
              let gradient = CGGradient(
                colorsSpace: colorSpace,
                colors: [cgColor(Palette.light.accentRGB),
                         cgColor(Palette.iconGradientBottomRGB)] as CFArray,
                locations: [0, 1]) else {
            throw RenderError.gradientUnavailable
        }
        let rounded = CGPath(roundedRect: canvasBounds,
                             cornerWidth: canvasCornerRadius,
                             cornerHeight: canvasCornerRadius,
                             transform: nil)
        context.saveGState()
        context.addPath(rounded)
        context.clip()
        // DESIGN: y=1024 is accent, y=0 is the derived darker stop.
        context.drawLinearGradient(gradient,
                                   start: CGPoint(x: mid, y: 1024),
                                   end: CGPoint(x: mid, y: 0),
                                   options: [])
        context.restoreGState()
    }

    private static func drawGlyph(in context: CGContext, band: SizeBand,
                                  translationOverride: CGFloat?) {
        let metrics = metrics(for: band)
        context.saveGState()
        context.translateBy(x: translationOverride ?? metrics.translationX, y: 0)
        let palette = Palette.light
        let ink = cgColor(palette.creamTextRGB)
        let endpointInk = cgColor(palette.creamTextRGB)
        let start = CGPoint(x: 250 + metrics.hubWidth, y: mid)
        let endpoints = [
            CGPoint(x: 742, y: mid + metrics.spread),
            CGPoint(x: 766, y: mid),
            CGPoint(x: 742, y: mid - metrics.spread),
        ]

        context.setStrokeColor(ink)
        context.setLineWidth(metrics.lineWidth)
        context.setLineCap(.round)
        for endpoint in endpoints {
            let path = CGMutablePath()
            path.move(to: start)
            path.addCurve(to: endpoint,
                          control1: branchControl1,
                          control2: CGPoint(x: branchControl2X, y: endpoint.y))
            context.addPath(path)
            context.strokePath()
        }

        context.setFillColor(endpointInk)
        for endpoint in endpoints {
            context.fillEllipse(in: CGRect(x: endpoint.x - metrics.dotDiameter / 2,
                                            y: endpoint.y - metrics.dotDiameter / 2,
                                            width: metrics.dotDiameter,
                                            height: metrics.dotDiameter))
        }

        let hub = CGPath(roundedRect: CGRect(x: 250, y: hubY,
                                             width: metrics.hubWidth, height: hubHeight),
                         cornerWidth: hubCornerRadius,
                         cornerHeight: hubCornerRadius,
                         transform: nil)
        context.addPath(hub)
        context.setFillColor(ink)
        context.fillPath()
        context.restoreGState()
    }
}
