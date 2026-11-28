#if os(macOS)
import FinanceCore
import XCTest
@testable import LedgerUI

/// 界面 v3 开发版：点了按钮以后数字对不对、撤销回不回得去。数字全是编的示例。
@MainActor
final class V3StateTests: XCTestCase {
    private func eur(_ s: String) -> Money { Money(parsing: s)! }

    func testDemoNumbersMatchTheDesign() {
        let s = V3State()
        XCTAssertEqual(s.book.month.left, eur("976,61"))
        XCTAssertEqual(s.book.totals.have, eur("8420"))
        XCTAssertEqual(s.book.totals.owe, eur("1840"))
        XCTAssertEqual(s.book.totals.net, eur("6580"))
        XCTAssertEqual(s.book.journey.remainingToNext, eur("181"))
        XCTAssertEqual(s.book.runway.monthsText, "2,8")
        // 四块加起来就是「一共有」；私房钱、借出去的不算
        let blocks = s.book.sum(.daily) + s.book.sum(.emergency) + s.book.sum(.goal) + s.book.sum(.shop)
        XCTAssertEqual(blocks, s.book.totals.have)
    }

    func testRecordThenUndo() {
        let s = V3State()
        let before = s.book
        s.record(QuickPhrase(name: "咖啡", emoji: "☕", amount: eur("3,20")), account: "现金", place: "Café Nube")
        XCTAssertEqual(s.book.month.left, eur("973,41"))
        XCTAssertEqual(s.book.today.first?.name, "咖啡")
        XCTAssertEqual(s.book.accounts.first { $0.name == "现金" }?.balance, eur("81,80"))
        XCTAssertEqual(s.toast?.canUndo, true)
        XCTAssertEqual(s.ledger.changes.first?.author, "你")
        XCTAssertEqual(s.ledger.changes.first?.kind, .add)
        s.undo()
        XCTAssertEqual(s.book, before)
        XCTAssertEqual(s.ledger.changes.first?.undone, true)
        XCTAssertNil(s.ledger.lastUndoable)
        // 没东西可撤时不出错
        s.undo()
        XCTAssertEqual(s.book, before)
    }

    func testDepositMovesMoneyAndDropsAStar() {
        let s = V3State()
        let net = s.book.totals.net
        XCTAssertTrue(s.deposit().isEmpty)
        XCTAssertEqual(s.book.journey.saved, eur("539"))
        XCTAssertEqual(s.book.accounts.first { $0.block == .goal }?.balance, eur("539"))
        XCTAssertEqual(s.book.accounts.first { $0.name == "日常卡" }?.balance, eur("1476,61"))
        XCTAssertEqual(s.book.totals.net, net, "自己账户之间挪钱，净剩不变")
        XCTAssertEqual(s.starDrops, 1)
        // 存够这一站：到 700 那一站
        let reached = s.deposit(s.book.journey.remainingToNext)
        XCTAssertEqual(reached.map(\.target), [eur("700")])
        let letter = s.arrivalLetter(for: reached[0])
        XCTAssertTrue(letter.tag.contains("700"))
        XCTAssertFalse(letter.paragraphs.isEmpty)
    }

    func testHalfGoesToEmergencyWhenAgreed() {
        let s = V3State()
        s.change("好，以后存钱自动对半分") { $0.splitWithEmergency = true }
        s.deposit(eur("20"))
        XCTAssertEqual(s.book.journey.saved, eur("529"))
        XCTAssertEqual(s.book.sum(.emergency), eur("2410"))
    }

    func testAddAccountChangesTotals() {
        let s = V3State()
        s.addAccount(emoji: "🤝", name: "跟朋友借的", note: "欠的钱", balance: eur("300"), kind: .debt)
        XCTAssertEqual(s.book.totals.owe, eur("2140"))
        XCTAssertEqual(s.book.totals.net, eur("6280"))
        s.addAccount(emoji: "🧑", name: "借给小王", note: "别人欠我", balance: eur("50"), kind: .lent)
        XCTAssertEqual(s.book.totals.have, eur("8420"), "借出去的收回来之前不算进一共有")
    }

