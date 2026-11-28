import XCTest
@testable import FinanceCore

/// 第 8 步：导入流水、记忆、账本改名接到正式账本。只用示例账本（内存里现造的）。
final class LedgerBridgeMoreTests: XCTestCase {
    private let today = LocalDate(year: 2026, month: 11, day: 18)
    private var ledger: Ledger { DemoData.make(endingOn: today) }
    private let csv = """
    Fecha;Concepto;Importe
    03/11/2026;Super Sol;-23,40
    04/11/2026;Farmacia Luna;-8,90
    05/11/2026;Nomina Taller Cielo;1.850,00
    TOTAL;;1.817,70
    """

    func testImportDryRunCountsAndWritesNothing() throws {
        var l = ledger
        let before = l
        let name = l.accounts.first { $0.kind != .credit }!.name
        let r = try LedgerBridge.importStatement(text: csv, fileName: "晴空银行 11 月.csv", accountName: name, to: &l, author: "小晴", dryRun: true)
        XCTAssertEqual(r.check.total, 3)
        XCTAssertEqual(r.check.fresh + r.check.duplicates, 3)
        XCTAssertEqual(r.check.unread, 1, "合计行读不懂，算没读的")
        XCTAssertNil(r.change)
        XCTAssertEqual(l, before, "预演：账本一个字都没变")
    }

    func testImportWritesOnceSkipsDuplicatesAndUndoes() throws {
        var l = ledger
        let account = l.accounts.first { $0.kind != .credit }!
        let count = l.transactions.count
        let r = try LedgerBridge.importStatement(text: csv, fileName: "晴空银行 11 月.csv", accountName: account.name, to: &l, author: "小晴")
        XCTAssertEqual(l.transactions.count, count + r.check.fresh)
        XCTAssertEqual(r.change?.author, "小晴")
        XCTAssertEqual(r.change?.kind, .importBatch)
        let added = l.transactions.filter { r.change!.transactionIDs.contains($0.id) }
        XCTAssertTrue(added.allSatisfy { $0.accountID == account.id && $0.bookID != nil }, "记在选的账户上，并且有账本")
        // 同一份再导一次：全是重复，账本不动
        let again = l
        XCTAssertThrowsError(try LedgerBridge.importStatement(text: csv, fileName: "晴空银行 11 月.csv", accountName: account.name, to: &l, author: "小晴"))
        XCTAssertEqual(l, again)
        // 整批撤销
        try l.undo(changeID: r.change!.id, author: "小晴")
        XCTAssertEqual(l.transactions.count, count)
    }

    func testImportRefusesWhatItCannotRead() {
        var l = ledger
        let before = l
        let name = l.accounts.first!.name
        XCTAssertThrowsError(try LedgerBridge.importStatement(text: "今天天气不错\n没有表格", fileName: "a.csv", accountName: name, to: &l, author: "小晴"))
        XCTAssertThrowsError(try LedgerBridge.importStatement(text: csv, fileName: "a.csv", accountName: "没有这个账户", to: &l, author: "小晴"))
        XCTAssertThrowsError(try LedgerBridge.importStatement(text: csv, fileName: "a.csv", accountName: name, to: &l, author: " "))
        XCTAssertEqual(l, before)
    }

    func testGuessReadsDebitCreditColumnsAndHeaderBelowNotes() throws {
        let text = """
        晴空银行 账户明细
        导出时间,2026-11-18
        交易日期,摘要,支出,收入
        2026-11-03,绿篮超市,23.40,
        2026-11-05,工资,,1850.00
        """
        let r = try StatementGuess.read(text, accountID: "a", source: "x")
        XCTAssertEqual(r.transactions.map(\.amount), [Money(cents: -23_40), Money(cents: 1850_00)])
        XCTAssertEqual(r.transactions.first?.description, "绿篮超市")
    }

