import ArgumentParser
import FinanceCore
import Foundation

// 存钱目标（小金猪，2026-11-23）：MCP 工具和 fin 命令共用这里的文字。规则都在 FinanceCore/PiggyBank.swift，
// 这里只把数字说成人话，所以 AI 说的「提前了 3 天」和 app 小猪旁边写的是同一个数。

enum GoalText {
    static func day(_ d: LocalDate) -> String { "\(d.year) 年 \(d.month) 月 \(d.day) 日" }

    /// 给 AI 看的一整页目标（MCP goals、fin goals --json）。
    struct Report: Encodable {
        struct Line: Encodable {
            var name: String
            /// 大目标 / 小目标 / 超出（老账本多出来的）/ 已完成
            var role: String
            var target: String
            var saved: String
            var left: String
            var percent: Int
            var deadline: String?
            /// 照现在的存法哪天到手
            var arrival: String?
            var per_day: String?
            /// 「每 2 天少一次「Café Nube」」
            var per_day_plain: String?
            /// 钱真的放在哪
            var stash: String?
            var idle_days: Int
            /// true = 很久没存了，用提问框问用户「还重要吗：继续 / 先放一放 / 删掉」
            var ask_still_important: Bool
            var locked: Bool
            var held_back_this_month: Int
        }
        var rules: String
        /// 最近三个月平均每月剩多少（收入 − 支出）
        var monthly_room: String?
        /// 最常买的小东西（「忍住了」按钮和换算用）
        var habit: String
        var weekly_challenge: String?
        var slots_left: Int
        var main: Line?
        var small: [Line]
        var over_limit: [Line]
        var done: [Line]
        /// 要用提问框问用户的事，一次问一个
        var ask: [String]
    }

    static func line(_ p: PiggyGoal, role: String, habit: SmallHabit) -> Report.Line {
        let f = p.forecast
        let stash = p.stash.map { s in p.stashNote.map { "\(s.label)（\($0)）" } ?? s.label }
        return Report.Line(name: f.name, role: role, target: f.target.formatted, saved: f.saved.formatted, left: f.left.formatted,
                           percent: f.percent, deadline: f.deadline?.description, arrival: p.arrival.map(day),
                           per_day: p.perDay?.formatted, per_day_plain: p.perDay.map { habit.phrase(perDay: $0) },
                           stash: stash, idle_days: p.idleDays, ask_still_important: p.needsCheck, locked: f.locked,
                           held_back_this_month: p.heldBackCount)
    }

    static func report(_ ledger: Ledger, today: LocalDate = .today) -> Report {
        let b = Plans.goalBoard(ledger, today: today)
        var ask: [String] = []
        if let p = b.needsCheck {
            ask.append("「\(p.name)」已经 \(p.idleDays) 天没存了：问用户它还重要吗，选项「还重要，继续」「先放一放」「删掉」（goal_check）。")
        }
        if !b.extra.isEmpty {
            ask.append("现在有 \(b.active.count) 个目标，超出了 1 个大目标 + 3 个小目标：问用户先完成或删掉哪几个（不要自己删）。")
        }
        for p in b.active where p.stash == nil {
            ask.append("「\(p.name)」还没记钱存在哪：问用户是储蓄罐、一张银行卡，还是一个固定的地方。")
            break
        }
        let h = b.habit
        return Report(rules: Plans.goalLimitSentence + "每次真的存了钱都要记一笔（goal_deposit）；钱可以取出来（goal_withdraw），不责怪。",
                      monthly_room: b.monthlyRoom?.formatted,
                      habit: h.isGuess ? "流水里还看不出常买的小东西，按一杯咖啡 3 € 算" : "最常买「\(h.name)」，一般 \(h.typical.formatted) 一次，最近 60 天 \(h.count60) 次",
                      weekly_challenge: h.challengeLimit.map { "上周「\(h.name)」\(h.lastWeek) 次，这周少一次：不超过 \($0) 次（这周已经 \(h.thisWeek) 次）" },
                      slots_left: b.slotsLeft,
                      main: b.main.map { line($0, role: "大目标", habit: h) },
                      small: b.small.map { line($0, role: "小目标", habit: h) },
                      over_limit: b.extra.map { line($0, role: "超出", habit: h) },
                      done: b.done.map { line($0, role: "已完成", habit: h) },
                      ask: ask)
    }