    func testOnboardingStepsGoStraightIn() {
        let s = V3State()
        XCTAssertEqual(s.onboardingStep, 0)
        for _ in 0..<4 { s.nextStep() }
        XCTAssertEqual(s.onboardingStep, 4)
        s.previousStep()
        XCTAssertEqual(s.onboardingStep, 3)
        s.nextStep(); s.nextStep()
        XCTAssertNil(s.onboardingStep)
        XCTAssertNil(s.moment, "直接进总览")

        let t = V3State()
        t.ai = "Claude"
        for _ in 0..<5 { t.nextStep() }
        XCTAssertNil(t.moment, "连了 AI 也直接进总览，不再先定目标")
        XCTAssertEqual(t.page, .overview)
        let b = V3State()
        b.mode = .biz
        for _ in 0..<5 { b.nextStep() }
        XCTAssertEqual(b.page, .bizHome, "只管生意的进生意首页")
    }

    func testMonthNames() {
        XCTAssertEqual(V3State.monthName(after: 1), "12 月")
        XCTAssertEqual(V3State.monthName(after: 5), "明年 4 月")
        XCTAssertEqual(V3State.monthName(after: 14), "2028 年 1 月")
    }

    func testRulesComeFromTheCoreAndFailuresSayWhy() {
        let s = V3State()
        let before = s.book
        // 存的比账户里的多：什么都不变，底下说清为什么
        XCTAssertTrue(s.deposit(eur("5000")).isEmpty)
        XCTAssertEqual(s.book, before)
        XCTAssertEqual(s.toast?.isError, true)
        XCTAssertEqual(s.toast?.canUndo, false)
        XCTAssertEqual(s.starDrops, 0)
        XCTAssertNil(s.ledger.lastUndoable)
    }

    func testDeleteRecategorizeAndUndoFromTheLog() {
        let s = V3State()
        let start = s.book
        let lumi = s.book.entries.first { $0.place == "Super Lumi" }!
        XCTAssertTrue(s.change("归好了", kind: .categorize) { try $0.recategorize(entry: lumi.id, emoji: "🛒", name: "超市", always: true) })
        XCTAssertEqual(s.book.entries.first { $0.id == lumi.id }?.name, "超市")
        let afterFirst = s.book
        let coffee = s.book.today.first { $0.name == "咖啡" }!
        XCTAssertTrue(s.change("删掉了", kind: .remove) { try $0.delete(entry: coffee.id) })
        XCTAssertEqual(s.book.month.left, eur("979,81"))
        XCTAssertEqual(s.book.account("现金")?.balance, eur("88,20"))
        s.undo()
        XCTAssertEqual(s.book, afterFirst)
        // 在改动记录里撤销更早的一条：它后面的也一起撤回
        s.record(QuickPhrase(name: "打车", emoji: "🚕", amount: eur("15")), account: "日常卡")
        let first = s.ledger.changes.first { $0.kind == .categorize && !$0.undone && s.ledger.canUndo($0.id) }!
        s.undo(change: first.id)
        XCTAssertEqual(s.book, start)
    }

