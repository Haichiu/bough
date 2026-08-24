import pathlib
p = pathlib.Path("Checks/MindFlowChecks.swift")
s = p.read_text()
old = '- idea A\n- idea B\n  - sub idea"'
new = '- idea A\\n- idea B\\n  - sub idea"'
s = s.replace(old, new)
p.write_text(s)
print("fixed")