    /// 存了一笔以后回的话：「提前了 3 天到手，现在 2027 年 3 月 12 日能到。」
    static func afterDeposit(_ before: Int?, _ ledger: Ledger, goalID: UUID, today: LocalDate = .today) -> String {
        let board = Plans.goalBoard(ledger, today: today)
        guard let p = (board.active + board.done).first(where: { $0.id == goalID }) else { return "" }
        if p.forecast.isDone { return "「\(p.name)」存够了！到手啦 🎉" }
        var s = before.map { "「\(p.name)」提前了 \($0) 天到手。" } ?? "「\(p.name)」又近了一步。"
        if let a = p.arrival { s += "照现在的存法 \(day(a)) 能到。" }
        s += "还差 \(p.forecast.left.formatted)（\(p.forecast.percent)%）。"
        return s
    }

    static func afterWithdraw(_ later: Int?, _ ledger: Ledger, goalID: UUID, today: LocalDate = .today) -> String {
        let board = Plans.goalBoard(ledger, today: today)
        guard let p = (board.active + board.done).first(where: { $0.id == goalID }) else { return "" }
        var s = later.map { "「\(p.name)」到手的日子往后推了大约 \($0) 天。" } ?? ""
        s += "还差 \(p.forecast.left.formatted)。用钱很正常，之后慢慢补回来就好。"
        return s
    }

    static func advice(_ a: GoalAdvice, target: Money) -> String {
        var s = "存 \(target.formatted)：每天 \(a.perDay.formatted)（\(a.phrase)），每月 \(a.perMonth.formatted)。"
        if let room = a.monthlyRoom { s += "最近每月大约剩 \(room.formatted)。" }
        if a.tooTight {
            s += "每月要存的比平时剩的多，会很吃力。"
            if let later = a.easierDeadline { s += "晚一点更轻松：改到 \(later.year) 年 \(later.month) 月，每月只要存一半左右。" }
        }
        return s
    }
}

// MARK: - MCP

extension MCPTools {
    static let goalTools: [[String: Any]] = [
        tool("goals", "存钱目标（小金猪）：1 个大目标 + 最多 3 个小目标，每个的进度、哪天到手、每天存多少（换成人话）、钱存在哪、多久没存；还有每月大约剩多少、最常买的小东西、要问用户的事（ask）。ask 里的事用提问框一次问一个。", [:], readOnly: true),
        tool("plan_goal", "建目标前算一算（不写入）：存这么多、哪天前要，每天/每月存多少、换成「每 2 天少一杯咖啡」这种人话、超不超出每月剩的钱、晚一点更轻松的日子。先调这个，把结果告诉用户再问要不要建。", [
            "target": prop("string", "要存多少"), "deadline": prop("string", "哪天前要，如 2027-06-30；不定日子不填（按一年算）"),
        ], required: ["target"], readOnly: true),
        tool("add_goal", "建一个存钱目标。同时最多 1 个大目标 + 3 个小目标（满了会报错，让用户先完成或删掉一个）。建之前用提问框一次一个问清：想要什么 → 多少钱 → 哪天要 → 钱存在哪 → 大目标还是小目标。", [
            "name": prop("string", "想要什么，如「换新电脑」"), "target": prop("string", "目标金额"), "book": prop("string", "账本 id，默认 personal"),
            "deadline": prop("string", "哪天前要"), "main": prop("boolean", "设成大目标（原来的大目标变小目标）。还没有目标时默认是大目标"),
            "stash": ["type": "string", "enum": ["jar", "card", "spot"], "description": "钱真的存在哪：jar 储蓄罐 / card 一张银行卡 / spot 一个固定的地方"],
            "stash_note": prop("string", "具体在哪，如「书桌上的小猪储蓄罐」"),
            "icon": prop("string", "小猪上的图标（SF Symbol 名，可不填）"),
            "savings_account": prop("string", "专门的储蓄账户 id（进度 = 这个账户余额）；没有就不填，在现有账户里划出"),
            "locked": prop("boolean", "锁定：到期前不能取"), "author": author, "dry_run": dryRun,
        ], required: ["name", "target"], readOnly: false),
        tool("goal_deposit", "往目标里存钱（不算支出）。用户说存了钱、投了币、忍住没买某样东西把钱存起来时用。返回「提前了几天到手」，原样告诉用户。", [
            "name": prop("string", "目标名称"), "amount": prop("string", "金额"), "from_account": prop("string", "钱从哪个账户来"),
            "held_back": prop("string", "忍住没买的东西（如「咖啡」）：算一次「忍住了」"),
            "date": prop("string", "日期，默认今天"), "author": author, "dry_run": dryRun,
        ], required: ["name", "amount", "from_account"], readOnly: false),
        tool("goal_withdraw", "从目标里取钱（锁定的目标到期前不能取）。取钱很正常，别责怪用户。", [
            "name": prop("string", "目标名称"), "amount": prop("string", "金额"), "to_account": prop("string", "取到哪个账户"),
            "date": prop("string", "日期，默认今天"), "author": author, "dry_run": dryRun,
        ], required: ["name", "amount", "to_account"], readOnly: false),
        tool("set_main_goal", "把一个目标设成大目标（只有一个，原来的变小目标）。", [
            "name": prop("string", "目标名称"), "author": author, "dry_run": dryRun,
        ], required: ["name"], readOnly: false),
        tool("goal_check", "很久没存的目标，用户在提问框里选了以后调：keep = 还重要，继续（30 天内不再问）；pause = 先放一放（90 天内不再问）。用户选「删掉」用 remove_goal。", [
            "name": prop("string", "目标名称"), "choice": ["type": "string", "enum": ["keep", "pause"], "description": "keep 或 pause"],
            "author": author, "dry_run": dryRun,
        ], required: ["name", "choice"], readOnly: false),
        tool("set_goal_stash", "记下目标的钱真的存在哪。", [
            "name": prop("string", "目标名称"),
            "stash": ["type": "string", "enum": ["jar", "card", "spot"], "description": "jar 储蓄罐 / card 一张银行卡 / spot 一个固定的地方"],
            "stash_note": prop("string", "具体在哪"), "author": author, "dry_run": dryRun,
        ], required: ["name", "stash"], readOnly: false),
        tool("remove_goal", "删掉一个目标（在现有账户里划出的存取记录一起删，账户余额不变；能撤销）。先问用户确认。", [
            "name": prop("string", "目标名称"), "author": author, "dry_run": dryRun,
        ], required: ["name"], readOnly: false),
    ]