    func testShopDayFixedCostAndTransfer() {
        let s = V3State()
        let shop = s.book.account("小店账户")!.balance
        XCTAssertTrue(s.change("记好了") { try $0.recordShopDay(18, cash: self.eur("74"), card: self.eur("112")) })
        XCTAssertEqual(s.book.shopDays.first { $0.day == 18 }?.total, eur("186"))
        XCTAssertEqual(s.book.account("小店账户")?.balance, shop + eur("112"), "刷卡的进店的银行卡")
        XCTAssertEqual(s.book.account("店里现金")?.balance, eur("314"), "现金进店里现金")
        // 改同一天：只算差的
        XCTAssertTrue(s.change("改好了") { try $0.recordShopDay(18, cash: self.eur("74"), card: self.eur("100")) })
        XCTAssertEqual(s.book.account("小店账户")?.balance, shop + eur("100"))
        XCTAssertFalse(s.change("记好了") { try $0.recordShopDay(25, cash: self.eur("10"), card: .zero) }, "还没到的日子记不了")
        XCTAssertEqual(s.book.fixedTotal, eur("1790"))
        XCTAssertTrue(s.change("加好了") { try $0.addFixedCost(name: "店面保险", amount: self.eur("35"), note: "每月 12 日", canSkip: false) })
        XCTAssertEqual(s.book.fixedTotal, eur("1825"))
        let net = s.book.totals.net
        XCTAssertTrue(s.change("转好了") { try $0.transferBetweenSides(self.eur("300"), toHome: true, shopAccount: "小店账户", homeAccount: "日常卡") })
        XCTAssertEqual(s.book.totals.net, net, "两边挪钱，净剩不变")
    }

    func testMemoryCategoriesAndAccounts() {
        let s = V3State()
        let n = s.book.memos.count
        XCTAssertTrue(s.change("记下了") { try $0.remember(.rule, topic: "转给妈妈的钱", line: "明年 1 月起每月多转 50 €") })
        XCTAssertEqual(s.book.memos.count, n, "已经有这个话题：加在它下面，不另开一条")
        XCTAssertEqual(s.book.memos.first { $0.topic == "转给妈妈的钱" }?.lines.count, 2)
        let cafe = s.book.memos.first { $0.topic == "Café Nube" }!
        XCTAssertTrue(s.change("删掉了") { try $0.removeMemo(cafe.id) })
        s.undo()
        XCTAssertNotNil(s.book.memos.first { $0.id == cafe.id }, "删掉能撤销")
        // 彻底忘掉：撤销也回不来
        XCTAssertTrue(s.change("改了别的") { try $0.renameBook(.biz, to: "花店") })
        s.forget(memo: cafe.id)
        s.undo()
        XCTAssertNil(s.book.memos.first { $0.id == cafe.id })
        XCTAssertEqual(s.book.shopName, "晴空小花店")

        // 分类改成已有的名字 = 并成一个，流水一起改
        XCTAssertTrue(s.change("并好了") { try $0.editCategory("咖啡", newName: "餐饮", emoji: "☕") })
        XCTAssertFalse(s.book.categories.contains { $0.name == "咖啡" })
        XCTAssertEqual(s.book.today.first { $0.place == "Café Nube" }?.name, "餐饮")

        // 账户：改名流水跟着改；有流水的不能删
        XCTAssertTrue(s.change("存好了") { try $0.editAccount("现金", newName: "钱包", balance: self.eur("90"), secret: false) })
        XCTAssertEqual(s.book.today.first { $0.place == "Café Nube" }?.account, "钱包")
        XCTAssertFalse(s.change("删掉了") { try $0.removeAccount("钱包") })
        XCTAssertEqual(s.toast?.isError, true)
    }

    func testDeleteEverythingKeepsABackupAndEmptyBookDoesNotBreak() {
        let s = V3State()
        let before = s.book
        let backups = s.backups.count
        s.deleteEverything()
        XCTAssertTrue(s.book.isEmpty)
        XCTAssertEqual(s.backups.count, backups + 1)
        XCTAssertEqual(s.book.totals.net, .zero)
        XCTAssertFalse(s.book.memos.isEmpty, "记忆不删")
        // 空账本上常用的数都能算，不出错
        _ = s.book.journey.remainingToNext; _ = s.book.journey.position; _ = s.book.journey.overallFraction
        _ = s.book.journey.monthsToFinish(); _ = s.book.runway.monthsText; _ = s.book.month.perDay; _ = s.book.dailyBreakEven
        XCTAssertFalse(s.depositAndCelebrate(eur("20")), "空账本里存不了，但不崩")
        s.restore(s.backups[0].id)
        XCTAssertEqual(s.book, before)
    }