    func testMemoriesComeAcrossAndWriteBack() throws {
        var l = ledger
        _ = try l.remember(kind: .rule, title: "停车位", text: "停车位算固定开销", allowNew: true, author: "小晴")
        let before = LedgerBridge.snapshot(of: l, today: today)
        XCTAssertEqual(before.memos.first { $0.topic == "停车位" }?.lines, ["停车位算固定开销"])
        // 记一条新的
        var after = before
        _ = try after.remember(.topic, topic: "奶茶", line: "一周最多两杯")
        try LedgerBridge.apply(before: before, after: after, to: &l, today: today, author: "小晴")
        XCTAssertEqual(l.memories.first { $0.title == "奶茶" }?.notes.map(\.text), ["一周最多两杯"])
        XCTAssertEqual(l.changes.last?.author, "小晴")
        // 在已有的话题下面加一行、标重要
        let b2 = LedgerBridge.snapshot(of: l, today: today)
        var a2 = b2
        _ = try a2.remember(.rule, topic: "停车位", line: "每月 1 号扣")
        try LedgerBridge.apply(before: b2, after: a2, to: &l, today: today, author: "小晴")
        XCTAssertEqual(l.memories.first { $0.title == "停车位" }?.notes.count, 2)
        let b3 = LedgerBridge.snapshot(of: l, today: today)
        var a3 = b3
        let rent = b3.memos.first { $0.topic == "停车位" }!
        try a3.setMemo(rent.id, important: true)
        try LedgerBridge.apply(before: b3, after: a3, to: &l, today: today, author: "小晴")
        XCTAssertEqual(l.memories.first { $0.title == "停车位" }?.pinned, true)
        // 删掉，能撤销
        let b4 = LedgerBridge.snapshot(of: l, today: today)
        var a4 = b4
        try a4.removeMemo(rent.id)
        let records = try LedgerBridge.apply(before: b4, after: a4, to: &l, today: today, author: "小晴")
        XCTAssertNil(l.memories.first { $0.title == "停车位" })
        try l.undo(changeID: records[0].id, author: "小晴")
        XCTAssertEqual(l.memories.first { $0.title == "停车位" }?.notes.count, 2)
    }

    /// 店里一天的收入在生意流水和「真正赚了」里只算一次（以前「营业额」「营业收入」各出一行，算了两次）。
    func testShopIncomeCountsOnceInFlowAndEarned() throws {
        var l = ledger
        // 先把今天店里已经记的收入拿掉，保证今天是「还没记」
        let shop = WealthBreakdown.businessAccounts(l)
        l.transactions.removeAll { $0.date == today && $0.amount > .zero && shop.contains($0.accountID) }
        let before = LedgerBridge.snapshot(of: l, today: today)
        XCTAssertEqual(before.shopFlowIn, before.shopDays.map(\.total).reduce(.zero, +), "流水里收的 = 每天收的加起来，不多算")
        XCTAssertEqual(before.shopMonth().income, before.shopFlowIn)
        // 记今天收了 300：流水里多一行 300，「真正赚了」里的收入也只多 300
        guard let day = before.shopDays.first(where: { $0.day == today.day }), day.state == .missing, let held = before.shopHeld.first else { return XCTFail("今天应该还没记") }
        var after = before
        let was = Money.zero
        try after.recordShopDay(day.day, channels: [.init(held.name, Money(cents: 300_00))])
        try LedgerBridge.apply(before: before, after: after, to: &l, today: today, author: "小晴")
        let now = LedgerBridge.snapshot(of: l, today: today)
        XCTAssertEqual(now.shopFlowIn, before.shopFlowIn + Money(cents: 300_00) - was)
        XCTAssertEqual(now.shopMonth().income, before.shopMonth().income + Money(cents: 300_00) - was)
        XCTAssertEqual(now.shopFlow.filter { $0.day == day.day && $0.amount > .zero }.count, 1, "那天只出一行")
    }

