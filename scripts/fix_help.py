path = "Sources/MindFlowKit/ContentView.swift"
lines = open(path).readlines()
out = [l for i, l in enumerate(lines) if not (610 <= i <= 615)]
open(path, "w").writelines(out)
print("removed", len(lines) - len(out), "lines")
