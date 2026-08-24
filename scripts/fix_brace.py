path = "Checks/MindFlowChecks.swift"
s = open(path).read()
// Remove the FIRST "if failures == 0 {" that was incorrectly inserted by the block
first = s.find("if failures == 0 {")
if first >= 0:
    s = s[:first] + s[first + len("if failures == 0 {"):]
open(path, "w").write(s)
print("removed extra marker")