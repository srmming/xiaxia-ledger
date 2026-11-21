import ArgumentParser
import FinanceCore
import Foundation

/// `fin insight`：AI 意见。写进账本后，app 的总览和「AI 意见」页会显示。
struct InsightCommand: ParsableCommand {
    static let configuration = CommandConfiguration(commandName: "insight", abstract: "AI 意见：写本月点评和提醒、列出来、标「知道了」。",
                                                    subcommands: [Add.self, List.self, Dismiss.self])

    struct Add: ParsableCommand {
        static let configuration = CommandConfiguration(commandName: "add", abstract: "写一条意见。本月点评每月每账本一条，新的替换旧的。")
        @OptionGroup var w: WriteOptions
        @Argument(help: "种类：review（本月点评）、alert（留意）、tip（建议）、good（好消息）、action（要处理）。") var kind: String
        @Argument(help: "一句话结论。") var title: String
        @Option(help: "两三句解释。") var body: String = ""
        @Option(help: "哪个月，如 2026-11；默认这个月。") var month: String?
        @Option(help: "账本 id；不填 = 全部。") var book: String?
        @Option(help: "关联的东西，如 category:超市。") var metric: String?

        func run() throws {
            let kinds: [String: Insight.Kind] = ["review": .monthlyReview, "alert": .alert, "tip": .tip, "good": .goodNews, "action": .action]
            guard let k = kinds[kind.lowercased()] else { throw ValidationError("种类只能是 review / alert / tip / good / action") }
            let ym: YearMonth
            if let month { guard let v = YearMonth(month) else { throw ValidationError("月份要写成 2026-11") }; ym = v } else { ym = LocalDate.today.yearMonth }
            var ledger = try loadLedger()
            if let book, !ledger.books.contains(where: { $0.id == book }) { throw ValidationError("没有这个账本：\(book)") }
            let change = try ledger.addInsight(Insight(month: ym, bookID: book, kind: k, title: title, body: body, metric: metric, author: w.who),
                                               author: w.who)
            try finish(ledger, change, w)
        }
    }

    struct List: ParsableCommand {
        static let configuration = CommandConfiguration(commandName: "list", abstract: "列出意见（默认没点「知道了」的）。")
        @Option(help: "月份，如 2026-11。") var month: String?
        @Option(help: "账本 id。") var book: String?
        @Flag(help: "连点过「知道了」的也列出。") var all = false
        @Flag(help: "输出 JSON。") var json = false

        func run() throws {
            let ledger = try loadLedger()
            let ym = try month.map { m -> YearMonth in
                guard let v = YearMonth(m) else { throw ValidationError("月份要写成 2026-11") }
                return v
            }
            let list = ledger.insights(month: ym, bookID: book, includeDismissed: all)
            if json { try Output.json(list); return }
            if list.isEmpty { print("还没有意见。"); return }
            for i in list {
                let flag = i.dismissedAt == nil ? "" : "（知道了）"
                print("\(i.id.uuidString.prefix(8).lowercased())  \(i.month)  \(i.kind.label)\(flag)  \(i.author)：\(i.title)")
                if !i.body.isEmpty { print("          \(i.body)") }
            }
        }
    }

    struct Dismiss: ParsableCommand {
        static let configuration = CommandConfiguration(commandName: "dismiss", abstract: "把一条意见标成「知道了」。")
        @OptionGroup var w: WriteOptions
        @Argument(help: "意见 id（前 8 位就行）。") var id: String

        func run() throws {
            var ledger = try loadLedger()
            guard let hit = ledger.findInsight(id) else { throw ValidationError("没有这条意见，先用 fin insight list 看 id") }
            let change = try ledger.dismissInsight(hit.id, author: w.who)
            try finish(ledger, change, w)
        }
    }
}
