import pathlib
p = pathlib.Path("Sources/MindFlowKit/NodeView.swift")
s = p.read_text()

old = """            Text("\(hiddenCount)")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 18, height: 18)
                .background(Circle().fill(branchColor))
                .overlay(Circle().stroke(Color(nsColor: .controlBackgroundColor), lineWidth: 1.5))
                .offset(x: 10)"""

new = """            Text("+\(hiddenCount)")
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 5)
                .padding(.vertical, 2)
                .background(Capsule().fill(branchColor))
                .overlay(Capsule().stroke(Color.white.opacity(0.8), lineWidth: 1))
                .offset(x: 12)"""

s = s.replace(old, new)

# Remove duplicate help line
s = s.replace(
    '.help(node.note.isEmpty ? "" : "備註：\(node.note)")
        .help(node.note.isEmpty ? "" : "備註：\(node.note)")',
    '.help(node.note.isEmpty ? "" : "備註：\(node.note)")'
)

p.write_text(s)
print("badge upgraded")