    /// 内置分类没有一个落到问号或者「没有图标」的那张小票。
    func testEveryBuiltInCategoryHasItsOwnIcon() {
        let builtIn = CategoryIcons.all.map(\.label) + SideGuess.businessExpenses + SideGuess.businessIncome
            + Set(ledger.transactions.compactMap(\.category))
        for c in Set(builtIn) where c != "未分类" && c != "其他" && c != "报销" {
            let e = LedgerBridge.emoji(c)
            XCTAssertNotEqual(e, "❓", c)
            XCTAssertNotEqual(e, LedgerBridge.fallbackEmoji, "「\(c)」还没有图标")
        }
        XCTAssertEqual(LedgerBridge.emoji("手续费"), "💸"); XCTAssertEqual(LedgerBridge.emoji("社保"), "🪪"); XCTAssertEqual(LedgerBridge.emoji("花材"), "💐")
        XCTAssertEqual(LedgerBridge.emoji(nil), "❓")
        XCTAssertEqual(LedgerBridge.emoji("我自己起的名字"), LedgerBridge.fallbackEmoji)
    }

    /// 目标走完收起来：目标留在账本里、标上哪天走完；钱转回账户；在走的目标（含最多几个的上限）不再算它；能撤销。
    func testFinishingGoalsKeepsThemButStopsCountingThem() throws {
        var l = ledger
        try l.removeGoal(l.goals.last!.id, author: "测试")
        try l.giveEveryGoalItsOwnAccount(today: today, author: "迁移")
        // 把每个目标的金额改成「再存 10 就够」，好试走完
        for s in Plans.goals(l) {
            var g = l.goals.first { $0.id == s.id }!
            g.target = s.saved + Money(cents: 10_00)
            _ = try? l.updateGoal(g, author: "测试")
        }
        let before = LedgerBridge.snapshot(of: l, today: today)
        let total = before.inHand
        let active = l.activeGoalIDs().count
        let pay = before.accounts(for: .moveOut, side: .life).first { $0.kind == .own && $0.block == .daily && $0.balance > Money(cents: 100_00) }!.name
        // 小目标：最后一笔存进去正好存够，自己收进「走完的路」
        let small = try XCTUnwrap(before.smallGoals.first)
        var after = before
        try after.depositSmall(small.id, amount: Money(cents: 10_00), from: pay)
        XCTAssertEqual(after.finishedGoals.first?.name, small.name)
        let records = try LedgerBridge.apply(before: before, after: after, to: &l, today: today, author: "小晴")
        let done = try XCTUnwrap(l.goals.first { $0.id == small.id }, "目标还留在账本里")
        XCTAssertEqual(done.finishedOn, today)
        XCTAssertEqual(l.activeGoalIDs().count, active - 1, "不再算在走的目标")
        XCTAssertFalse(Plans.goals(l).contains { $0.id == small.id })
        XCTAssertTrue(Plans.goals(l, includeFinished: true).contains { $0.id == small.id })
        XCTAssertTrue(records.allSatisfy { $0.author == "小晴" })
        let now = LedgerBridge.snapshot(of: l, today: today)
        XCTAssertEqual(now.finishedGoals.map(\.name), [small.name])
        XCTAssertFalse(now.smallGoals.contains { $0.name == small.name })
        XCTAssertEqual(now.inHand, total, "钱只是挪了地方，总数不变")
        XCTAssertEqual(now.account(pay)?.balance, after.account(pay)?.balance, "界面上算的和正式账本一致")
        XCTAssertEqual(l.accountBalances()[done.savingsAccountID!]?.base, now.account(before.accounts.first { $0.id == small.account }!.name)?.balance, "那个账户里的钱和界面上一致")
        // 走完的不占位置：还能再定一个新目标
        XCTAssertNoThrow(try l.addGoal(name: "新的心愿", bookID: done.bookID, target: Money(cents: 500_00), today: today, author: "小晴"))
        // 整步撤回：目标回到在走
        for r in (records + [l.changes.last!]).reversed() { try l.undo(changeID: r.id, author: "小晴") }
        XCTAssertNil(l.goals.first { $0.id == small.id }?.finishedOn)
        XCTAssertEqual(l.activeGoalIDs().count, active)
        // 大目标：存够以后点「收起来」
        let b2 = LedgerBridge.snapshot(of: l, today: today)
        var a2 = b2
        _ = try a2.deposit(Money(cents: 10_00), from: pay)
        try LedgerBridge.apply(before: b2, after: a2, to: &l, today: today, author: "小晴")
        let b3 = LedgerBridge.snapshot(of: l, today: today)
        XCTAssertTrue(b3.journey.isFinished)
        var a3 = b3
        try a3.archiveBigGoal()
        try LedgerBridge.apply(before: b3, after: a3, to: &l, today: today, author: "小晴")
        let big = try XCTUnwrap(l.goals.first { $0.name == b3.journey.name })
        XCTAssertEqual(big.finishedOn, today)
        let b4 = LedgerBridge.snapshot(of: l, today: today)
        XCTAssertEqual(b4.finishedGoals.first?.name, big.name)
        XCTAssertNotEqual(b4.journey.name, big.name, "大目标的位置让出来了")
        XCTAssertEqual(b4.inHand, total)
        XCTAssertTrue(b4.goalAccountsAreConsistent)
    }

