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

    /// 回本、体检页的数从正式账本来：本钱 = 账本里填的；赚回来的 = 正式账本自己算的那个数；店里每月要还的不是 0。
    func testPaybackNumbersComeFromTheLedger() throws {
        let l = ledger
        let cap = try XCTUnwrap(l.business?.capital, "示例账本里填了开店本钱")
        let progress = try XCTUnwrap(l.capitalProgress(today: today))
        let b = LedgerBridge.snapshot(of: l, today: today)
        XCTAssertEqual(b.capitalTotal, cap.total)
        XCTAssertGreaterThan(progress.recovered, .zero, "示例里的店已经赚回来一些")
        if b.shopMonth().earned <= progress.recovered { XCTAssertEqual(b.shopBack, progress.recovered, "赚回来的和正式账本算的一样") }
        XCTAssertEqual(b.paybackLeft, max(cap.total - b.shopBack, .zero))
        XCTAssertEqual(b.shopLoanMonthly, LedgerBridge.shopMonthlyRepayments(l, today: today))
        // 示例账本里店有分期（咖啡机）：每月要还的不是 0，而且就是没还完的分期每期的数 + 欠款这个月该还的
        let biz = Set(l.books.filter(\.isBusiness).map(\.id))
        let inst = Plans.installments(l).filter { s in l.installments.contains { $0.id == s.id && biz.contains($0.bookID) } && s.remaining > .zero }
        if !inst.isEmpty { XCTAssertGreaterThanOrEqual(b.shopLoanMonthly, inst.map { min($0.perPayment, $0.remaining) }.reduce(.zero, +)) }
        // 没有生意的账本：都是 0，不报错
        XCTAssertEqual(LedgerBridge.shopMonthlyRepayments(.fresh, today: today), .zero)
    }

    /// 回本的日子只有一个算法：首页和回本页用的是同一句；不亏线的说明里写的就是实际算进去的几样。
    func testPaybackDateAndBreakEvenNoteMatchTheNumbers() throws {
        for b in [TrialBook.demo, LedgerBridge.snapshot(of: ledger, today: today)] {
            let months = b.paybackMonths()
            let label = b.paybackDateLabel()
            if b.paybackLeft == .zero { XCTAssertEqual(label, "已经回本"); continue }
            XCTAssertEqual(label == nil, months == nil, "算得出几个月，就写得出哪个月")
            if let months, let label {
                let cal = Calendar(identifier: .gregorian)
                let c = cal.dateComponents([.year, .month], from: cal.date(byAdding: .month, value: months, to: b.todayDate)!)
                XCTAssertEqual(label, "\(c.year!) 年 \(c.month!) 月")
            }
            // 不亏线：说明里的几样加起来 ÷ 开门天数 = 那条线（往上取整到 1 €）
            let need = b.fixedTotal + b.shopLoanMonthly + b.shopMonth().purchases
            XCTAssertEqual(b.dailyBreakEven.cents, (need.cents / Int64(b.plannedOpenDays) + 99) / 100 * 100)
            for (word, amount) in [("每月固定要付的", b.fixedTotal), ("每月要还的", b.shopLoanMonthly), ("这个月进的货", b.shopMonth().purchases)] {
                XCTAssertEqual(b.breakEvenNote.contains("\(word) \(amount.formatted)"), amount > .zero, word)
            }
            XCTAssertTrue(b.breakEvenNote.contains("\(b.plannedOpenDays) 天"))
        }
    }

    /// 新加的订阅：多久扣一次照选的记；下次扣款是从今天起过一个周期；「赚钱用的」记在生意账本上。
    func testNewSubscriptionsKeepTheirCycleAndBook() throws {
        var l = ledger
        for (i, name) in ["周报", "月卡", "季票", "年费"].enumerated() {
            let before = LedgerBridge.snapshot(of: l, today: today)
            var after = before
            try after.addSubscription(name: name, amount: Money(cents: 12_00), note: "", forWork: i == 3, cycle: i)
            try LedgerBridge.apply(before: before, after: after, to: &l, today: today, author: "小晴")
        }
        func sub(_ n: String) -> Subscription { l.subscriptions.first { $0.name == n }! }
        XCTAssertEqual(sub("周报").cycle, .weekly); XCTAssertEqual(sub("周报").nextDate, today.adding(days: 7))
        XCTAssertEqual(sub("月卡").cycle, .monthly); XCTAssertEqual(sub("月卡").nextDate, today.adding(months: 1))
        XCTAssertEqual(sub("季票").cycle, .quarterly); XCTAssertEqual(sub("季票").nextDate, today.adding(months: 3))
        XCTAssertEqual(sub("年费").cycle, .yearly); XCTAssertEqual(sub("年费").nextDate, today.adding(months: 12))
        XCTAssertEqual(sub("年费").bookID, l.businessBook?.id, "赚钱用的记在生意账本")
        XCTAssertEqual(sub("月卡").bookID, l.books.first { !$0.isBusiness }?.id)
        // 新界面里显示的周期和每月折合也对
        let b = LedgerBridge.snapshot(of: l, today: today)
        XCTAssertEqual(b.subscriptions.first { $0.name == "年费" }?.cycle, 3)
        XCTAssertEqual(b.subscriptions.first { $0.name == "年费" }?.monthly, Money(cents: 1_00))
    }

    /// 「再几个月回本」按前三个整月平均赚的算（和旧界面一个口径），月初也不会算出一个特别远的日子；
    /// 回本那条线是过去每个月底真实赚回来的累计，最后一个点是今天。
    func testPaybackSpeedUsesLastThreeFullMonthsAndTheCurveIsReal() throws {
        let l = ledger
        let b = LedgerBridge.snapshot(of: l, today: today)
        // 速度 = 正式账本里前三个整月多赚回来的 ÷ 3
        func recovered(_ monthsAgo: Int) -> Money {
            let ym = today.yearMonth.adding(months: -monthsAgo)
            let end = LocalDate(year: ym.year, month: ym.month, day: 1).adding(months: 1).adding(days: -1)
            return l.capitalProgress(today: end)!.recovered
        }
        XCTAssertTrue(b.paybackSpeed.fromLastThree)
        XCTAssertEqual(b.paybackSpeed.perMonth, Money(cents: (recovered(1) - recovered(4)).cents / 3))
        XCTAssertEqual(b.paybackSpeedNote, "照前三个月平均赚的速度")
        // 月初和月中算出来的回本月份差不了多少（以前月初会差出好几年）
        let early = LedgerBridge.snapshot(of: DemoData.make(endingOn: LocalDate(year: 2026, month: 11, day: 2)), today: LocalDate(year: 2026, month: 11, day: 2))
        if let a = early.paybackMonths(), let c = b.paybackMonths() { XCTAssertLessThanOrEqual(abs(a - c), 3) }
        // 那条线：每个点就是正式账本那个月底的数，一个月比一个月多（示例里的店一直在赚），最后一个是今天
        let curve = b.paybackCurve
        XCTAssertGreaterThan(curve.count, 3)
        XCTAssertEqual(curve.last?.back, b.shopBack); XCTAssertEqual(curve.last?.key, b.thisMonth)
        XCTAssertEqual(curve[curve.count - 2].back, recovered(1))
        XCTAssertEqual(curve.map(\.key), curve.map(\.key).sorted())
        // 试用数字只有两个月的数：退回用这个月赚的
        XCTAssertFalse(TrialBook.demo.paybackSpeed.fromLastThree)
        XCTAssertEqual(TrialBook.demo.paybackSpeed.perMonth, TrialBook.demo.shopMonth().earned)
        XCTAssertEqual(TrialBook.demo.paybackCurve.count, 3)
    }

    /// 过去月份的生意流水：正式账本上是一笔笔的，加起来就是那个月收的、花的；试用数字里只有合计的月份说清楚。
    func testPastMonthShopFlowIsItemisedOnTheRealLedger() throws {
        let b = LedgerBridge.snapshot(of: ledger, today: today)
        let oct = TrialBook.MonthKey(2026, 10)
        let rows = b.shopFlow(in: oct)
        XCTAssertGreaterThan(rows.count, 10, "十月店里有很多笔")
        XCTAssertFalse(b.shopFlowIsTotalsOnly(in: oct)); XCTAssertNil(b.shopFlowTotalsLine(in: oct))
        let d = b.monthData(oct)
        XCTAssertEqual(rows.filter { $0.amount > .zero }.map(\.amount).reduce(.zero, +), d.shopIn, "逐笔加起来 = 那个月收的")
        XCTAssertEqual(rows.filter { $0.amount < .zero }.map(\.amount).reduce(.zero, +).magnitude, d.shopOut, "逐笔加起来 = 那个月花的")
        XCTAssertEqual(Set(rows.map(\.id)).count, rows.count, "没有重复的行")
        XCTAssertTrue(rows.allSatisfy { (1...31).contains($0.day) })
        // 这个月不受影响：还是按每天收的算一次
        XCTAssertEqual(b.shopFlow(in: b.thisMonth).count, b.shopFlow.count)
        XCTAssertFalse(b.shopFlowIsTotalsOnly(in: b.thisMonth))
        // 试用数字：十月只有合计
        let demo = TrialBook.demo
        XCTAssertTrue(demo.shopFlowIsTotalsOnly(in: oct))
        XCTAssertEqual(demo.shopFlowTotalsLine(in: oct), "10 月只有合计：收了 4.210,00 €，花了 2.874,00 €。一笔笔的没有存")
        // 试用数字里往十月补记一笔：就不再是「只有合计」了
        var patched = demo
        try patched.recordShopIncome(daysAgo: patched.todayDay + 3, channels: [.init(patched.shopHeld.first!.name, Money(cents: 80_00))])
        XCTAssertFalse(patched.shopFlowIsTotalsOnly(in: oct)); XCTAssertEqual(patched.shopFlow(in: oct).count, 1)
    }

    /// 每月打算存多少：存在大目标上（可选字段），新界面读它、能改、能撤销；这个月留给目标的钱按它算。
    func testMonthlyPlanLivesOnTheBigGoal() throws {
        var l = ledger
        let before = LedgerBridge.snapshot(of: l, today: today)
        XCTAssertEqual(before.journey.monthlyPlan, .zero, "老账本没定过")
        var after = before
        try after.setMonthlyPlan(Money(cents: 150_00))
        let records = try LedgerBridge.apply(before: before, after: after, to: &l, today: today, author: "小晴")
        let big = try XCTUnwrap(l.goals.first { $0.name == before.journey.name })
        XCTAssertEqual(big.monthlyPlan, Money(cents: 150_00)); XCTAssertEqual(records.first?.author, "小晴")
        let now = LedgerBridge.snapshot(of: l, today: today)
        XCTAssertEqual(now.journey.monthlyPlan, Money(cents: 150_00))
        XCTAssertGreaterThanOrEqual(now.month.forGoals, Money(cents: 150_00), "这个月先给目标留出这么多")
        try l.undo(changeID: records[0].id, author: "小晴")
        XCTAssertNil(l.goals.first { $0.id == big.id }?.monthlyPlan)
        // 老数据里没有这个字段照样读得出来；没定的时候不多写一个字段
        let old = try JSONEncoder().encode(Goal(name: "旅行", bookID: "personal", target: Money(cents: 100_00)))
        XCTAssertFalse(String(data: old, encoding: .utf8)!.contains("monthlyPlan"))
        XCTAssertNil(try JSONDecoder().decode(Goal.self, from: old).monthlyPlan)
    }

    /// 小结里「过了一站」：那个月里大目标存的钱跨过了哪一站，从存钱的流水现算。
    func testStationsPassedInAMonthAreComputed() throws {
        // 试用数字：十月从 239 存到 439，路上 300 那一站在中间（示例的站：0、100、300…）
        let demo = TrialBook.demo
        let oct = TrialBook.MonthKey(2026, 10)
        let start = demo.pastMonths[1].goalSavedEnd!, end = demo.pastMonths[0].goalSavedEnd!
        let crossed = demo.journey.stations.filter { $0.target > start && $0.target <= end }
        XCTAssertEqual(demo.monthGood(oct).contains { $0.title.hasPrefix("过了") }, !crossed.isEmpty)
        if let last = crossed.last { XCTAssertTrue(demo.monthGood(oct).first { $0.title.hasPrefix("过了") }!.detail.contains(last.target.formatted)) }
        // 正式账本：每个月底大目标存了多少 = 它那个账户到那个月底的余额，一个月不比上个月少（示例里只存不取）
        var l = ledger
        try l.removeGoal(l.goals.last!.id, author: "测试")
        try l.giveEveryGoalItsOwnAccount(today: today, author: "迁移")
        let b = LedgerBridge.snapshot(of: l, today: today)
        let ends = b.pastMonths.sorted { $0.key < $1.key }.compactMap(\.goalSavedEnd)
        XCTAssertFalse(ends.isEmpty)
        XCTAssertLessThanOrEqual(ends.last!, b.journey.saved)
        // 没有上个月的数：不写这一句，不编
        var alone = demo
        alone.pastMonths.removeAll { $0.key != oct }
        XCTAssertFalse(alone.monthGood(oct).contains { $0.title.hasPrefix("过了") })
    }

    /// 店的本钱、估货值、欠款接正式账本；生意账本里的欠款和分期不再混进生活那边。
    func testShopCapitalStockAndDebtsGoToTheLedger() throws {
        var l = ledger
        let shopBook = l.businessBook!.id
        let b0 = LedgerBridge.snapshot(of: l, today: today)
        // 生意账本里的分期（咖啡机）在店的欠款里，不在生活的账户里
        let inst = try XCTUnwrap(l.installments.first { $0.bookID == shopBook })
        XCTAssertTrue(b0.shopDebts.contains { $0.name == inst.name && $0.tag == LedgerBridge.installmentTag })
        XCTAssertNil(b0.account(inst.name), "不混进生活那边")
        XCTAssertLessThan(b0.shopDueNext, b0.shopOwesTotal, "下个月要还的只算这一期，不是整笔")
        // 本钱：后来又投了一样
        var a1 = b0
        try a1.addCapital(name: "新冷柜", amount: Money(cents: 900_00), note: "")
        let r1 = try LedgerBridge.apply(before: b0, after: a1, to: &l, today: today, author: "小晴")
        XCTAssertEqual(l.business?.capital?.total, b0.capitalTotal + Money(cents: 900_00))
        XCTAssertEqual(l.business?.capital?.items.last?.name, "新冷柜")
        XCTAssertEqual(l.business?.capital?.openedOn, ledger.business?.capital?.openedOn, "开店时间照旧")
        XCTAssertEqual(r1.first?.author, "小晴")
        // 估货值：记一个估的数，流水不动
        let b2 = LedgerBridge.snapshot(of: l, today: today)
        XCTAssertEqual(b2.capitalTotal, b0.capitalTotal + Money(cents: 900_00))
        var a2 = b2
        try a2.estimateStock(Money(cents: 1200_00), note: "盘了一遍")
        let tx = l.transactions.count
        try LedgerBridge.apply(before: b2, after: a2, to: &l, today: today, author: "小晴")
        XCTAssertEqual(l.business?.stockEstimates?.last?.value, Money(cents: 1200_00)); XCTAssertEqual(l.transactions.count, tx)
        let b3 = LedgerBridge.snapshot(of: l, today: today)
        XCTAssertEqual(b3.stockEstimates.first?.amount, Money(cents: 1200_00)); XCTAssertEqual(b3.stockEstimates.first?.name, "今天")
        // 赊账：欠花材店 300；还清它，钱从店里的账户出，不算开销
        var a3 = b3
        try a3.addShopDebt(name: "晴空花材行", amount: Money(cents: 300_00), note: "月底结", owedToShop: false)
        try LedgerBridge.apply(before: b3, after: a3, to: &l, today: today, author: "小晴")
        XCTAssertEqual(l.debts.last?.bookID, shopBook); XCTAssertEqual(l.debts.last?.direction, .iOweThem)
        let b4 = LedgerBridge.snapshot(of: l, today: today)
        XCTAssertTrue(b4.shopDebts.contains { $0.name == "晴空花材行" && $0.amount == Money(cents: 300_00) && !$0.flag })
        XCTAssertEqual(b4.shopOwesTotal, b3.shopOwesTotal + Money(cents: 300_00))
        XCTAssertNil(b4.account("晴空花材行"))
        var a4 = b4
        let payFrom = b4.shopHeld.first { $0.balance >= Money(cents: 300_00) }!.name
        try a4.payShopDebt("晴空花材行", from: payFrom)
        let costs = b4.shopMonth().costs
        try LedgerBridge.apply(before: b4, after: a4, to: &l, today: today, author: "小晴")
        let b5 = LedgerBridge.snapshot(of: l, today: today)
        XCTAssertFalse(b5.shopDebts.contains { $0.name == "晴空花材行" }, "还清了就不在欠款里了")
        XCTAssertEqual(b5.account(payFrom)?.balance, b4.account(payFrom)!.balance - Money(cents: 300_00))
        XCTAssertEqual(b5.shopMonth().costs, costs, "还欠款不算开销")
        // 别人欠店的
        var a5 = b5
        try a5.addShopDebt(name: "云朵咖啡馆", amount: Money(cents: 120_00), note: "", owedToShop: true)
        try LedgerBridge.apply(before: b5, after: a5, to: &l, today: today, author: "小晴")
        XCTAssertEqual(l.debts.last?.direction, .theyOweMe)
        // 分期不能在这里一次还清：拒绝，账本不动
        let b6 = LedgerBridge.snapshot(of: l, today: today)
        var a6 = b6
        if let i = a6.shopDebts.firstIndex(where: { $0.name == inst.name }) { a6.shopDebts[i].off = true }
        let keep = l
        XCTAssertThrowsError(try LedgerBridge.apply(before: b6, after: a6, to: &l, today: today, author: "小晴"))
        XCTAssertEqual(l, keep)
    }

    /// 「这个月一共花掉」= 各分类加起来（花销页圆环中间那个数），一分不差；还没到日子的固定开销不算花掉，但照样先留着。
    func testSpentTotalEqualsTheCategorySlices() throws {
        for day in [1, 3, 15, 18, 28, 30] {
            let t = LocalDate(year: 2026, month: 11, day: day)
            let b = LedgerBridge.snapshot(of: DemoData.make(endingOn: t), today: t)
            // 按月取数那一份（手机、总览切月份用的）也一样：一共花掉 = 固定 + 随手花的 = 圆环各段之和
            let d = b.monthData(b.thisMonth)
            XCTAssertEqual(d.spentTotal, d.fixed + d.spent, "\(day) 号")
            XCTAssertEqual(d.spentTotal, d.sliceTotal, "\(day) 号")
            XCTAssertEqual(d.spentTotal, b.month.spentTotal, "\(day) 号")
            XCTAssertEqual(d.left, b.month.left, "\(day) 号：最后剩下和「还能随便花」是同一个数")
            // 过去的月份也是
            for p in b.pastMonths { XCTAssertEqual(p.spentTotal, p.sliceTotal, "\(p.key.month) 月") }
            XCTAssertEqual(b.month.spentTotal, b.spendByCategory.map(\.amount).reduce(.zero, +), "\(day) 号")
            XCTAssertEqual(b.month.fixedPaid + b.month.fixedLeft, b.month.fixed)
            XCTAssertEqual(b.month.left, b.month.income - b.month.fixed - b.month.forGoals - b.month.spent, "还能随便花照样先留出没付的固定开销")
            XCTAssertEqual(b.spendPace.soFar.last, b.month.spentTotal, "趋势那条线的末端也是这个数")
        }
        // 报上来的那个情况：同一本账，把日子定在 28 号看
        let l28 = LedgerBridge.snapshot(of: ledger, today: LocalDate(year: 2026, month: 11, day: 28))
        XCTAssertEqual(l28.monthData(l28.thisMonth).spentTotal, l28.monthData(l28.thisMonth).sliceTotal)
        // 试用数字没有「还没付的固定开销」，数不变
        XCTAssertEqual(TrialBook.demo.month.spentTotal, TrialBook.demo.month.fixed + TrialBook.demo.month.spent)
    }

    /// 三样从账本算出来的日子和数：欠的哪个月还完、目标各站哪天到的、两次估货之间用掉多少。算不出来就不写。
    func testPayoffStationDatesAndStockUsageAreComputedOrLeftOut() throws {
        var l = ledger
        let b = LedgerBridge.snapshot(of: l, today: today)
        // 分期：最后一期 = 下一期 + 还剩的期数 − 1 个月
        for st in Plans.installments(l) where st.remaining > .zero {
            guard let next = st.nextDate else { continue }
            let end = next.adding(months: max(st.count - st.paidCount - 1, 0))
            XCTAssertEqual(b.payoffMonths[st.name], "\(end.year) 年 \(end.month) 月", st.name)
        }
        // 没约日子、没排计划的欠款：不写；只要有这样一笔，就不写「哪个月不欠了」
        let open = l.debts.filter { $0.direction == .iOweThem && !$0.closed && ($0.plan ?? []).isEmpty && $0.dueDate == nil }
        let bizBooks = Set(l.books.filter(\.isBusiness).map(\.id))
        for d in open { XCTAssertNil(b.payoffMonths[d.counterparty], d.counterparty) }
        if open.contains(where: { !bizBooks.contains($0.bookID) }) { XCTAssertNil(b.debtFreeMonth, "有一笔没日子，就不编") }
        // 给每一笔都约上日子：就写得出最晚的那个月
        for i in l.debts.indices where l.debts[i].direction == .iOweThem { l.debts[i].dueDate = LocalDate(year: 2027, month: 3, day: 31) }
        let b2 = LedgerBridge.snapshot(of: l, today: today)
        let latest = try XCTUnwrap(b2.debtFreeMonth)
        XCTAssertTrue(b2.payoffMonths.values.contains(latest))
        XCTAssertGreaterThanOrEqual(latest, "2027 年 3 月")

        // 目标各站哪天到的：迁移以后每个目标有自己的账户，从它的余额历史算
        var g = ledger
        try g.removeGoal(g.goals.last!.id, author: "测试")
        try g.giveEveryGoalItsOwnAccount(today: today, author: "迁移")
        let bg = LedgerBridge.snapshot(of: g, today: today)
        for (i, _) in bg.stationDates { XCTAssertLessThanOrEqual(bg.journey.stations[i].target, bg.journey.saved, "只写已经到了的站") }
        // 存够下一站：那一站的日子就是今天
        if let next = bg.journey.nextStation, !bg.journey.isFinished {
            var after = bg
            let pay = bg.accounts(for: .moveOut, side: .life).first { $0.kind == .own && $0.block == .daily && $0.balance > bg.journey.remainingToNext }!.name
            _ = try after.deposit(bg.journey.remainingToNext, from: pay)
            try LedgerBridge.apply(before: bg, after: after, to: &g, today: today, author: "小晴")
            let now = LedgerBridge.snapshot(of: g, today: today)
            let idx = now.journey.stations.firstIndex { $0.target == next.target }!
            XCTAssertEqual(now.stationDates[idx], "\(today.month) 月 \(today.day) 日")
        }

        // 估货：估过一次算不出来；估过两次 = 上次估的 + 这段进的货 − 这次估的
        var s1 = ledger
        try s1.addStockEstimate(Money(cents: 2400_00), date: LocalDate(year: 2026, month: 9, day: 30), author: "小晴")
        XCTAssertNil(LedgerBridge.snapshot(of: s1, today: today).stockUsage)
        try s1.addStockEstimate(Money(cents: 2600_00), date: today, author: "小晴")
        let u = try XCTUnwrap(LedgerBridge.snapshot(of: s1, today: today).stockUsage)
        let shop = s1.businessBook!.id
        let bought = s1.transactions.filter { $0.bookID == shop && $0.amount < .zero && $0.countsAsIncomeOrExpense && $0.date > LocalDate(year: 2026, month: 9, day: 30) && $0.date <= today
            && ["进货", "花材", "原料"].contains($0.category ?? "") }.reduce(Money.zero) { $0 + $1.amount.magnitude }
        XCTAssertEqual(u.bought, bought); XCTAssertGreaterThan(bought, .zero)
        XCTAssertEqual(u.used, Money(cents: 2400_00) + bought - Money(cents: 2600_00))
        // 试用数字里这三样都没有（它用的是自己的示例）
        XCTAssertNil(TrialBook.demo.stockUsage); XCTAssertNil(TrialBook.demo.debtFreeMonth)
        // 试用数字各站的日子在示例数据里，而且只给已经到了的站
        let demo = TrialBook.demo
        XCTAssertEqual(demo.stationDates, [0: "9 月 3 日", 2: "10 月 12 日"])
        for (i, _) in demo.stationDates { XCTAssertLessThanOrEqual(demo.journey.stations[i].target, demo.journey.saved) }
    }

    /// 加订阅时能选的账户：银行卡、储蓄、信用卡、现金都在（存钱罐不在）；选的账户和哪天扣都写进正式账本。
    func testSubscriptionChargeAccountAndDateAreKept() throws {
        let demo = TrialBook.demo
        XCTAssertEqual(demo.subscriptionAccounts(.life).map(\.name), ["日常卡", "储蓄", "信用卡", "现金"])
        var d = demo
        XCTAssertThrowsError(try d.addSubscription(name: "杂志", amount: Money(cents: 5_00), note: "", forWork: false, account: "换新电脑 存钱罐"), "存钱罐扣不了订阅")
        try d.addSubscription(name: "杂志", amount: Money(cents: 5_00), note: "", forWork: false, cycle: 1, account: "信用卡", dueIn: 9)
        XCTAssertEqual(d.subscriptions.last?.account, "信用卡"); XCTAssertEqual(d.subscriptions.last?.dueIn, 9)
        // 正式账本：记在选的那张卡上，下次扣款就是选的那天
        var l = ledger
        let before = LedgerBridge.snapshot(of: l, today: today)
        let card = try XCTUnwrap(before.subscriptionAccounts(.life).first { $0.isCreditCard })
        XCTAssertGreaterThanOrEqual(before.subscriptionAccounts(.life).count, 3)
        var after = before
        try after.addSubscription(name: "杂志", amount: Money(cents: 5_00), note: "", forWork: false, cycle: 1, account: card.name, dueIn: 9)
        try LedgerBridge.apply(before: before, after: after, to: &l, today: today, author: "小晴")
        let s = try XCTUnwrap(l.subscriptions.first { $0.name == "杂志" })
        XCTAssertEqual(s.accountID, l.accounts.first { $0.name == card.name }?.id)
        XCTAssertEqual(s.nextDate, today.adding(days: 9))
        XCTAssertEqual(LedgerBridge.snapshot(of: l, today: today).subscriptions.first { $0.name == "杂志" }?.account, card.name)
    }

    /// 「店里一共值」是负数时才有那句「欠的比有的多 X」，X 就是差的那个数；不是负数没有这句。
    func testShopWorthNoteOnlyWhenNegative() {
        let demo = TrialBook.demo
        XCTAssertLessThan(demo.shopWorth.net, .zero, "示例里的店欠的比有的多")
        XCTAssertEqual(demo.shopWorthNote, "欠的比有的多 \(demo.shopWorth.net.magnitude.formatted)")
        let real = LedgerBridge.snapshot(of: ledger, today: today)
        XCTAssertGreaterThan(real.shopWorth.net, .zero)
        XCTAssertNil(real.shopWorthNote)
        var none = demo
        none.wipe()
        XCTAssertNil(none.shopWorthNote, "正好是 0 也不显示")
    }

    /// 店里能加不同的账户：现金、银行卡、信用卡都算店那边的；店的贷款记成生意账本里的一笔欠款。
    func testAddingDifferentShopAccountsOnTheRealLedger() throws {
        var l = ledger
        func add(_ emoji: String, _ name: String, _ amount: Int64, owes: Bool) throws {
            let before = LedgerBridge.snapshot(of: l, today: today)
            var after = before
            try after.addShopAccount(emoji: emoji, name: name, balance: Money(cents: amount), owes: owes)
            try LedgerBridge.apply(before: before, after: after, to: &l, today: today, author: "小晴")
        }
        try add("💶", "店的零钱箱 现金", 80_00, owes: false)
        try add("🏪", "店的第二张银行卡", 500_00, owes: false)
        try add("💳", "店的信用卡", 120_00, owes: true)
        let shopAccounts = WealthBreakdown.businessAccounts(l)
        for name in ["店的零钱箱 现金", "店的第二张银行卡", "店的信用卡"] {
            let a = try XCTUnwrap(l.accounts.first { $0.name == name }, name)
            XCTAssertTrue(shopAccounts.contains(a.id), "\(name) 算店那边的")
        }
        XCTAssertEqual(l.accounts.first { $0.name == "店的零钱箱 现金" }?.kind, .cash)
        XCTAssertEqual(l.accounts.first { $0.name == "店的信用卡" }?.kind, .credit)
        let b = LedgerBridge.snapshot(of: l, today: today)
        XCTAssertEqual(b.account("店的第二张银行卡")?.side, .biz); XCTAssertEqual(b.account("店的第二张银行卡")?.balance, Money(cents: 500_00))
        XCTAssertEqual(b.account("店的信用卡")?.balance, Money(cents: 120_00), "信用卡填的是欠多少")
        XCTAssertNil(b.accounts(on: .life).first { $0.name.hasPrefix("店的") }, "不混进生活那边")
        // 店的贷款：生意账本里的一笔欠款，出现在店的欠款里
        let debts = l.debts.count
        try add("🏦", "店的设备贷款", 1000_00, owes: true)
        XCTAssertEqual(l.debts.count, debts + 1)
        XCTAssertEqual(l.debts.last?.bookID, l.businessBook?.id)
        let b2 = LedgerBridge.snapshot(of: l, today: today)
        XCTAssertTrue(b2.shopDebts.contains { $0.name == "店的设备贷款" && $0.amount == Money(cents: 1000_00) })
        XCTAssertEqual(b2.totals.owe, b.totals.owe, "生活这边欠的没变")
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

    // MARK: 管哪边

    func testManagedSidesLiveInTheLedgerAndUndo() throws {
        var l = ledger
        XCTAssertEqual(l.managedSides, .both, "示例账本开着生意、没选过：两边都管")
        XCTAssertThrowsError(try l.setManagedSides(.both, author: "小晴"), "没变就不记改动")
        let n = l.changes.count
        let c = try l.setManagedSides(.biz, author: "小晴")
        XCTAssertEqual(l.managedSides, .biz); XCTAssertEqual(c.author, "小晴"); XCTAssertEqual(l.changes.count, n + 1)
        // 存进账本文件：编码再解码（另一台设备读到的）还是它
        let copy = try JSONDecoder().decode(Ledger.self, from: JSONEncoder().encode(l))
        XCTAssertEqual(copy.managedSides, .biz)
        let b = LedgerBridge.snapshot(of: copy, today: today)
        XCTAssertFalse(b.showLife); XCTAssertTrue(b.showBiz)
        _ = try l.undo(changeID: c.id, author: "小晴")
        XCTAssertEqual(l.managedSides, .both)
        // 只管生活：生意模式不关，账还在
        try l.setManagedSides(.life, author: "小晴")
        XCTAssertEqual(l.business?.enabled, true); XCTAssertEqual(l.managedSides, .life)
        XCTAssertFalse(LedgerBridge.snapshot(of: l, today: today).showBiz)
    }

    func testManagedSidesOnALedgerWithoutBusiness() throws {
        var l = Ledger.fresh
        XCTAssertEqual(l.managedSides, .life)
        XCTAssertThrowsError(try l.setManagedSides(.life, author: "小晴"))
        // 选两边都管：顺手把生意模式打开（一条改动）
        let n = l.changes.count
        try l.setManagedSides(.both, author: "小晴")
        XCTAssertEqual(l.managedSides, .both); XCTAssertEqual(l.business?.enabled, true); XCTAssertEqual(l.changes.count, n + 1)
    }

    func testBridgeAppliesSides() throws {
        var l = ledger
        let before = LedgerBridge.snapshot(of: l, today: today)
        var after = before
        after.setManagedSides(.life)
        let r = try LedgerBridge.apply(before: before, after: after, to: &l, today: today, author: "小晴")
        XCTAssertEqual(r.count, 1); XCTAssertEqual(l.managedSides, .life)
        XCTAssertEqual(LedgerBridge.snapshot(of: l, today: today).managedSides, .life)
    }

    // MARK: 分类

    func testCategoriesComeFromTheLedgerAndAddRename() throws {
        var l = ledger
        let before = LedgerBridge.snapshot(of: l, today: today)
        XCTAssertEqual(before.categories.last?.name, "还没分")
        XCTAssertTrue(Set(before.categories.map(\.name)).isSuperset(of: l.allCategoryNames(income: false).subtracting(["还没分", "未分类"])))
        // 新建
        var after = before
        try after.addCategory(emoji: "🪴", name: "养花")
        let r = try LedgerBridge.apply(before: before, after: after, to: &l, today: today, author: "小晴")
        XCTAssertEqual(r.first?.author, "小晴")
        XCTAssertTrue(l.allCategoryNames(income: false).contains("养花"))
        XCTAssertTrue(LedgerBridge.snapshot(of: l, today: today).categories.contains { $0.name == "养花" })
        // 只换图标：这一版不接，账本不动
        let now = LedgerBridge.snapshot(of: l, today: today)
        var icon = now; icon.categories[0].emoji = "🧪"
        let keep = l
        XCTAssertThrowsError(try LedgerBridge.apply(before: now, after: icon, to: &l, today: today, author: "小晴"))
        XCTAssertEqual(l, keep)
    }
}
