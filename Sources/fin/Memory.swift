import ArgumentParser
import FinanceCore
import Foundation

// 夏夏的记忆：MCP 工具（memory / remember / update_memory / forget_memory / tidy_memory / regulars）和 `fin memory`、`fin regulars`。
// 规则都在 FinanceCore/Memory.swift，这里只接参数。

extension MCPTools {
    static let memoryKinds: [String: Any] = ["type": "string", "enum": ["rule", "topic", "lesson"],
                                             "description": "rule = 规矩（每次必读，只放高频、确定的约定）；topic = 记得的事（默认）；lesson = 做事经验（标题用任务名）"]
    static let memorySources: [String: Any] = ["type": "string", "enum": ["said", "corrected", "confirmed", "observed"],
                                               "description": "said = 用户亲口说的（默认）；corrected = 用户纠正了你；confirmed = 你看出来、问过用户、用户说对；observed = 你自己看出来还没问过（只用于 lesson）"]
    static let memoryLinks: [String: Any] = ["type": "array", "items": ["type": "string"],
                                             "description": "跟哪些东西有关，聊到它们时好找到：category:工资、account:账户id、book:账本id、merchant:商户名、subscription:订阅名、goal:目标名、person:人名"]

    static let memoryTools: [[String: Any]] = [
        tool("memory", "夏夏的记忆。不填参数 = 用户定的规矩（全文）+ 其它记忆的目录 + 怎么用；id = 读一条的全文；query = 按关键词搜；link = 挂在某样东西上的（如 category:工资）；kind = 只看某一类的全文。聊到目录里有的话题、或要做导入 / 对账 / 月报之前先读。", [
            "id": prop("string", "记忆 id（前 8 位）或话题名"), "query": prop("string", "关键词，如「工资」「妈妈」「对账」"),
            "link": prop("string", "种类:名字，如 category:工资"), "kind": memoryKinds,
        ], readOnly: true),
        tool("remember", "记住一件事（记进夏夏的记忆，所有连上的 AI 和 app 都读得到）。先搜再记：同一件事已经有话题，就用 topic 加在它下面。标题写话题不写结论。能从流水算出来的数字、临时的事、你的猜测、卡号密码不记；你自己看出来的规律先问用户再记。", [
            "title": prop("string", "话题：这件事叫什么，如「工资」「转给妈妈的钱」「导入对账单」。加到已有话题时不用填"),
            "text": prop("string", "记住什么。一句话说清，单独看也看得懂。时间写具体的年月日（2027 年 3 月），不写「明年 3 月」「月底」这种过一阵就看不懂的"),
            "kind": memoryKinds, "source": memorySources,
            "quote": prop("string", "用户的原话（有就填，照原样，不用改时间）"),
            "story": prop("string", "当时出了什么事、怎么解决的（纠正和做事经验要填）"),
            "review_on": prop("string", "会过时的事填哪天回头看，如 2027-03-31"),
            "links": memoryLinks,
            "topic": prop("string", "加到已有的哪条下面：它的 id 或话题名"),
            "new_topic": prop("boolean", "提示有相近话题、但确实是另一件事时填 true"),
            "author": author, "dry_run": dryRun,
        ], required: ["text"], readOnly: false),
        tool("update_memory", "改一条记忆：说法变了就改那一行（不要另记一条）、改话题名、挪到另一类、换挂的东西、标成重要；keep=true 表示整理时用户说留着。只填要改的。", [
            "id": prop("string", "记忆 id（前 8 位）或话题名"),
            "line": prop("string", "改哪一行：memory 读出来每行开头那几位。只有一行时不用填"),
            "text": prop("string", "这一行的新说法"), "source": memorySources,
            "quote": prop("string", "原话（空字符串 = 清掉）"), "story": prop("string", "经过（空字符串 = 清掉）"),
            "review_on": prop("string", "哪天回头看（空字符串 = 清掉）"),
            "title": prop("string", "新话题名"), "kind": memoryKinds, "links": memoryLinks,
            "pinned": prop("boolean", "重要：每月整理时不列出来"),
            "keep": prop("boolean", "整理时用户说留着：半年内不再问"),
            "author": author, "dry_run": dryRun,
        ], required: ["id"], readOnly: false),
        tool("forget_memory", "删掉一条记忆，或其中一行（line）。默认能撤销；forever=true 是彻底忘掉：连改动记录里的痕迹一起抹掉、找不回来，先跟用户确认。", [
            "id": prop("string", "记忆 id（前 8 位）或话题名"),
            "line": prop("string", "只删这一行（不填 = 整条）"),
            "forever": prop("boolean", "彻底忘掉，不能撤销"),
            "author": author, "dry_run": dryRun,
        ], required: ["id"], readOnly: false),
        tool("tidy_memory", "每月整理记忆。不填参数 = 列出可能该清掉的（到期的、半年没用上的、挂的东西没了的、行数太多的），念给用户听；remove = 用户同意清掉的那几条的 id（一条改动，能撤销）；done=true = 过完一遍了，记下整理过了。", [
            "remove": ["type": "array", "items": ["type": "string"], "description": "要清掉的记忆 id"],
            "done": prop("boolean", "过完一遍了"),
            "author": author, "dry_run": dryRun,
        ], readOnly: false),
        tool("regulars", "每月固定进出：工资、房租、话费这类每个月差不多同一天、差不多同样多的钱，从最近 12 个月的流水现算。用户问「我工资多少」「每月固定要花多少」用它。", [
            "include_private": prop("boolean", "算上私房钱账户"),
        ], readOnly: true),
    ]

