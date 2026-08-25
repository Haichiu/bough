import pathlib
p = pathlib.Path("Sources/MindFlowKit/MapCanvasView.swift")
s = p.read_text()

# Add CachedLayout struct before MapCanvasView
cache_struct = """/// Immutable snapshot of a completed layout computation.
struct CachedLayout {
    let layouts: [UUID: NodeLayout]
    let bounds: CGRect
    let origin: CGPoint
}"""

if "CachedLayout" not in s:
    s = s.replace("struct MapCanvasView: View {", cache_struct + "\n\nstruct MapCanvasView: View {")

# Add @State for cached layout
state_line = '    @State private var layoutCache: CachedLayout?'
if "layoutCache" not in s:
    s = s.replace("    private static let zoomRange:", state_line + "\n\n    private static let zoomRange:")

# Replace direct layout computation with cached version
old_body = """            let layouts = LayoutEngine.layout(root: vm.document.root, direction: vm.direction,
                                              offsets: vm.document.offsets)
            // (offsets already applied here — single source of truth)"""
new_body = """            // Use cached layout if document hasn't changed
            let docHash = vm.document.hashValue
            let currentDirection = vm.direction
            let computed: CachedLayout
            if let cached = layoutCache,
               cached.layouts.count > 0 || vm.document.root.children.isEmpty {
                computed = cached
            } else {
                let layouts = LayoutEngine.layout(root: vm.document.root, direction: currentDirection,
                                                  offsets: vm.document.offsets)
                let b = LayoutEngine.contentBounds(of: layouts).insetBy(dx: -180, dy: -140)
                let o = CGPoint(x: -b.minX, y: -b.minY)
                computed = CachedLayout(layouts: layouts, bounds: b, origin: o)
            }
            let layouts = computed.layouts
            let theme = Theme.named(vm.document.themeName)
            let bounds = LayoutEngine.contentBounds(of: layouts).insetBy(dx: -180, dy: -140)
            let origin = CGPoint(x: -bounds.minX, y: -bounds.minY)
            let items = nodeItems(layouts: layouts)
            let dropTarget = drag.flatMap { hitTest(point: $0.current, draggedID: $0.id, layouts: layouts) }
            let focusIDs = vm.focusSet()"""

if old_body in s:
    s = s.replace(old_body, new_body)
    print("replaced body computation")
else:
    print("WARN: old_body not found exactly")
    # Try line-by-line approach
    lines = s.split("\n")
    for i, l in enumerate(lines):
        if "let layouts = LayoutEngine.layout" in l:
        # Replace this block with cached version
            lines[i] = "            let layouts = layoutCache?.layouts ?? [:]"
            break
    p.write_text("\n".join(lines))
print("done")