    /// 老账本的目标没有「哪天走完的」：读出来都是在走的；新字段存一遍读回来还在。
    func testFinishedOnIsOptionalAndSurvivesSaving() throws {
        var g = Goal(name: "旅行", bookID: "personal", target: Money(cents: 100_00))
        let old = try JSONEncoder().encode(g)
        XCTAssertFalse(String(data: old, encoding: .utf8)!.contains("finishedOn"), "没走完的不多写一个字段")
        XCTAssertNil(try JSONDecoder().decode(Goal.self, from: old).finishedOn)
        g.finishedOn = today
        XCTAssertEqual(try JSONDecoder().decode(Goal.self, from: JSONEncoder().encode(g)).finishedOn, today)
    }

    /// 那天已经有从流水导进来的收入：再按渠道记不抛错。界面上填的是「那天这个渠道一共收了多少」，
    /// 多出来的补记一笔；那天只出一行，营业额 = 导进来的 + 补记的，不漏不重。
    func testRecordingADayThatAlreadyHasImportedIncome() throws {
        var l = ledger
        let shopBook = l.businessBook!.id
        let shop = WealthBreakdown.businessAccounts(l)
        l.transactions.removeAll { $0.date == today && $0.amount > .zero && shop.contains($0.accountID) }
        let accountID = l.transactions.first { $0.bookID == shopBook && $0.amount > .zero }!.accountID
        try l.addTransaction(Transaction(date: today, amount: Money(cents: 45_00), description: "转账收款", accountID: accountID, bookID: shopBook,
                                         category: "营业收入", source: "晴空银行.csv"), author: "流水导入")
        let before = LedgerBridge.snapshot(of: l, today: today)
        let name = l.accounts.first { $0.id == accountID }!.name
        let day = before.shopDays.first { $0.day == today.day }!
        XCTAssertEqual(day.state, .open); XCTAssertEqual(day.total, Money(cents: 45_00), "导进来的那笔已经算在这天里")
        let n = l.transactions.count
        // 这天这个渠道一共收了 165：补记 120，导进来的 45 不动
        var after = before
        try after.recordShopDay(today.day, channels: [.init(name, Money(cents: 165_00))])
        let records = try LedgerBridge.apply(before: before, after: after, to: &l, today: today, author: "小晴")
        XCTAssertEqual(records.count, 1)
        XCTAssertEqual(l.transactions.count, n + 1)
        XCTAssertEqual(l.transactions.last?.amount, Money(cents: 120_00)); XCTAssertEqual(l.transactions.last?.source, Ledger.dailySource)
        let now = LedgerBridge.snapshot(of: l, today: today)
        XCTAssertEqual(now.shopDays.first { $0.day == today.day }?.total, Money(cents: 165_00))
        XCTAssertEqual(now.shopFlow.filter { $0.day == today.day && $0.amount > .zero }.map(\.amount), [Money(cents: 165_00)], "那天只出一行")
        XCTAssertEqual(now.shopFlowIn, before.shopFlowIn + Money(cents: 120_00))
        XCTAssertEqual(now.shopMonth().income, before.shopMonth().income + Money(cents: 120_00))
        // 改少一点（还在「每天记账」记的那部分里）：可以
        var a2 = now
        try a2.recordShopDay(today.day, channels: [.init(name, Money(cents: 100_00))])
        try LedgerBridge.apply(before: now, after: a2, to: &l, today: today, author: "小晴")
        XCTAssertEqual(l.transactions.count, n + 1, "补记的那笔是改成 55，不是又多一笔")
        let b3 = LedgerBridge.snapshot(of: l, today: today)
        XCTAssertEqual(b3.shopDays.first { $0.day == today.day }?.total, Money(cents: 100_00))
        XCTAssertTrue(l.transactions.contains { $0.source == "晴空银行.csv" && $0.amount == Money(cents: 45_00) }, "导进来的那笔一直没动")
        // 改到比导进来的还少、或者标成休息：分不清该改哪笔，拒绝并说清楚，账本不动
        let keep = l
        var a3 = b3
        try a3.recordShopDay(today.day, channels: [.init(name, Money(cents: 20_00))])
        XCTAssertThrowsError(try LedgerBridge.apply(before: b3, after: a3, to: &l, today: today, author: "小晴")) {
            XCTAssertTrue(($0 as? TrialError)?.message.contains("从流水导进来的") ?? false)
        }
        var a4 = b3
        try a4.markShopRest(today.day)
        XCTAssertThrowsError(try LedgerBridge.apply(before: b3, after: a4, to: &l, today: today, author: "小晴"))
        XCTAssertEqual(l, keep)
    }