    func testSubscriptionCycleInstallmentQueuedGoalAndCapitalTotal() {
        let s = V3State()
        let monthly = s.book.subscriptionsMonthly
        XCTAssertTrue(s.change("加好了") { try $0.addSubscription(name: "域名", amount: self.eur("24"), note: "每年扣", forWork: true, cycle: 3) })
        XCTAssertEqual(s.book.subscriptionsMonthly, monthly + eur("2"), "一年 24 € 折成每月 2 €")
        let owe = s.book.totals.owe
        XCTAssertTrue(s.change("记上了") { try $0.addInstallment(name: "新冰箱", total: self.eur("600"), periods: 12, paid: 2, day: 8) })
        XCTAssertEqual(s.book.totals.owe, owe + eur("500"))
        XCTAssertEqual(s.book.upcoming.last?.amount, eur("50"))
        XCTAssertFalse(s.change("记上了") { try $0.addInstallment(name: "沙发", total: self.eur("600"), periods: 12, paid: 12, day: 8) })
        XCTAssertTrue(s.change("存成目标了") { try $0.queueGoal(name: "攒够 6 个月底气", total: self.eur("5160")) })
        XCTAssertEqual(s.book.nextGoals.first?.note, "排在「换新电脑」后面")
        XCTAssertEqual(s.book.journey.name, "换新电脑", "现在这条路不动")
        s.undo()
        XCTAssertTrue(s.book.nextGoals.isEmpty)
        XCTAssertTrue(s.change("存好了") { try $0.setCapitalTotal(self.eur("32000")) })
        XCTAssertEqual(s.book.capitalTotal, eur("32000"))
    }

    func testWhichSidesShow() {
        // 三种选择各自的导航清单
        let s = V3State()
        XCTAssertEqual(s.book.visiblePages, TrialBook.lifePages + TrialBook.bizPages)
        s.mode = .life
        XCTAssertEqual(s.book.visiblePages, TrialBook.lifePages)
        XCTAssertNil(s.ledger.lastUndoable, "引导里选的只是设初值，不留记录")
        s.go(.payback)
        XCTAssertEqual(s.page, .overview, "关着的那边去不了")
        s.mode = .biz
        XCTAssertEqual(s.book.visiblePages, TrialBook.bizPages)
        XCTAssertEqual(s.side, .biz)
        XCTAssertEqual(s.page, .bizHome, "正停在被关掉的那边：跳到还开着的那边第一页")

        // 至少开一个：最后一个关不掉，什么都不变
        XCTAssertFalse(s.setSides(life: false, biz: false))
        XCTAssertEqual(s.mode, .biz)
        XCTAssertThrowsError(try { var b = s.book; try b.setSides(life: false, biz: false) }())

        // 关了再开，数据还在；设置里改的能撤销
        let shop = s.book.shopDays, entries = s.book.entries
        XCTAssertTrue(s.setSides(life: true, biz: false))
        XCTAssertEqual(s.page, .overview)
        XCTAssertEqual(s.book.shopDays, shop)
        XCTAssertTrue(s.setSides(life: true, biz: true))
        XCTAssertEqual(s.book.shopDays, shop)
        XCTAssertEqual(s.book.entries, entries)
        s.undo()
        XCTAssertEqual(s.mode, .life)
    }

