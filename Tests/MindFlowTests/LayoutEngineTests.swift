import XCTest
@testable import MindFlow

final class LayoutEngineTests: XCTestCase {
    func testChildrenGrowRightwardAndSorted() {
        let root = MindNode(text: "Root", children: [
            MindNode(text: "A"), MindNode(text: "B"), MindNode(text: "C"),
        ])
        let layouts = LayoutEngine.layout(root: root)
        let rootLayout = layouts[root.id]!

        for child in root.children {
            let childLayout = layouts[child.id]!
            XCTAssertGreaterThan(childLayout.frame.minX, rootLayout.frame.maxX)
            XCTAssertGreaterThan(childLayout.depth, 0)
        }
        let ys = root.children.map { layouts[$0.id]!.frame.midY }
        XCTAssertEqual(ys, ys.sorted(), "children should be ordered top to bottom")
    }

    func testMiddleChildCenteredOnRoot() {
        let root = MindNode(text: "Root", children: [
            MindNode(text: "A"), MindNode(text: "B"), MindNode(text: "C"),
        ])
        let layouts = LayoutEngine.layout(root: root)
        let middle = layouts[root.children[1].id]!.frame.midY
        XCTAssertEqual(middle, layouts[root.id]!.frame.midY, accuracy: 0.5)
    }

    func testCollapsedNodeHidesDescendants() {
        let grandchild = MindNode(text: "G")
        let child = MindNode(text: "C", collapsed: true, children: [grandchild])
        let root = MindNode(text: "Root", children: [child])
        let layouts = LayoutEngine.layout(root: root)
        XCTAssertNil(layouts[grandchild.id])
        XCTAssertNotNil(layouts[child.id])
    }

    func testDeepSubtreeParentCentered() {
        let leaf = MindNode(text: "L")
        let mid = MindNode(text: "M", children: [leaf])
        let root = MindNode(text: "Root", children: [mid])
        let layouts = LayoutEngine.layout(root: root)
        XCTAssertEqual(layouts[mid.id]!.frame.midY, layouts[root.id]!.frame.midY, accuracy: 0.5)
        XCTAssertEqual(layouts[leaf.id]!.frame.midY, layouts[mid.id]!.frame.midY, accuracy: 0.5)
    }

    func testNodeUpdateMutatesNestedNode() {
        var root = MindNode(text: "Root", children: [MindNode(text: "A", children: [MindNode(text: "B")])])
        let b = root.children[0].children[0]
        XCTAssertTrue(root.update(b.id) { $0.text = "B2" })
        XCTAssertEqual(root.children[0].children[0].text, "B2")
        XCTAssertFalse(root.update(UUID(), { _ in }))
    }

    func testRemoveReturnsRemovedNode() {
        let a = MindNode(text: "A")
        var root = MindNode(text: "Root", children: [a, MindNode(text: "B")])
        let removed = root.remove(a.id)
        XCTAssertEqual(removed?.id, a.id)
        XCTAssertEqual(root.children.count, 1)
    }
}