    /// 处理上面这些工具；不是它们就返回 nil。
    static func callGoals(_ name: String, _ a: [String: Any], who: String) throws -> String? {
        let names: Set<String> = ["goals", "plan_goal", "add_goal", "goal_deposit", "goal_withdraw", "set_main_goal", "goal_check",
                                  "set_goal_stash", "remove_goal"]
        guard names.contains(name) else { return nil }
        func s(_ k: String) -> String? { (a[k] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? (a[k] as? NSNumber).map { "\($0)" } }
        func req(_ k: String) throws -> String { guard let v = s(k) else { throw ToolError(message: "缺少参数 \(k)") }; return v }
        func flag(_ k: String) -> Bool? { a[k] as? Bool }
        func money(_ k: String) throws -> Money {
            guard let m = Money(parsing: try req(k)) else { throw ToolError(message: "金额看不懂：\(a[k] ?? "")") }
            return m.magnitude
        }
        func date(_ k: String) throws -> LocalDate? {
            guard let v = s(k) else { return nil }
            guard let d = LocalDate(v) else { throw ToolError(message: "日期要写成 2026-11-21：\(v)") }
            return d
        }
        func stash(_ k: String) throws -> GoalStash? {
            guard let v = s(k) else { return nil }
            guard let x = GoalStash(loose: v) else { throw ToolError(message: "stash 只能是 jar（储蓄罐）、card（银行卡）或 spot（固定的地方）") }
            return x
        }
        var ledger = try loadLedger()
        func goal() throws -> Goal {
            let hits = ledger.findGoals(named: try req("name"))
            guard hits.count == 1 else { throw ToolError(message: hits.isEmpty ? "没有这个目标" : "对上了 \(hits.count) 个目标，写完整一点") }
            return hits[0]
        }
        func commit(_ change: ChangeRecord, _ extra: String = "") throws -> String {
            if flag("dry_run") == true { return "预演（没有写入）：\(change.summary)" + (extra.isEmpty ? "" : "\n\(extra)") }
            try saveLedger(ledger)
            return "已记：\(change.summary)" + (extra.isEmpty ? "" : "\n\(extra)")
                + "\n改动 id：\(change.id.uuidString.prefix(8).lowercased())（写错了用 undo 撤销）"
        }

        switch name {
        case "goals":
            return try MCPTools.json(GoalText.report(ledger))
        case "plan_goal":
            let target = try money("target")
            return GoalText.advice(Plans.goalAdvice(ledger, target: target, deadline: try date("deadline")), target: target)
        case "add_goal":
            let target = try money("target")
            let deadline = try date("deadline")
            let advice = Plans.goalAdvice(ledger, target: target, deadline: deadline)
            // 还没有在存的目标时，第一个就是大目标。
            let main = flag("main") ?? ledger.activeGoalIDs().isEmpty
            let book = s("book") ?? ledger.books.first?.id ?? "personal"
            let goalName = try req("name")
            let where_ = try stash("stash")
            let (_, change) = try ledger.addGoal(name: goalName, bookID: book,
                                                 target: target, deadline: deadline, savingsAccountID: s("savings_account"),
                                                 locked: flag("locked") ?? false, main: main, icon: s("icon"),
                                                 stash: where_, stashNote: s("stash_note"), author: who)
            var extra = (main ? "这是大目标。" : "这是小目标。") + GoalText.advice(advice, target: target)
            if s("stash") == nil { extra += "\n还没记钱存在哪：用提问框问用户（储蓄罐 / 一张银行卡 / 一个固定的地方），再调 set_goal_stash。" }
            extra += "\n提醒用户：每次真的存了钱，都跟你说一声或在 app 里点小猪记一笔。小小的一步也能实现大大的目标。"
            return try commit(change, extra)
        case "goal_deposit":
            let g = try goal()
            let amount = try money("amount")
            let early = Plans.daysEarlier(ledger, goalID: g.id, amount: amount)
            let change = try ledger.deposit(goalID: g.id, amount: amount, fromAccount: try req("from_account"),
                                            date: try date("date") ?? .today, heldBack: s("held_back"), author: who)
            return try commit(change, GoalText.afterDeposit(early, ledger, goalID: g.id))
        case "goal_withdraw":
            let g = try goal()
            let amount = try money("amount")
            let later = Plans.daysEarlier(ledger, goalID: g.id, amount: amount)
            let change = try ledger.withdraw(goalID: g.id, amount: amount, toAccount: try req("to_account"),
                                             date: try date("date") ?? .today, author: who)
            return try commit(change, GoalText.afterWithdraw(later, ledger, goalID: g.id))
        case "set_main_goal":
            let id = try goal().id
            return try commit(try ledger.setMainGoal(id, author: who))
        case "goal_check":
            let choice = try req("choice").lowercased()
            guard choice == "keep" || choice == "pause" else { throw ToolError(message: "choice 只能是 keep 或 pause；要删用 remove_goal") }
            let id = try goal().id
            return try commit(try ledger.keepGoal(id, pause: choice == "pause", author: who))
        case "set_goal_stash":
            let id = try goal().id
            let where_ = try stash("stash")
            return try commit(try ledger.setGoalStash(id, stash: where_, note: s("stash_note"), author: who))
        case "remove_goal":
            let id = try goal().id
            return try commit(try ledger.removeGoal(id, author: who))
        default:
            return nil
        }
    }
}

// MARK: - fin 命令

extension GoalCommand {
    struct Plan: ParsableCommand {
        static let configuration = CommandConfiguration(commandName: "plan", abstract: "建目标前算一算：每天、每月存多少，超不超出每月剩的钱（不写入）。")
        @Argument(help: "要存多少。") var target: String
        @Option(help: "哪天前要。") var deadline: String?