    /// 只用编的假密钥和内存里的假钥匙串，不碰真的钥匙串。
    func testOwnAPIKeySaveSwapDelete() {
        let s = V3State()
        let store = MemorySecretStore()
        s.keyStore = store
        XCTAssertNil(s.apiProvider)
        XCTAssertFalse(s.saveAPIKey("   ", provider: .anthropic))
        XCTAssertEqual(s.toast?.isError, true)
        XCTAssertTrue(s.saveAPIKey(" sk-demo-000 ", provider: .anthropic))
        XCTAssertEqual(s.apiProvider, .anthropic)
        XCTAssertEqual(s.ai, V3State.aiOwnAPI)
        XCTAssertEqual(store.peek("anthropic"), "sk-demo-000")
        // 密钥不进账本、不进改动记录、不进提示条
        XCTAssertNil(s.ledger.lastUndoable)
        XCTAssertFalse(s.ledger.changes.contains { $0.summary.contains("sk-demo") })
        XCTAssertFalse(s.toast?.text.contains("sk-demo") ?? true)
        // 换一家：原来那家的删掉
        XCTAssertFalse(s.saveAPIKey("sk-demo-111", provider: .custom, address: "http://example.com"), "自定义地址要 https")
        XCTAssertTrue(s.saveAPIKey("sk-demo-111", provider: .custom, address: "https://api.example.com/v1"))
        XCTAssertEqual(s.apiProvider, .custom)
        XCTAssertNil(store.peek("anthropic"))
        s.deleteAPIKey()
        XCTAssertNil(s.apiProvider)
        XCTAssertNil(store.peek("custom"))
        XCTAssertNil(s.ai)
    }

    func testNavOrderAndBuyFlow() {
        XCTAssertEqual(V3State.Page.life.map(\.rawValue), ["overview", "transactions", "spending", "wealth", "debts", "subscriptions", "goals", "trends", "monthly"])
        XCTAssertEqual(V3State.Page.biz.map(\.rawValue), ["bizHome", "sales", "shopWealth", "fixed", "stock", "bizDebts", "payback", "checkup"])
        XCTAssertNil(V3State.Page(rawValue: "think"), "「花钱前想想」那一页没有了")
        // 先放着想想 → 进想要清单；不要了 → 钱进目标；都能撤销
        let s = V3State()
        let n = s.book.wanted.count, saved = s.book.journey.saved
        XCTAssertTrue(s.change("放进想要清单了") { try $0.addWanted(name: "降噪耳机", price: self.eur("279")) })
        XCTAssertEqual(s.book.wanted.count, n + 1)
        let w = s.book.wanted.first { $0.name == "降噪耳机" }!
        s.resist(wanted: w)
        XCTAssertEqual(s.book.journey.saved, saved + eur("279"))
        s.undo(); s.undo()
        XCTAssertEqual(s.book.wanted.count, n)
        XCTAssertEqual(s.book.journey.saved, saved)
    }

    func testEmergencyIsASetting() {
        let s = V3State()
        XCTAssertEqual(s.book.emergencyAccounts.map(\.name), ["储蓄"], "示例里默认是储蓄，但只是数据")
        XCTAssertTrue(s.change("设好了") { try $0.setEmergency(accounts: ["储蓄", "现金"], months: 6) })
        XCTAssertEqual(s.book.sum(.emergency), eur("2485"))
        XCTAssertEqual(s.book.emergencyGoalMonths, 6)
        XCTAssertFalse(s.change("设好了") { try $0.setEmergency(accounts: ["目标罐"], months: 3) })
        s.undo()
        XCTAssertEqual(s.book.emergencyAccounts.map(\.name), ["储蓄"])
    }

