import XCTest
@testable import FinanceCore

/// 按月取数：能选哪些月、过去的月份拿到的是那个月的数。
final class TrialMonthsTests: XCTestCase {
    private func eur(_ s: String) -> Money { Money(parsing: s)! }

    private func book() -> TrialBook {
        var b = TrialBook(accounts: [.init(emoji: "💳", name: "日常卡", note: "", balance: eur("1500"))], entries: [], upcoming: [],
                          month: FreeToSpend(income: eur("2340"), fixed: eur("892"), forGoals: eur("200"), spent: eur("271,39"), daysLeft: 12),
                          journey: Journey(name: "换新电脑", stops: [eur("700")], saved: .zero), monthlyMust: eur("860"))
        b.spendByCategory = [.init(emoji: "🛒", name: "超市", amount: eur("142,19"), lastMonth: eur("162"))]
        b.pastMonths = [
            .init(key: .init(2026, 10), income: eur("2340"), fixed: eur("892"), forGoals: eur("200"), spent: eur("612"),
                  slices: [.init(emoji: "🛒", name: "超市", amount: eur("162"), lastMonth: eur("150")), .init(emoji: "💊", name: "看病", amount: eur("120"), lastMonth: .zero)]),
            .init(key: .init(2026, 8), income: eur("2100"), fixed: eur("892"), forGoals: .zero, spent: eur("700")),
        ]
        return b
    }

    func testWhichMonthsCanBePicked() {
        let b = book()
        XCTAssertEqual(b.thisMonth, .init(2026, 11))
        XCTAssertEqual(b.months, [.init(2026, 8), .init(2026, 9), .init(2026, 10), .init(2026, 11)], "从最早有数据的月到这个月，一个不漏")
        XCTAssertEqual(b.clampMonth(.init(2026, 12)), .init(2026, 11), "还没到的月份选不了")
        XCTAssertEqual(b.clampMonth(.init(2027, 1)), .init(2026, 11))
        XCTAssertEqual(b.clampMonth(.init(2025, 3)), .init(2026, 8), "比最早的还早也选不了")
        XCTAssertEqual(TrialBook.MonthKey(2026, 1).previous, .init(2025, 12))
        XCTAssertEqual(TrialBook.MonthKey(2025, 12).next, .init(2026, 1))
        XCTAssertEqual(TrialBook.MonthKey(2026, 10).label(thisYear: 2026), "10 月")
        XCTAssertEqual(TrialBook.MonthKey(2025, 12).label(thisYear: 2026), "2025 年 12 月")
    }

    func testEachMonthHasItsOwnNumbers() {
        let b = book()
        let now = b.monthData(b.thisMonth)
        XCTAssertEqual(now.spentTotal, b.month.spentTotal)
        XCTAssertEqual(now.left, b.month.left, "这个月的是账本里现算的")
        XCTAssertEqual(now.slices, b.spendByCategory)
        let oct = b.monthData(.init(2026, 10))
        XCTAssertEqual(oct.spentTotal, eur("1504"))
        XCTAssertEqual(oct.left, eur("636"), "2.340 − 892 − 200 − 612")
        XCTAssertEqual(oct.topSlices().map(\.name), ["超市", "看病"])
        XCTAssertEqual(oct.sliceTotal, eur("282"))
        let sep = b.monthData(.init(2026, 9))
        XCTAssertEqual(sep.spentTotal, .zero, "中间没数据的月份全是 0，不会拿别的月的数顶上")
        XCTAssertEqual(b.monthData(.init(2027, 5)), now, "还没到的月份：给这个月的")
    }

    func testChangingThisMonthDoesNotTouchPastMonths() throws {
        var b = book()
        let oct = b.monthData(.init(2026, 10))
        try b.record(name: "午饭", emoji: "🍜", amount: eur("12"), account: "日常卡")
        XCTAssertEqual(b.monthData(.init(2026, 10)), oct)
        XCTAssertEqual(b.monthData(b.thisMonth).spent, eur("283,39"))
    }