        func run() throws {
            let ledger = try loadLedger()
            let t = try parseMoney(target).magnitude
            print(GoalText.advice(Plans.goalAdvice(ledger, target: t, deadline: try deadline.map { try parseDate($0) }), target: t))
        }
    }

    struct Main: ParsableCommand {
        static let configuration = CommandConfiguration(commandName: "main", abstract: "设成大目标（只有一个）。")
        @OptionGroup var w: WriteOptions
        @Argument(help: "目标名称。") var name: String

        func run() throws {
            var ledger = try loadLedger()
            let id = try GoalCommand.find(ledger, name).id
            let change = try ledger.setMainGoal(id, author: w.who)
            try finish(ledger, change, w)
        }
    }

    struct Check: ParsableCommand {
        static let configuration = CommandConfiguration(commandName: "check", abstract: "很久没存的目标：keep 还重要继续 / pause 先放一放。要删用 fin goal rm。")
        @OptionGroup var w: WriteOptions
        @Argument(help: "目标名称。") var name: String
        @Argument(help: "keep 或 pause。") var choice: String

        func run() throws {
            guard choice == "keep" || choice == "pause" else { throw ValidationError("只能是 keep 或 pause") }
            var ledger = try loadLedger()
            let id = try GoalCommand.find(ledger, name).id
            let change = try ledger.keepGoal(id, pause: choice == "pause", author: w.who)
            try finish(ledger, change, w)
        }
    }

    struct Remove: ParsableCommand {
        static let configuration = CommandConfiguration(commandName: "rm", abstract: "删掉一个目标（能撤销）。")
        @OptionGroup var w: WriteOptions
        @Argument(help: "目标名称。") var name: String

        func run() throws {
            var ledger = try loadLedger()
            let id = try GoalCommand.find(ledger, name).id
            let change = try ledger.removeGoal(id, author: w.who)
            try finish(ledger, change, w)
        }
    }
}