    func testAccountListsComeFromOnePlace() {
        let s = V3State()
        XCTAssertEqual(s.book.accounts(for: .pay).map(\.name), ["日常卡", "现金", "信用卡"], "能付钱的：日常的账户加信用卡；储蓄、目标罐、分期不行")
        // 新加一张卡以后，付钱、收钱、转出、转入各处都能选到
        XCTAssertTrue(s.addAccount(emoji: "💳", name: "新开的卡", note: "", balance: eur("300"), kind: .own))
        for use in [TrialBook.AccountUse.pay, .receive, .moveOut, .moveIn] {
            XCTAssertTrue(s.book.accounts(for: use).contains { $0.name == "新开的卡" }, "\(use)")
        }
        XCTAssertEqual(s.book.accounts(for: .pay, side: .biz).map(\.name), ["小店账户", "店里现金", "店的信用卡"], "店里能付钱的：店的账户加店的信用卡；贷款不行")
        // 刷信用卡：欠的变多，删掉这笔欠的变回去
        let owed = s.book.account("信用卡")!.balance
        XCTAssertTrue(s.change("记好了") { try $0.record(name: "超市", emoji: "🛒", amount: self.eur("40"), account: "信用卡") })
        XCTAssertEqual(s.book.account("信用卡")?.balance, owed + eur("40"))
        s.undo()
        XCTAssertEqual(s.book.account("信用卡")?.balance, owed)
    }

    func testTransferReadsAsFromTo() {
        let s = V3State()
        let net = s.book.totals.net
        XCTAssertEqual(s.book.transferShortcuts.map(\.title), ["存进储蓄", "还信用卡", "取现金", "放进目标罐"])
        XCTAssertTrue(s.change("转好了") { try $0.transfer(self.eur("100"), from: "日常卡", to: "储蓄") })
        XCTAssertEqual(s.book.account("储蓄")?.balance, eur("2500"))
        XCTAssertEqual(s.book.totals.net, net, "自己账户之间转，净剩不变")
        XCTAssertTrue(s.change("转好了") { try $0.transfer(self.eur("640"), from: "日常卡", to: "信用卡") }, "转给信用卡就是还款")
        XCTAssertEqual(s.book.account("信用卡")?.balance, .zero)
        let saved = s.book.journey.saved
        XCTAssertTrue(s.change("转好了") { try $0.transfer(self.eur("20"), from: "现金", to: "目标罐") }, "转进目标罐就是存一笔")
        XCTAssertEqual(s.book.journey.saved, saved + eur("20"))
        XCTAssertFalse(s.change("转好了") { try $0.transfer(self.eur("20"), from: "现金", to: "现金") }, "从和到不能是同一个")
        XCTAssertFalse(s.change("转好了") { try $0.transfer(self.eur("20"), from: "目标罐", to: "现金") }, "目标罐里的钱不能这样转出来")
    }

    func testSpendSlices() {
        let b = V3State().book
        XCTAssertEqual(b.spendSliceTotal, b.month.spentTotal, "圆环和大数是同一个口径")
        XCTAssertEqual(b.spendSlices().first?.name, "房租")
        XCTAssertEqual(b.spendSlices(limit: 3).map(\.name), ["房租", "手机分期", "其他"])
        XCTAssertEqual(b.spendSlices(limit: 3).map(\.amount).reduce(.zero, +), b.spendSliceTotal)
    }

    /// 试用版的示例数据全是编的：不能出现真实的店名、银行、商户（和正式版示例数据同一张拦截单）。
    func testDemoDataHasNoRealNames() {
        let s = V3State()
        let b = s.book
        var words: [String] = [b.lifeName, b.shopName]
        words += b.accounts.flatMap { [$0.name, $0.note, $0.short] }
        words += (b.entries + b.upcoming).flatMap { [$0.name, $0.meta, $0.place, $0.account, $0.note, $0.tag] }
        words += (b.subscriptions + b.wanted + b.fixedCosts + b.purchases + b.stockEstimates + b.capital + b.shopDebts).flatMap { [$0.name, $0.note, $0.tag] }
        words += b.memos.flatMap { [$0.topic, $0.source] + $0.lines }
        words += b.letters.flatMap { [$0.title, $0.quote, $0.headline] + $0.paragraphs }
        words += b.spendByCategory.map(\.name) + b.categories.map(\.name) + [b.journey.name, b.journey.why]
        words += s.ledger.changes.flatMap { [$0.summary, $0.author] }
        words += s.aiLinks.map(\.note) + s.backups.map(\.title)
        let all = words.joined(separator: "\n").lowercased()
        for word in ["miora", "caixa", "imagin", "revolut", "mercadona", "glovo", "amazon", "netflix", "spotify", "美甲", "甲油"] {
            XCTAssertFalse(all.contains(word), "示例数据里出现了「\(word)」")
        }
    }