    /// 店里的固定开销 = 自己加的规则 + 从流水里认出来的，同一样只出现一次；停掉的、说过「不算」的不算；
    /// 不亏线用的就是这一份合计。
    func testShopFixedCostsListEachOnceAndFeedTheBreakEvenLine() throws {
        var l = ledger
        let b = LedgerBridge.snapshot(of: l, today: today)
        XCTAssertEqual(Set(b.fixedCosts.map(\.name)).count, b.fixedCosts.count, "同一样不出现两次")
        let rules = LedgerBridge.shopFixedRules(l), guesses = Outlook.fixedGuesses(l, side: .business, today: today)
        XCTAssertFalse(rules.isEmpty, "示例账本里店有自己加的固定开销（店租、工资）")
        // 合计 = 规则（没停的）+ 认出来的（规则没管到的），一分不差
        let expect = rules.filter { !$0.paused }.map { $0.template.amount.magnitude }.reduce(.zero, +)
            + guesses.filter { g in !rules.contains { $0.template.description == g.name } }.map(\.amount).reduce(.zero, +)
        XCTAssertEqual(b.fixedTotal, expect)
        // 认出来的和规则不是同一笔钱：每个认出来的「账户|分类」都不在规则里
        for g in guesses { XCTAssertFalse(rules.contains { "\($0.template.accountID)|\($0.template.category ?? "")" == g.key }, g.name) }
        // 不亏线 = (固定开销合计 + 贷款月供 + 这个月进货) ÷ 打算开门的天数，往上取整到 1 €
        let need = b.fixedTotal + b.shopLoanMonthly + b.shopMonth().purchases
        XCTAssertEqual(b.dailyBreakEven.cents, (need.cents / Int64(b.plannedOpenDays) + 99) / 100 * 100)
        // 停掉一样：合计少这么多
        var paused = rules[0]; paused.paused = true
        try l.updateRecurring(paused, author: "测试")
        let b2 = LedgerBridge.snapshot(of: l, today: today)
        XCTAssertEqual(b2.fixedTotal, b.fixedTotal - rules[0].template.amount.magnitude)
        XCTAssertEqual(b2.fixedCosts.first { $0.name == rules[0].template.description }?.off, true)
        XCTAssertLessThan(b2.dailyBreakEven, b.dailyBreakEven)
        // 说过「不算」的：不在列表里，合计也少这么多
        if let g = guesses.first {
            l.markNotFixed(g.key, name: g.name, author: "测试")
            let b3 = LedgerBridge.snapshot(of: l, today: today)
            XCTAssertNil(b3.fixedCosts.first { $0.name == g.name })
            XCTAssertEqual(b3.fixedTotal, b2.fixedTotal - g.amount)
        }
    }

