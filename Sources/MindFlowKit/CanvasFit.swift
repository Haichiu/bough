import CoreGraphics

/// How far to zoom so a map's content sits inside the canvas.
///
/// This rule used to live inside `MapCanvasView` as two near-identical private functions,
/// `centerContent` and `fitToView`, which meant nothing could check it and a defect in it
/// was invisible: the shipped build opened maps at the 1.2 cap and let the lower half fall
/// off the bottom of the window. The rule is small enough to state plainly and to test.
public enum CanvasFit {
    /// What the user can reach by zooming manually.
    public static let zoomRange: ClosedRange<CGFloat> = 0.25...3

    /// Opening a two-node map should not blow it up to fill the screen, so enlarging on
    /// first sight stops here even when there is room to spare.
    public static let maxInitial: CGFloat = 1.2

    /// Content larger than the viewport is shrunk until it fits; smaller content is
    /// enlarged only up to `maxInitial`. Degenerate content leaves the zoom untouched
    /// rather than producing a NaN or a zero scale.
    public static func scale(content: CGSize, viewport: CGSize) -> CGFloat {
        guard content.width > 0, content.height > 0,
              viewport.width > 0, viewport.height > 0 else { return 1 }
        let fit = min(viewport.width / content.width,
                      viewport.height / content.height,
                      maxInitial)
        return min(zoomRange.upperBound, max(zoomRange.lowerBound, fit))
    }
}