import ArgumentParser
import FinanceCore
import Foundation

// 自己动手记账的几样：拆开、复制、退款、标签、重复记账。规则都在 FinanceCore/ManualEntry.swift，和 app 一样。

struct SplitCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "split", abstract: "把一笔拆成几笔不同分类，合计要等于原来的金额。",
        discussion: "例子：fin split ab12cd34 30:超市 18,30:日用品    第三段可以写新说明：18,30:日用品:洗衣液")
    @OptionGroup var w: WriteOptions
    @Argument(help: "流水编号（fin tx 里的 8 位）。") var id: String
    @Argument(help: "每份：金额:分类[:说明]，金额写正数。") var parts: [String]

    func run() throws {
        var ledger = try loadLedger()
        let t = try ledger.findTransactions([id])[0]
        let list = try parts.map { p -> SplitPart in
            guard let part = SplitPart(parsing: p) else { throw ValidationError("看不懂「\(p)」，要写成 30:超市") }
            return part
        }
        try finish(ledger, try ledger.splitTransaction(t.id, parts: list, author: w.who), w)
    }
}

struct CopyCommand: ParsableCommand {
    static let configuration = CommandConfiguration(commandName: "copy", abstract: "照着一笔再记一笔，日期默认今天。")
    @OptionGroup var w: WriteOptions
    @Argument(help: "流水编号。") var id: String
    @Option(help: "新的日期，默认今天。") var date: String?

    func run() throws {
        var ledger = try loadLedger()
        let t = try ledger.findTransactions([id])[0]
        try finish(ledger, try ledger.duplicateTransaction(t.id, date: try parseDate(date), author: w.who), w)
    }
}

struct RefundCommand: ParsableCommand {
    static let configuration = CommandConfiguration(commandName: "refund", abstract: "给一笔支出记退款：钱回到同一个账户，分类「退款」，冲减支出。")
    @OptionGroup var w: WriteOptions
    @Argument(help: "原来那笔支出的编号。") var id: String
    @Option(help: "退了多少，不填就是全额。") var amount: String?
    @Option(help: "退款日期，默认今天。") var date: String?

    func run() throws {
        var ledger = try loadLedger()
        let t = try ledger.findTransactions([id])[0]
        let change = try ledger.addRefund(of: t.id, amount: try amount.map { try parseAmount($0).magnitude },
                                          date: try parseDate(date), author: w.who)
        try finish(ledger, change, w)
    }
}

struct TagCommand: ParsableCommand {
    static let configuration = CommandConfiguration(commandName: "tag", abstract: "给几笔流水加 / 去标签。例子：fin tag ab12cd34 ef56ab78 --add 旅行")
    @OptionGroup var w: WriteOptions
    @Argument(help: "流水编号，可以一次写多个。") var ids: [String]
    @Option(help: "要加的标签，可以写几次。") var add: [String] = []
    @Option(help: "要去掉的标签，可以写几次。") var remove: [String] = []

    func run() throws {
        var ledger = try loadLedger()
        let txs = try ledger.findTransactions(ids)
        try finish(ledger, try ledger.tagTransactions(txs.map(\.id), add: add, remove: remove, author: w.who), w)
    }
}

struct RepeatCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "repeat", abstract: "重复记账：房租、话费这种固定的，到日子自动记。新建用 fin add --repeat monthly，或 fin repeat set 把已有的一笔设成重复。",
        subcommands: [List.self, Set_.self, Run.self, Pause.self, Resume.self, Remove.self], defaultSubcommand: List.self)

    struct List: ParsableCommand {
        static let configuration = CommandConfiguration(commandName: "list", abstract: "列出所有重复记账。")
        @Flag(name: .long, help: "输出 JSON。") var json = false
        func run() throws {
            let ledger = try loadLedger()
            if json { return try Output.json(ledger.recurring) }
            if ledger.recurring.isEmpty { print("还没有重复记账。用 fin add … --repeat monthly 新建。") }
            for r in ledger.recurring {
                print("\(r.id.uuidString.prefix(8).lowercased())\t\(r.summary)\t下次 \(r.nextDate)\(r.until.map { "\t到 \($0) 为止" } ?? "")\(r.paused ? "\t（暂停中）" : "")")
            }
        }
    }

    struct Set_: ParsableCommand {
        static let configuration = CommandConfiguration(commandName: "set", abstract: "把已有的一笔设成重复，从它的下一期开始自动记。")
        @OptionGroup var w: WriteOptions
        @Argument(help: "流水编号。") var id: String
        @Argument(help: "weekly、monthly 或 yearly。") var frequency: String
        @Option(help: "到哪天为止（可不填）。") var until: String?
        func run() throws {
            var ledger = try loadLedger()
            guard let f = Recurring.Frequency(rawValue: frequency) else { throw ValidationError("要写 weekly、monthly 或 yearly") }
            let t = try ledger.findTransactions([id])[0]
            try finish(ledger, try ledger.makeRecurring(t.id, frequency: f, until: try until.map { try parseDate($0) }, author: w.who), w)
        }
    }

    struct Run: ParsableCommand {
        static let configuration = CommandConfiguration(commandName: "run", abstract: "把到日子的重复记账记上（app 打开时也会自动做）。")
        @OptionGroup var w: WriteOptions
        @Option(help: "算到哪天，默认今天。") var date: String?
        func run() throws {
            var ledger = try loadLedger()
            guard let change = ledger.postDueRecurring(today: try parseDate(date), author: w.who) else {
                return print("没有到日子的重复记账。")
            }
            try finish(ledger, change, w)
        }
    }

    static func find(_ ledger: Ledger, _ key: String) throws -> Recurring {
        let hits = ledger.findRecurring(key)
        guard hits.count == 1 else {
            throw ValidationError(hits.isEmpty ? "找不到「\(key)」这条重复记账（fin repeat list 看全部）" : "「\(key)」对上了 \(hits.count) 条，写编号")
        }
        return hits[0]
    }

    struct Pause: ParsableCommand {
        static let configuration = CommandConfiguration(commandName: "pause", abstract: "暂停一条重复记账。")
        @OptionGroup var w: WriteOptions
        @Argument(help: "编号或说明。") var key: String
        func run() throws {
            var ledger = try loadLedger()
            var r = try RepeatCommand.find(ledger, key)
            r.paused = true
            try finish(ledger, try ledger.updateRecurring(r, author: w.who), w)
        }
    }

    struct Resume: ParsableCommand {
        static let configuration = CommandConfiguration(commandName: "resume", abstract: "继续一条暂停的重复记账。")
        @OptionGroup var w: WriteOptions
        @Argument(help: "编号或说明。") var key: String
        func run() throws {
            var ledger = try loadLedger()
            var r = try RepeatCommand.find(ledger, key)
            r.paused = false
            try finish(ledger, try ledger.updateRecurring(r, author: w.who), w)
        }
    }

    struct Remove: ParsableCommand {
        static let configuration = CommandConfiguration(commandName: "rm", abstract: "停掉一条重复记账（已经记上的流水不动）。")
        @OptionGroup var w: WriteOptions
        @Argument(help: "编号或说明。") var key: String
        func run() throws {
            var ledger = try loadLedger()
            let r = try RepeatCommand.find(ledger, key)
            try finish(ledger, try ledger.removeRecurring(r.id, author: w.who), w)
        }
    }
}
