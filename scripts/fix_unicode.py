import pathlib
p = pathlib.Path("Sources/MindFlowKit/ContentView.swift")
s = p.read_text()
// Replace broken \uXXXX sequences with actual characters
replacements = {
    "\\u2190": "\u2190",  # left arrow
    "\\u2192": "\u2192",  # right arrow
    "\\u2191": "\u2191",  # up arrow
    "\\u2193": "\u2193",  # down arrow
    "\\u2318": "\u2318",  # command key
    "\\u21e7": "\u21e7",  # shift key
    "\\u2303": "\u2303",  # control key
    "\\u00b7": "\u00b7",  # middle dot
}
for old, new in replacements.items():
    s = s.replace(old, new)
p.write_text(s)
print("fixed unicode escapes")