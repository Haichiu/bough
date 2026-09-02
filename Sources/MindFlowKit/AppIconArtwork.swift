import AppKit
import CoreGraphics
import Foundation

/// Programmatic source of truth for the macOS app icon.
///
/// Geometry is authored in the 1024-point DESIGN coordinate system (y-up, matching the
/// CoreGraphics drawing context; raster rows map as row = 1024 - design y) and rasterized
/// at each slot's physical pixel size. The T-047 glyph speaks the product's own shape
/// language: a filled rounded root card on the left, two stroked rounded child cards on
/// the right joined by rounded horizontal-vertical-horizontal elbow connectors.
/// Hierarchy comes from size — the root card's area is more than twice either child —
/// and the two children are deliberately NOT horizontal mirrors of each other (different
/// sizes, different elbow lengths), because a mirrored pair reads as decoration instead
/// of structure.
public enum AppIconArtwork {
    public enum SizeBand: String, Equatable {
        case small
        case mid
        case large
    }

    /// One rounded card of the glyph. `rect` is the card's outer ink bound: a filled card
    /// fills it exactly, a stroked card draws its stroke inward from it.
    public struct CardSpec: Equatable {
        public let rect: CGRect
        public let cornerRadius: CGFloat
        public let filled: Bool

        public init(rect: CGRect, cornerRadius: CGFloat, filled: Bool) {
            self.rect = rect
            self.cornerRadius = cornerRadius
            self.filled = filled
        }
    }

    /// A rounded horizontal-vertical-horizontal elbow from the root card's right edge to
    /// a child card's left edge.
    public struct ElbowSpec: Equatable {
        public let start: CGPoint
        public let junctionX: CGFloat
        public let endX: CGFloat
        public let endY: CGFloat
        public let cornerRadius: CGFloat

        public init(start: CGPoint, junctionX: CGFloat, endX: CGFloat, endY: CGFloat,
                    cornerRadius: CGFloat) {
            self.start = start
            self.junctionX = junctionX
            self.endX = endX
            self.endY = endY
            self.cornerRadius = cornerRadius
        }

        /// Centerline length of the horizontal-vertical-horizontal polyline.
        public var polylineLength: CGFloat {
            abs(junctionX - start.x) + abs(endY - start.y) + abs(endX - junctionX)
        }
    }

    public struct GlyphGeometry: Equatable {
        public let connectorLineWidth: CGFloat
        public let childStrokeWidth: CGFloat
        public let translationX: CGFloat
        public let root: CardSpec
        public let upperChild: CardSpec
        public let lowerChild: CardSpec
        public let upperElbow: ElbowSpec
        public let lowerElbow: ElbowSpec

