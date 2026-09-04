import CoreGraphics

/// Pure screen↔map coordinate transform for the canvas.
///
/// Extracted from the two byte-identical `toMap` closures that lived in
/// MapCanvasView — `visibleItems` (culling rect, currently unwired) and
/// `completeLasso` (batch-selection rect). The extraction is verbatim: the
/// screen→map formula and its operand order match the pre-extraction code
/// exactly, and `mapToScreen` is the same algebra solved the other way
/// (the shape autoScrollToward/revealNode use inline — this type does not
/// replace them).
///
/// Semantics: the map layer is centred in the viewport, panned by `pan` and
/// scaled about the centre of `bounds`. `origin` shifts map space so the
/// top-leading corner of `bounds` is the zero of the layer's local space.
/// Pan and zoom are inputs, never mutated here.
public struct CanvasTransform: Equatable {
    public var viewport: CGSize
    public var bounds: CGRect
    public var pan: CGSize
    public var scale: CGFloat

    public init(viewport: CGSize, bounds: CGRect, pan: CGSize, scale: CGFloat) {
        self.viewport = viewport
        self.bounds = bounds
        self.pan = pan
        self.scale = scale
    }

    /// Map-space point at the top-leading corner of `bounds`.
    public var origin: CGPoint { CGPoint(x: -bounds.minX, y: -bounds.minY) }

    /// Screen (viewport-local) point → document map-space point.
    public func screenToMap(_ screen: CGPoint) -> CGPoint {
        let center = CGPoint(x: bounds.width / 2, y: bounds.height / 2)
        let sx = screen.x - (viewport.width - bounds.width) / 2 - pan.width
        let sy = screen.y - (viewport.height - bounds.height) / 2 - pan.height
        let qx = center.x + (sx - center.x) / scale
        let qy = center.y + (sy - center.y) / scale
        return CGPoint(x: qx - origin.x, y: qy - origin.y)
    }

    /// Document map-space point → screen (viewport-local) point. Exact inverse
    /// of `screenToMap` for finite inputs.
    public func mapToScreen(_ map: CGPoint) -> CGPoint {
        let center = CGPoint(x: bounds.width / 2, y: bounds.height / 2)
        let qx = map.x + origin.x
        let qy = map.y + origin.y
        let sx = center.x + (qx - center.x) * scale
        let sy = center.y + (qy - center.y) * scale
        return CGPoint(x: (viewport.width - bounds.width) / 2 + sx + pan.width,
                       y: (viewport.height - bounds.height) / 2 + sy + pan.height)
    }
}