    /// 检查报告第 16 条：数据页、账本页的笔数是同一份；改动记录页「自己进来 + 手记」不超过总数。
    func testEntryCountsAgreeEverywhere() throws {
        var b = TrialBook.demo
        XCTAssertEqual(b.counts.entries, b.entryCounts.life + b.entryCounts.shop)
        let before = b.counts.entries, hand = b.entrySources.hand
        let pay = b.accounts(for: .pay, side: .life).first!.name
        try b.record(name: "咖啡", emoji: "☕", amount: Money(cents: 3_20), account: pay)
        XCTAssertEqual(b.counts.entries, before + 1)
        XCTAssertEqual(b.entrySources.hand, hand + 1, "手记的多一笔")
        XCTAssertLessThanOrEqual(b.entrySources.auto + b.entrySources.hand, b.counts.entries)
    }

    /// 趋势页的折线：累计到今天 = 这个月一共花掉；记一笔，线的末端跟着涨；每天只增不减。
    func testSpendPaceFollowsTheBook() throws {
        var b = TrialBook.demo
        let p = b.spendPace
        XCTAssertEqual(p.soFar.count, b.todayDay)
        XCTAssertEqual(p.soFar.last, b.month.spentTotal)
        XCTAssertTrue(zip(p.soFar, p.soFar.dropFirst()).allSatisfy { $0 <= $1 })
        XCTAssertEqual(p.last.last, b.previousMonthData?.spentTotal)
        XCTAssertEqual(p.weeks.reduce(.zero, +), b.month.spent, "每周平时花的加起来 = 这个月平时花的")
        let pay = b.accounts(for: .pay, side: .life).first!.name
        try b.record(name: "咖啡", emoji: "☕", amount: Money(cents: 3_20), account: pay)
        XCTAssertEqual(b.spendPace.soFar.last, p.soFar.last! + Money(cents: 3_20))
        XCTAssertEqual(b.spendPace.soFar.last, b.month.spentTotal)
    }

    /// 每月小结里那几句话都是从那个月的数算出来的：数变了话跟着变，没有就不写。
    func testMonthNotesComeFromTheNumbers() throws {
        let b = TrialBook.demo
        let oct = TrialBook.MonthKey(2026, 10)
        let d = b.monthData(oct), sep = b.monthData(.init(2026, 9))
        let good = b.monthGood(oct), watch = b.monthWatch(oct)
        XCTAssertLessThanOrEqual(good.count, 3); XCTAssertLessThanOrEqual(watch.count, 1)
        XCTAssertTrue(good.contains { $0.title == "存进了目标" && $0.amount == d.forGoals.formatted })
        // 十月净剩比九月多：写出来的就是这两个月底的差
        let more = d.net - sep.net
        XCTAssertGreaterThan(more, .zero)
        XCTAssertTrue(good.contains { $0.title == "家底多了" && $0.amount == "+" + more.formatted })
        // 要留意的：就是比上个月多花得最多的那一样，数是两个月的差
        let worst = d.slices.filter { $0.lastMonth > .zero && $0.amount > $0.lastMonth }.max { ($0.amount - $0.lastMonth) < ($1.amount - $1.lastMonth) }!
        XCTAssertEqual(watch.first?.title, worst.name)
        XCTAssertEqual(watch.first?.amount, "+" + (worst.amount - worst.lastMonth).formatted)
        // 一个没数据的月份：什么都不写，不编
        var empty = b
        empty.pastMonths = [TrialBook.MonthData(key: oct, income: .zero, fixed: .zero, forGoals: .zero, spent: .zero)]
        XCTAssertTrue(empty.monthGood(oct).isEmpty); XCTAssertTrue(empty.monthWatch(oct).isEmpty)
        // 进账不够花：要留意的是这一条
        var tight = b
        tight.pastMonths[0].income = Money(cents: 100_00)
        XCTAssertEqual(tight.monthWatch(oct).first?.title, "花的比进的多")
    }

