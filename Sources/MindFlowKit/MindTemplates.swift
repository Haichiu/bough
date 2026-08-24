import Foundation

/// Ready-made starting points so newcomers never face a blank canvas.
public enum MindTemplates {
    public static let all: [(name: String, subtitle: String)] = [
        ("空白", "從零開始，只有中心主題"),
        ("會議記錄", "出席、議題、決議、待辦（自動帶今天日期）"),
        ("專案計畫", "目標、里程碑、資源、風險"),
        ("每週回顧", "完成、下一步、學到的事（自動帶今天日期）"),
    ]

    public static func make(_ name: String, date: Date = Date()) -> MindDocument {
        let formatter = DateFormatter()
        formatter.dateFormat = "M月d日"
        let today = formatter.string(from: date)

        func node(_ text: String, children: [MindNode] = []) -> MindNode {
            MindNode(text: text, children: children)
        }

        switch name {
        case "會議記錄":
            return MindDocument(title: "會議記錄 \(today)", root: node("會議主題（\(today)）", children: [
                node("出席者"),
                node("討論議題", children: [node("議題一"), node("議題二")]),
                node("決議事項"),
                node("待辦行動", children: [node("負責人＋期限")]),
            ]))
        case "專案計畫":
            return MindDocument(title: "專案計畫", root: node("專案名稱", children: [
                node("目標", children: [node("成功長什麼樣？")]),
                node("里程碑", children: [node("第一階段"), node("第二階段")]),
                node("資源與分工"),
                node("風險與備案"),
            ]))
        case "每週回顧":
            return MindDocument(title: "每週回顧 \(today)", root: node("本週回顧（\(today)）", children: [
                node("完成了什麼"),
                node("卡住什麼"),
                node("下週最重要的一件事"),
                node("學到的事"),
            ]))
        default:
            return .new()
        }
    }
}