    func testOneBigGoalAndUpToThreeSmallOnes() {
        let s = V3State()
        XCTAssertEqual(s.book.smallGoals.count, 3)
        XCTAssertFalse(s.book.canAddSmallGoal)
        XCTAssertFalse(s.change("加上了") { try $0.addSmallGoal(name: "第四个", target: self.eur("50")) }, "最多 3 个小目标")
        XCTAssertTrue(s.toast?.text.contains("目标不在多") ?? false)
        // 存进小目标：钱从账户进目标罐，大目标不动
        let shoes = s.book.smallGoals.first { $0.name == "新跑鞋" }!
        let saved = s.book.journey.saved
        XCTAssertTrue(s.change("存好了") { try $0.depositSmall(shoes.id, amount: self.eur("35"), from: "日常卡") })
        XCTAssertTrue(s.book.smallGoals.first { $0.id == shoes.id }!.isDone)
        XCTAssertEqual(s.book.journey.saved, saved)
        XCTAssertTrue(s.book.canAddSmallGoal, "存够了的不算，位置空出来了")
        // 设成大目标：原来的大目标变成小目标
        let trip = s.book.smallGoals.first { $0.name == "周末短途旅行" }!
        XCTAssertTrue(s.change("换好了") { try $0.promoteSmallGoal(trip.id) })
        XCTAssertEqual(s.book.journey.name, "周末短途旅行")
        XCTAssertEqual(s.book.journey.saved, eur("120"))
        XCTAssertTrue(s.book.smallGoals.contains { $0.name == "换新电脑" && $0.saved == saved })
        s.undo()
        XCTAssertEqual(s.book.journey.name, "换新电脑")
        // 删小目标：存的钱回日常卡
        let daily = s.book.account("日常卡")!.balance
        let gift = s.book.smallGoals.first { $0.name == "给妈妈的生日礼物" }!
        XCTAssertTrue(s.change("删掉了") { try $0.removeSmallGoal(gift.id) })
        XCTAssertEqual(s.book.account("日常卡")?.balance, daily + eur("15"))
    }

    func testHoldBackAndSavedPhraseDoNotAssumeCoffee() {
        let s = V3State()
        XCTAssertNil(s.book.smallHabit, "示例流水里没有买过 3 次以上的小东西：不瞎猜")
        XCTAssertEqual(s.book.savedPhrase(eur("86")), "等于少花 3 天的零花")
        // 常买奶茶的人，说的就是奶茶
        s.patch { b in
            for d in [1, 3, 5, 8] { _ = try? b.record(name: "奶茶", emoji: "🧋", amount: self.eur("4,50"), account: "现金", place: "茶铺", daysAgo: d) }
        }
        XCTAssertEqual(s.book.smallHabit?.name, "茶铺")
        XCTAssertEqual(s.book.savedPhrase(eur("18")), "等于少买 4 次茶铺")
        let saved = s.book.journey.saved, resisted = s.book.journey.resisted
        XCTAssertTrue(s.change("算你忍住一次") { try $0.holdBack(name: "", amount: self.eur("4,50")) })
        XCTAssertEqual(s.book.journey.saved, saved + eur("4,50"))
        XCTAssertEqual(s.book.journey.resisted, resisted + 1)
        XCTAssertEqual(s.book.wanted.first?.tag, "忍住了")
    }

