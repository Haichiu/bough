import pathlib
p = pathlib.Path("Sources/MindFlowKit/ViewModel.swift")
s = p.read_text()
start = s.find("    // MARK: - Haptic feedback")
if start >= 0:
    end = s.find("\n    // MARK:", start + 10)
    if end < 0:
        end = s.find("\n", s.rfind("}", 0, s.find("Manual position nudges")))
    if end >= 0:
        s = s[:start] + s[end+1:]
p.write_text(s)
print("haptic removed")