    /// 处理上面这些工具；不是它们就返回 nil。
    static func callMemory(_ name: String, _ a: [String: Any], who: String) throws -> String? {
        guard ["memory", "remember", "update_memory", "forget_memory", "tidy_memory", "regulars"].contains(name) else { return nil }
        func s(_ k: String) -> String? { (a[k] as? String).flatMap { $0.isEmpty ? nil : $0 } }
        func flag(_ k: String) -> Bool { (a[k] as? Bool) ?? false }
        func strings(_ k: String) -> [String]? { a[k] as? [String] }
        func day(_ text: String) throws -> LocalDate {
            guard let d = LocalDate(text) else { throw ToolError(message: "日期要写成 2026-11-21：\(text)") }
            return d
        }
        func kind() throws -> Memory.Kind? {
            guard let k = s("kind") else { return nil }
            guard let v = Memory.Kind(rawValue: k.lowercased()) else { throw ToolError(message: "kind 只能是 rule / topic / lesson") }
            return v
        }
        func source() throws -> Memory.Source? {
            guard let k = s("source") else { return nil }
            guard let v = Memory.Source(rawValue: k.lowercased()) else { throw ToolError(message: "source 只能是 said / corrected / confirmed / observed") }
            return v
        }
        var ledger = try loadLedger()
        func find(_ key: String) throws -> Memory {
            guard let m = ledger.findMemory(key) else { throw ToolError(message: "没有这条记忆：\(key)。先用 memory 看目录，id 写前 8 位。") }
            return m
        }
        func commit(_ change: ChangeRecord) throws -> String {
            if flag("dry_run") { return "预演（没有写入）：\(change.summary)" }
            try saveLedger(ledger)
            return "已记：\(change.summary)\n改动 id：\(change.id.uuidString.prefix(8).lowercased())"
        }
        /// 读出来用了：记一下时间，整理时好知道哪些一直没用上。存不上也不影响读。
        func used(_ list: [Memory]) {
            if ledger.touchMemories(list.map(\.id)) { try? saveLedger(ledger) }
        }

        switch name {
        case "memory":
            if let key = s("id") {
                let m = try find(key)
                used([m])
                return m.described()
            }
            if let link = s("link") {
                let list = ledger.memories(linkedTo: link)
                used(list)
                return list.isEmpty ? "没有挂在 \(link) 上的记忆。" : list.map { $0.described() }.joined(separator: "\n\n")
            }
            if let q = s("query") {
                let hits = ledger.searchMemories(q, kind: try kind(), limit: 5).map(\.memory)
                used(hits)
                if hits.isEmpty {
                    let titles = ledger.memories().map { "\($0.shortID)「\($0.title)」" }.joined(separator: "、")
                    return "没搜到和「\(q)」有关的记忆。" + (titles.isEmpty ? "现在还什么都没记。" : "现在有：\(titles)")
                }
                return hits.map { $0.described() }.joined(separator: "\n\n")
            }
            if let k = try kind() {
                let list = ledger.memories(kind: k)
                return list.isEmpty ? "「\(k.label)」里还没有东西。" : list.map { $0.described() }.joined(separator: "\n\n")
            }
            return try json(MemoryBrief(ledger: ledger))
        case "remember":
            guard let text = s("text") else { throw ToolError(message: "缺少参数 text") }
            var into: UUID?
            if let t = s("topic") { into = try find(t).id }
            guard into != nil || s("title") != nil else { throw ToolError(message: "缺少参数 title：这件事叫什么（话题）。加到已有话题就填 topic。") }
            let change = try ledger.remember(kind: try kind() ?? .topic, title: s("title") ?? "", text: text, source: try source() ?? .said,
                                             quote: s("quote"), story: s("story"), reviewOn: try s("review_on").map { try day($0) },
                                             links: strings("links") ?? [], into: into, allowNew: flag("new_topic"), author: who)
            return try commit(change)
        case "update_memory":
            guard let key = s("id") else { throw ToolError(message: "缺少参数 id") }
            let m = try find(key)
            var last: ChangeRecord?
            var said: [String] = []
            // 没填 = 不动；填了空字符串 = 清掉。
            var quote: String??
            if let q = a["quote"] as? String { quote = .some(q.isEmpty ? nil : q) }
            var story: String??
            if let st = a["story"] as? String { story = .some(st.isEmpty ? nil : st) }
            var review: LocalDate??
            if let r = a["review_on"] as? String {
                if r.isEmpty { review = .some(nil) } else { review = .some(try day(r)) }
            }
            if s("text") != nil || s("source") != nil || quote != nil || story != nil || review != nil {
                guard let note = ledger.findNote(s("line"), in: m) else {
                    throw ToolError(message: "「\(m.title)」有 \(m.notes.count) 行，line 要填改哪一行（memory 读出来每行开头那几位）。")
                }
                let c = try ledger.updateMemoryNote(m.id, noteID: note.id, text: s("text"), source: try source(), quote: quote, story: story,
                                                    reviewOn: review, author: who)
                last = c; said.append(c.summary)
            }
            if s("title") != nil || s("kind") != nil || a["links"] != nil || a["pinned"] != nil {
                let c = try ledger.editMemory(m.id, title: s("title"), kind: try kind(), links: strings("links"),
                                              pinned: a["pinned"] as? Bool, author: who)
                last = c; said.append(c.summary)
            }
            if flag("keep") {
                let c = try ledger.keepMemory(m.id, author: who)
                last = c; said.append(c.summary)
            }
            guard let last else { throw ToolError(message: "没有要改的：填 text / title / kind / links / pinned / keep 里的至少一个。") }
            if said.count == 1 { return try commit(last) }
            if flag("dry_run") { return "预演（没有写入）：\n" + said.joined(separator: "\n") }
            try saveLedger(ledger)
            return "已记：\n" + said.joined(separator: "\n")
        case "forget_memory":
            guard let key = s("id") else { throw ToolError(message: "缺少参数 id") }
            let m = try find(key)
            var noteID: UUID?
            if let line = s("line") {
                guard let n = ledger.findNote(line, in: m) else { throw ToolError(message: "「\(m.title)」里没有这一行：\(line)") }
                noteID = n.id
            }
            if flag("forever") {
                let change = try ledger.forgetMemory(m.id, noteID: noteID, author: who)
                if flag("dry_run") { return "预演（没有写入）：会彻底忘掉「\(m.title)」\(noteID == nil ? "" : "里的一行")，找不回来。" }
                try saveLedger(ledger)
                return "已经彻底忘掉，改动记录里也没有留内容。（\(change.summary)）"
            }
            let change = try ledger.removeMemory(m.id, noteID: noteID, author: who)
            return try commit(change)
        case "tidy_memory":
            let list = ledger.memoryTidyList()
            if let ids = strings("remove"), !ids.isEmpty {
                var items: [MemoryTidyItem] = []
                for key in ids {
                    let m = try find(key)
                    let mine = list.filter { $0.memoryID == m.id && $0.removable }
                    // 不在单子上的也可以清：用户点名要清就整条清。
                    items += mine.isEmpty ? [MemoryTidyItem(memoryID: m.id, noteID: nil, title: m.title, text: m.notes.first?.text ?? "",
                                                             reason: .stale, why: "用户说清掉")] : mine
                }
                let change = try ledger.tidyMemories(remove: items, author: who)
                return try commit(change)
            }
            if flag("done") {
                let change = try ledger.tidyMemories(remove: [], author: who)
                return try commit(change)
            }
            if list.isEmpty { return "没有要清的：没有到期的、半年没用上的，也没有挂的东西没了的。" }
            return "可能该清掉的（念给用户听，问哪些清、哪些留；清用 remove，留用 update_memory keep=true，过完填 done=true）：\n"
                + list.map { "\($0.memoryID.uuidString.prefix(8).lowercased())「\($0.title)」\($0.text)（\($0.why)）" }.joined(separator: "\n")
        case "regulars":
            let lines = Regulars.lines(ledger, hidden: flag("include_private") ? [] : nil)
            return lines.isEmpty ? "还看不出每月固定的进出：流水不够 3 个月，或者没有每个月差不多同一天、同样多的钱。" : lines.joined(separator: "\n")
        default:
            return nil
        }
    }
}

