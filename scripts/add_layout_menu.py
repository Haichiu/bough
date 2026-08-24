path = "Sources/MindFlow/MindFlowApp.swift"
s = open(path).read()
block = """            CommandMenu("\u7248\u9762") {
                Button("\u908f\u8f2f\u5716\uff08\u53f3\u5c55\uff09") { vm.setDirection(.logicRight) }
                    .keyboardShortcut("1", modifiers: [.command, .option])
                Button("\u5e73\u8861\u5716\uff08\u5de6\u53f3\uff09") { vm.setDirection(.balanced) }
                    .keyboardShortcut("2", modifiers: [.command, .option])
                Button("\u9b5a\u9aa8\u5716") { vm.setDirection(.fishbone) }
                    .keyboardShortcut("3", modifiers: [.command, .option])
                Button("\u62ec\u865f\u5716") { vm.setDirection(.bracket) }
                    .keyboardShortcut("4", modifiers: [.command, .option])
            }
            CommandMenu("\u5c0b\u627e") {"""
s = s.replace("            CommandMenu("\\u5c0b\\u627e") {", block)
# Also fix the escaped version
s = s.replace('            CommandMenu("\u5c0b\u627e") {', block)
open(path, "w").write(s)
print("layout menu added")