    /// 总览上关于存钱的那一句是算出来的：没定每月存多少就不说；差多少就是「打算存的 − 已经存的」。
    func testSavingRemarkIsComputed() throws {
        var b = TrialBook.demo
        let plan = b.journey.monthlyPlan, saved = b.journey.savedThisMonth
        XCTAssertEqual(b.savingRemark, "这个月打算存 \(plan.formatted)，还差 \((plan - saved).formatted)。")
        b.journey.monthlyPlan = .zero
        XCTAssertNil(b.savingRemark, "没定就不说")
        b.journey.monthlyPlan = saved
        XCTAssertEqual(b.savingRemark, "这个月打算存的 \(saved.formatted) 已经存够了。")
        b.journey.monthlyPlan = plan
        b.month.spent = b.month.spent + b.month.left + Money(cents: 1)
        XCTAssertTrue(b.savingRemark?.contains("钱不太够") ?? false)
    }

    /// 订阅页那一问的依据只有「一年多少钱」：问的是一年下来最贵的两个，数是周期 × 金额；赚钱用的、要退的不问。
    func testSubscriptionQuestionIsAboutYearlyCost() throws {
        var b = TrialBook.demo
        XCTAssertFalse(b.subscriptions.contains { $0.note.contains("没怎么用") || $0.note.contains("重了") }, "示例里不再写死用没用")
        let ask = b.subscriptionsToAsk
        XCTAssertEqual(ask.count, 2)
        let rest = b.subscriptions.filter { s in !s.off && !s.flag && !ask.contains { $0.id == s.id } }
        XCTAssertTrue(rest.allSatisfy { r in ask.allSatisfy { $0.yearly >= r.yearly } }, "问的是一年下来最贵的")
        XCTAssertEqual(b.subscriptionsQuestion, ask.map { "「\($0.name)」一年下来是 \($0.yearly.formatted)" }.joined(separator: "、") + "，还要吗？")
        try b.addSubscription(name: "设计软件", amount: Money(cents: 60_00), note: "", forWork: true, cycle: 1)
        XCTAssertFalse(b.subscriptionsToAsk.contains { $0.name == "设计软件" }, "赚钱要用的不问")
        try b.setSubscription(ask[0].name, dropped: true)
        XCTAssertFalse(b.subscriptionsToAsk.contains { $0.name == ask[0].name }, "已经要退的不再问")
        var none = b; none.subscriptions = []
        XCTAssertNil(none.subscriptionsQuestion)
    }

    /// 「步子改小一点」那一屏：月底大概能存多少是按速度算的；进账少了多少是和上个月比出来的，没少就没有那句。
    func testSmallerStepSceneNumbersAreComputed() {
        var b = TrialBook.demo
        let days = Calendar(identifier: .gregorian).range(of: .day, in: .month, for: b.todayDate)!.count
        XCTAssertEqual(b.projectedSavedThisMonth, Money(cents: b.journey.savedThisMonth.cents * Int64(days) / Int64(b.todayDay)))
        XCTAssertEqual(b.savingIsBehind, b.projectedSavedThisMonth < b.journey.monthlyPlan)
        // 示例里这个月进账和上个月一样：没有那句
        XCTAssertEqual(b.month.income, b.previousMonthData?.income)
        XCTAssertNil(b.incomeDropNote)
        // 进账少了 260：说少了 260；花得不比上月同期多，才说不是乱花
        b.month.income = b.month.income - Money(cents: 260_00)
        XCTAssertEqual(b.incomeDropNote, "这个月进账比上个月少了 260,00 €，不是你乱花。")
        b.month.spent = b.month.spent + Money(cents: 500_00)
        XCTAssertEqual(b.incomeDropNote, "这个月进账比上个月少了 260,00 €。")
        b.pastMonths = []
        XCTAssertNil(b.incomeDropNote)
    }
}