/// `fin memory`：夏夏的记忆。
struct MemoryCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "memory", abstract: "夏夏的记忆：规矩、记得的事、做事经验。看、搜、记、改、忘、每月整理。",
        subcommands: [List.self, Show.self, Search.self, Add.self, Edit.self, Forget.self, Tidy.self], defaultSubcommand: List.self)

    static func kind(_ text: String?) throws -> Memory.Kind? {
        guard let text else { return nil }
        guard let k = Memory.Kind(rawValue: text.lowercased()) else { throw ValidationError("kind 只能是 rule / topic / lesson") }
        return k
    }

    static func source(_ text: String?) throws -> Memory.Source? {
        guard let text else { return nil }
        guard let k = Memory.Source(rawValue: text.lowercased()) else { throw ValidationError("source 只能是 said / corrected / confirmed / observed / written") }
        return k
    }

    static func day(_ text: String) throws -> LocalDate {
        guard let d = LocalDate(text) else { throw ValidationError("日期要写成 2026-11-21：\(text)") }
        return d
    }

    static func find(_ key: String, in ledger: Ledger) throws -> Memory {
        guard let m = ledger.findMemory(key) else { throw ValidationError("没有这条记忆：\(key)。用 fin memory 看目录。") }
        return m
    }

    struct List: ParsableCommand {
        static let configuration = CommandConfiguration(commandName: "list", abstract: "列出记忆（默认全部）。")
        @Option(help: "只看一类：rule（规矩）、topic（记得的事）、lesson（做事经验）。") var kind: String?
        @Flag(help: "输出 JSON（规矩全文 + 目录 + 怎么用，和 MCP 的 memory 一样）。") var json = false

        func run() throws {
            let ledger = try loadLedger()
            if json { try Output.json(MemoryBrief(ledger: ledger)); return }
            let list = ledger.memories(kind: try MemoryCommand.kind(kind))
            if list.isEmpty { print("夏夏还没记住什么。用 fin memory add <话题> <记住什么> 记一条。"); return }
            for k in Memory.Kind.allCases {
                let part = list.filter { $0.kind == k }
                if part.isEmpty { continue }
                print("== \(k.label) ==")
                for m in part { print(m.described()) }
            }
        }
    }

    struct Show: ParsableCommand {
        static let configuration = CommandConfiguration(commandName: "show", abstract: "看一条的全文。")
        @Argument(help: "记忆 id（前 8 位）或话题名。") var id: String
        func run() throws { print(try MemoryCommand.find(id, in: try loadLedger()).described()) }
    }

    struct Search: ParsableCommand {
        static let configuration = CommandConfiguration(commandName: "search", abstract: "按关键词搜。")
        @Argument(help: "关键词。") var query: String
        func run() throws {
            let hits = try loadLedger().searchMemories(query)
            if hits.isEmpty { print("没搜到。"); return }
            print(hits.map { $0.memory.described() }.joined(separator: "\n\n"))
        }
    }

    struct Add: ParsableCommand {
        static let configuration = CommandConfiguration(commandName: "add", abstract: "记一条。同名话题会加在它下面；有相近话题会先提示。")
        @OptionGroup var w: WriteOptions
        @Argument(help: "话题：这件事叫什么，如「工资」。") var title: String
        @Argument(help: "记住什么，一句话。") var text: String
        @Option(help: "rule（规矩）、topic（记得的事，默认）、lesson（做事经验）。") var kind: String?
        @Option(help: "said（默认）、corrected、confirmed、observed、written。") var source: String?
        @Option(help: "用户的原话。") var quote: String?
        @Option(help: "当时出了什么事。") var story: String?
        @Option(help: "哪天回头看，如 2027-03-31。") var reviewOn: String?
        @Option(parsing: .upToNextOption, help: "挂在什么上：category:工资 account:caixa ……") var link: [String] = []
        @Flag(help: "有相近话题，但确实是另一件事。") var newTopic = false

        func run() throws {
            var ledger = try loadLedger()
            let change = try ledger.remember(kind: try MemoryCommand.kind(kind) ?? .topic, title: title, text: text,
                                             source: try MemoryCommand.source(source) ?? .said, quote: quote, story: story,
                                             reviewOn: try reviewOn.map { try MemoryCommand.day($0) }, links: link, allowNew: newTopic, author: w.who)
            try finish(ledger, change, w)
        }
    }

    struct Edit: ParsableCommand {
        static let configuration = CommandConfiguration(commandName: "edit", abstract: "改一条：改某一行的说法、改话题名、挪到另一类、标成重要。")
        @OptionGroup var w: WriteOptions
        @Argument(help: "记忆 id（前 8 位）或话题名。") var id: String
        @Option(help: "改哪一行（fin memory show 里每行开头那几位）；只有一行时不用填。") var line: String?
        @Option(help: "这一行的新说法。") var text: String?
        @Option(help: "新话题名。") var title: String?
        @Option(help: "挪到 rule / topic / lesson。") var kind: String?
        @Option(help: "哪天回头看；写 none 清掉。") var reviewOn: String?
        @Flag(inversion: .prefixedNo, help: "标成重要（每月整理时不列出来）。") var pin: Bool?
        @Flag(help: "整理时说留着：半年内不再问。") var keep = false

        func run() throws {
            var ledger = try loadLedger()
            let m = try MemoryCommand.find(id, in: ledger)
            var last: ChangeRecord?
            if text != nil || reviewOn != nil {
                guard let note = ledger.findNote(line, in: m) else { throw ValidationError("「\(m.title)」有 \(m.notes.count) 行，用 --line 指明改哪一行。") }
                var review: LocalDate??
                if let r = reviewOn {
                    if r == "none" { review = .some(nil) } else { review = .some(try MemoryCommand.day(r)) }
                }
                last = try ledger.updateMemoryNote(m.id, noteID: note.id, text: text, reviewOn: review, author: w.who)
            }
            if title != nil || kind != nil || pin != nil {
                last = try ledger.editMemory(m.id, title: title, kind: try MemoryCommand.kind(kind), pinned: pin, author: w.who)
            }
            if keep { last = try ledger.keepMemory(m.id, author: w.who) }
            guard let last else { throw ValidationError("没有要改的：填 --text / --title / --kind / --pin / --keep 里的至少一个。") }
            try finish(ledger, last, w)
        }
    }

    struct Forget: ParsableCommand {
        static let configuration = CommandConfiguration(commandName: "forget", abstract: "删掉一条（能撤销）；--forever 彻底忘掉，连改动记录里的痕迹一起抹掉。")
        @OptionGroup var w: WriteOptions
        @Argument(help: "记忆 id（前 8 位）或话题名。") var id: String
        @Option(help: "只删这一行。") var line: String?
        @Flag(help: "彻底忘掉，不能撤销。") var forever = false

        func run() throws {
            var ledger = try loadLedger()
            let m = try MemoryCommand.find(id, in: ledger)
            var noteID: UUID?
            if let line {
                guard let n = ledger.findNote(line, in: m) else { throw ValidationError("「\(m.title)」里没有这一行：\(line)") }
                noteID = n.id
            }
            let change: ChangeRecord
            if forever { change = try ledger.forgetMemory(m.id, noteID: noteID, author: w.who) }
            else { change = try ledger.removeMemory(m.id, noteID: noteID, author: w.who) }
            try finish(ledger, change, w)
        }
    }

    struct Tidy: ParsableCommand {
        static let configuration = CommandConfiguration(commandName: "tidy", abstract: "每月整理：列出可能该清掉的；--remove 清掉；--done 记下整理过了。")
        @OptionGroup var w: WriteOptions
        @Option(parsing: .upToNextOption, help: "清掉这几条（id）。") var remove: [String] = []
        @Flag(help: "过完一遍了。") var done = false

        func run() throws {
            var ledger = try loadLedger()
            let list = ledger.memoryTidyList()
            if !remove.isEmpty {
                var items: [MemoryTidyItem] = []
                for key in remove {
                    let m = try MemoryCommand.find(key, in: ledger)
                    let mine = list.filter { $0.memoryID == m.id && $0.removable }
                    items += mine.isEmpty ? [MemoryTidyItem(memoryID: m.id, noteID: nil, title: m.title, text: m.notes.first?.text ?? "",
                                                             reason: .stale, why: "点名清掉")] : mine
                }
                let change = try ledger.tidyMemories(remove: items, author: w.who)
                try finish(ledger, change, w)
                return
            }
            if done {
                let change = try ledger.tidyMemories(remove: [], author: w.who)
                try finish(ledger, change, w)
                return
            }
            if w.json { try Output.json(list); return }
            if list.isEmpty { print("没有要清的。"); return }
            for i in list { print("\(i.memoryID.uuidString.prefix(8).lowercased())「\(i.title)」\(i.text)（\(i.why)）") }
        }
    }
}

/// `fin regulars`：每月固定进出（工资、房租……），从流水现算。
struct RegularsCommand: ParsableCommand {
    static let configuration = CommandConfiguration(commandName: "regulars", abstract: "每月固定进出：工资、房租、话费这类，从最近 12 个月的流水现算。")
    @Flag(help: "算上私房钱账户。") var includePrivate = false
    @Flag(help: "输出 JSON。") var json = false

    func run() throws {
        let ledger = try loadLedger()
        let list = Regulars.detect(ledger, hidden: includePrivate ? [] : ledger.privateAccountIDs)
        if json { try Output.json(list); return }
        if list.isEmpty { print("还看不出每月固定的进出（流水不够 3 个月，或者没有每月固定的）。"); return }
        for r in list { print(r.line(currency: ledger.baseCurrency)) }
    }
}
