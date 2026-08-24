import pathlib
p = pathlib.Path("Sources/MindFlowKit/ContentView.swift")
s = p.read_text()
s = s.replace("id: \\.\\.id)", "id: \\.id)")
s = s.replace("\\\\.id)", "\\.id)")
# Fix any remaining double-escaped keypaths
s = s.replace("\\.\\.id", "\\.id")
p.write_text(s)
print("done")