    func testShopWorthAndShopAccounts() {
        let s = V3State()
        let w = s.book.shopWorth
        XCTAssertEqual(w.cash, eur("3919,39"), "店的银行卡 + 店里现金")
        XCTAssertEqual(w.stock, eur("2600"))
        XCTAssertEqual(w.owedToShop, eur("85"))
        XCTAssertEqual(w.owes, eur("8900"), "贷款 8.400 + 信用卡 180 + 欠供货商 320")
        XCTAssertEqual(w.net, eur("-2295,61"))
        XCTAssertEqual(w.monthsText, "2,2")
        XCTAssertEqual(s.book.totals.have, eur("8420"), "生活家底的「一共有」口径没变")
        XCTAssertEqual(s.book.totals.owe, eur("1840"), "店里欠的不算进生活的欠款")
        // 店里新加一张卡：家底、记账选账户、两边转钱都看得到
        XCTAssertTrue(s.change("加好了") { try $0.addShopAccount(emoji: "🏪", name: "店的第二张卡", balance: self.eur("500"), owes: false) })
        XCTAssertEqual(s.book.shopWorth.cash, eur("4419,39"))
        XCTAssertTrue(s.book.accounts(for: .pay, side: .biz).contains { $0.name == "店的第二张卡" })
        XCTAssertTrue(s.book.accounts(for: .receive, side: .biz).contains { $0.name == "店的第二张卡" })
        XCTAssertFalse(s.book.accounts(for: .pay, side: .life).contains { $0.name == "店的第二张卡" }, "店的卡不出现在生活的记一笔里")
        XCTAssertTrue(s.change("加好了") { try $0.addShopAccount(emoji: "🏦", name: "设备贷款", balance: self.eur("1000"), owes: true) })
        XCTAssertEqual(s.book.shopWorth.owes, eur("9900"))
        // 能删（没流水的），至少留一个放钱的
        XCTAssertTrue(s.change("删掉了") { try $0.removeAccount("店的第二张卡") })
        s.undo()
        XCTAssertNotNil(s.book.account("店的第二张卡"))
    }

    /// 用假的验证器，不弹系统的框。
    func testLockTurnsOnLocksAndUnlocks() async {
        let s = V3State()
        XCTAssertFalse(s.lockPolicy.enabled, "默认不上锁")
        s.lockIfNeeded(.launch)
        XCTAssertFalse(s.locked)
        // 验证没过：开关不变
        s.authenticator = V3FakeAuthenticator(ok: false)
        let refused = await s.setLock(enabled: true)
        XCTAssertFalse(refused)
        XCTAssertFalse(s.lockPolicy.enabled)
        s.authenticator = V3FakeAuthenticator(ok: true)
        let turnedOn = await s.setLock(enabled: true)
        XCTAssertTrue(turnedOn)
        s.setLock(grace: 60)
        // 启动就锁；锁上时小窗、聊天都收起来
        s.showAdd = true; s.chatOpen = true
        s.lockIfNeeded(.launch)
        XCTAssertTrue(s.locked)
        XCTAssertFalse(s.showAdd)
        XCTAssertFalse(s.chatOpen)
        // 验证失败或取消：停在锁屏
        s.authenticator = V3FakeAuthenticator(ok: false)
        await s.unlock()
        XCTAssertTrue(s.locked)
        s.authenticator = V3FakeAuthenticator(ok: true)
        await s.unlock()
        XCTAssertFalse(s.locked)
        // 离开不到 1 分钟不锁，超过才锁
        s.awaySince = Date().addingTimeInterval(-20); s.appCameBack()
        XCTAssertFalse(s.locked)
        s.awaySince = Date().addingTimeInterval(-90); s.appCameBack()
        XCTAssertTrue(s.locked)
    }

    func testGoingToBizSwitchesSide() {
        let s = V3State()
        s.go(.payback)
        XCTAssertEqual(s.side, .biz)
        s.switchSide(.life)
        XCTAssertEqual(s.page, .overview)
    }
}
#endif