    /// 新用户从零开始：引导里填的账户、欠款、想要的那句话写进空账本；每样有作者、能撤销；什么都没填就什么都不写。
    func testFirstSetupWritesWhatTheOnboardingCollected() throws {
        var l = Ledger.fresh
        XCTAssertTrue(LedgerBridge.isBrandNew(l))
        XCTAssertFalse(LedgerBridge.isBrandNew(ledger), "有数据的账本不走引导")
        var list = StartingAccounts(rows: [])
        func add(_ k: StartingAccounts.Kind, _ name: String? = nil, _ text: String) throws {
            let id = try list.add(k)
            if let name { try list.rename(id, to: name) }
            try list.setText(id, text)
        }
        try add(.daily, nil, "1.500"); try add(.cash, nil, "85"); try add(.credit, nil, "640")
        try add(.lent, "小王", "200"); try add(.borrowed, "阿青", "300"); try add(.savings, nil, "")
        let records = try LedgerBridge.firstSetup(&l, accounts: list, wish: "三年后不用为钱发愁", today: today, author: "小晴")
        XCTAssertFalse(LedgerBridge.isBrandNew(l))
        XCTAssertTrue(records.allSatisfy { $0.author == "小晴" })
        let b = LedgerBridge.snapshot(of: l, today: today)
        XCTAssertEqual(b.account("日常卡")?.balance, Money(cents: 1500_00))
        XCTAssertEqual(b.account("现金")?.balance, Money(cents: 85_00))
        XCTAssertEqual(b.account("储蓄")?.balance, .zero, "没填多少的账户照样建，余额是 0")
        XCTAssertEqual(l.accounts.first { $0.name == "信用卡" }?.kind, .credit)
        XCTAssertEqual(b.account("信用卡")?.balance, Money(cents: 640_00), "信用卡填的是欠多少")
        XCTAssertEqual(l.debts.count, 2)
        XCTAssertEqual(b.totals.net, Money(cents: (1500 + 85 + 200 - 640 - 300) * 100), "净剩 = 有的 − 欠的")
        XCTAssertEqual(b.month.spentTotal, .zero, "开账的钱不算花销"); XCTAssertEqual(b.month.income, .zero, "也不算收入")
        XCTAssertEqual(b.memos.first { $0.topic == "我想要的" }?.lines, ["三年后不用为钱发愁"])
        // 全部撤回：又是一本空账本
        for r in records.reversed() { try l.undo(changeID: r.id, author: "小晴") }
        XCTAssertTrue(l.accounts.isEmpty); XCTAssertTrue(l.debts.isEmpty); XCTAssertTrue(l.memories.isEmpty)
        // 什么都没填：什么都不写
        var empty = Ledger.fresh
        XCTAssertTrue(try LedgerBridge.firstSetup(&empty, accounts: StartingAccounts(rows: []), wish: " ", today: today, author: "小晴").isEmpty)
        XCTAssertEqual(empty, Ledger.fresh)
        // 两个账户重名：拒绝，账本不动
        var twice = StartingAccounts(rows: [.init(kind: .daily, name: "卡", text: "1", owes: false), .init(kind: .custom, name: "卡", text: "2", owes: false)])
        _ = twice
        XCTAssertThrowsError(try LedgerBridge.firstSetup(&empty, accounts: twice, wish: "", today: today, author: "小晴"))
        XCTAssertEqual(empty, Ledger.fresh)
        twice = StartingAccounts(rows: [])
    }

    func testRenamingABookGoesToTheLedger() throws {
        var l = ledger
        let before = LedgerBridge.snapshot(of: l, today: today)
        var after = before
        try after.renameBook(.life, to: "我的日子")
        let records = try LedgerBridge.apply(before: before, after: after, to: &l, today: today, author: "小晴")
        XCTAssertEqual(l.books.first { !$0.isBusiness }?.name, "我的日子")
        XCTAssertEqual(LedgerBridge.snapshot(of: l, today: today).lifeName, "我的日子")
        try l.undo(changeID: records[0].id, author: "小晴")
        XCTAssertEqual(l.books.first { !$0.isBusiness }?.name, before.lifeName)
    }
}