        public init(connectorLineWidth: CGFloat, childStrokeWidth: CGFloat,
                    translationX: CGFloat, root: CardSpec, upperChild: CardSpec,
                    lowerChild: CardSpec, upperElbow: ElbowSpec, lowerElbow: ElbowSpec) {
            self.connectorLineWidth = connectorLineWidth
            self.childStrokeWidth = childStrokeWidth
            self.translationX = translationX
            self.root = root
            self.upperChild = upperChild
            self.lowerChild = lowerChild
            self.upperElbow = upperElbow
            self.lowerElbow = lowerElbow
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

    // MARK: - DESIGN-space skeleton (named constants)

    private static let canvasBounds = CGRect(x: 100, y: 100, width: 824, height: 824)
    private static let canvasCornerRadius: CGFloat = 185
    private static let mid: CGFloat = 512

    /// The filled root card, left of center and clearly the largest element.
    private static let rootCardRect = CGRect(x: 190, y: 352, width: 400, height: 320)
    private static let rootCardCornerRadius: CGFloat = 80
    /// The upper child card (visually top-right): wider and taller than the lower one.
    private static let upperChildRect = CGRect(x: 640, y: 580, width: 240, height: 215)
    /// The lower child card (visually bottom-right): deliberately smaller, so the pair is
    /// not a horizontal mirror.
    private static let lowerChildRect = CGRect(x: 680, y: 225, width: 200, height: 190)
    /// The corner radius the stroke's inner edge keeps on every band.
    private static let childInnerCornerRadius: CGFloat = 24
    /// Where each elbow leaves the root card's right edge. The exits sit at different
    /// heights and feed elbows of different lengths.
    private static let upperElbowExitY: CGFloat = 606
    private static let lowerElbowExitY: CGFloat = 424
    /// The junction of each elbow sits this fraction of the way from the root edge to the
    /// child's left edge, so unequal child positions yield unequal elbow lengths.
    private static let elbowJunctionFraction: CGFloat = 0.5
    private static let elbowCornerRadius: CGFloat = 15
    /// Per-band child-card horizontal offsets. The fat strokes of the small and mid
    /// bands carry so much ink mass that the untranslated centroid needs an extra
    /// rightward pull for the zero-translation control to reject with margin, and the
    /// longer elbows read better at coarse sizes.
    private static let smallBandChildOffsetX: CGFloat = 60
    private static let midBandChildOffsetX: CGFloat = 12

    /// Per-band metrics. `connectorLineWidth` is the elbow stroke; child cards stroke
    /// lighter, mirroring the product's lighter child-link weight. `translationX` places
    /// the rendered ink centroid on the canvas midline (optical centering for a mark whose
    /// filled root outweighs its stroked children); the values are tuned against the
    /// raster and locked by the centroid gates.
    public static func geometry(for band: SizeBand) -> GlyphGeometry {
        let connector: CGFloat
        let childStroke: CGFloat
        let translation: CGFloat
        let offset: CGFloat
        switch band {
        case .small:
            connector = 112
            childStroke = 72
            translation = -66
            offset = smallBandChildOffsetX
        case .mid:
            connector = 78
            childStroke = 72
            translation = -39
            offset = midBandChildOffsetX
        case .large:
            connector = 40
            childStroke = 24
            translation = 24
            offset = 0
        }

        let childOffset = offset
        func childCard(_ rect: CGRect) -> CardSpec {
            CardSpec(rect: rect.offsetBy(dx: childOffset, dy: 0),
                     cornerRadius: childStroke / 2 + childInnerCornerRadius,
                     filled: false)
        }

        func elbow(exitY: CGFloat, child: CardSpec) -> ElbowSpec {
            let run = child.rect.minX - rootCardRect.maxX
            let junction = rootCardRect.maxX + elbowJunctionFraction * run
            let radius = min(elbowCornerRadius,
                             min(junction - rootCardRect.maxX, child.rect.minX - junction,
                                 abs(child.rect.midY - exitY)) / 2)
            return ElbowSpec(start: CGPoint(x: rootCardRect.maxX, y: exitY),
                             junctionX: junction,
                             endX: child.rect.minX,
                             endY: child.rect.midY,
                             cornerRadius: radius)
        }

        return GlyphGeometry(
            connectorLineWidth: connector,
            childStrokeWidth: childStroke,
            translationX: translation,
            root: CardSpec(rect: rootCardRect, cornerRadius: rootCardCornerRadius, filled: true),
            upperChild: childCard(upperChildRect),
            lowerChild: childCard(lowerChildRect),
            upperElbow: elbow(exitY: upperElbowExitY, child: childCard(upperChildRect)),
            lowerElbow: elbow(exitY: lowerElbowExitY, child: childCard(lowerChildRect)))
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
        let geometry = geometry(for: band)
        context.saveGState()
        context.translateBy(x: translationOverride ?? geometry.translationX, y: 0)
        let ink = cgColor(Palette.light.creamTextRGB)

        context.setFillColor(ink)
        context.addPath(CGPath(roundedRect: geometry.root.rect,
                               cornerWidth: geometry.root.cornerRadius,
                               cornerHeight: geometry.root.cornerRadius,
                               transform: nil))
        context.fillPath()

        context.setStrokeColor(ink)
        context.setLineWidth(geometry.connectorLineWidth)
        context.setLineCap(.round)
        context.setLineJoin(.round)
        for elbow in [geometry.upperElbow, geometry.lowerElbow] {
            context.addPath(elbowPath(for: elbow))
            context.strokePath()
        }

        context.setLineWidth(geometry.childStrokeWidth)
        for child in [geometry.upperChild, geometry.lowerChild] {
            let inset = geometry.childStrokeWidth / 2
            let innerRadius = child.cornerRadius - inset
            context.addPath(CGPath(roundedRect: child.rect.insetBy(dx: inset, dy: inset),
                                   cornerWidth: innerRadius,
                                   cornerHeight: innerRadius,
                                   transform: nil))
            context.strokePath()
        }
        context.restoreGState()
    }

    private static func elbowPath(for elbow: ElbowSpec) -> CGPath {
        let path = CGMutablePath()
        let r = elbow.cornerRadius
        let s = elbow.start.y
        let e = elbow.endY
        let x = elbow.junctionX
        path.move(to: elbow.start)
        path.addLine(to: CGPoint(x: x - r, y: s))
        if e > s {
            path.addArc(center: CGPoint(x: x - r, y: s + r), radius: r,
                        startAngle: -.pi / 2, endAngle: 0, clockwise: false)
            path.addLine(to: CGPoint(x: x, y: e - r))
            path.addArc(center: CGPoint(x: x + r, y: e - r), radius: r,
                        startAngle: .pi, endAngle: .pi / 2, clockwise: true)
        } else {
            path.addArc(center: CGPoint(x: x - r, y: s - r), radius: r,
                        startAngle: .pi / 2, endAngle: 0, clockwise: true)
            path.addLine(to: CGPoint(x: x, y: e + r))
            path.addArc(center: CGPoint(x: x + r, y: e + r), radius: r,
                        startAngle: .pi, endAngle: 3 * .pi / 2, clockwise: false)
        }
        path.addLine(to: CGPoint(x: elbow.endX, y: e))
        return path
    }
}
