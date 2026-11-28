#if os(macOS)
import FinanceCore
import AppKit
import SwiftUI
import XCTest
@testable import LedgerUI

/// 界面 v3 开发版：点了按钮以后数字对不对、撤销回不回得去。数字全是编的示例。
@MainActor
final class V3StateTests: XCTestCase {
    private func eur(_ s: String) -> Money { Money(parsing: s)! }

    func testDemoNumbersMatchTheDesign() {
        let s = V3State()
        XCTAssertEqual(s.book.month.left, eur("976,61"))
        XCTAssertEqual(s.book.totals.have, eur("4815,61"), "生活的「一共有」不含店里的钱")
        XCTAssertEqual(s.book.totals.owe, eur("1840"))
        XCTAssertEqual(s.book.totals.net, eur("2975,61"))
        XCTAssertEqual(s.book.journey.remainingToNext, eur("181"))
        XCTAssertEqual(s.book.runway.monthsText, "2,8")
        // 几块加起来就是「一共有」；店里的钱不算
        XCTAssertEqual(s.book.wealthBlocks.map(\.amount).reduce(.zero, +), s.book.totals.have)
        XCTAssertEqual(s.book.wealthBlocks.first { $0.name == "日常能用" }?.amount, eur("1581,61"), "日常能用 = 日常卡 + 现金，不含储蓄的 2.400")
        XCTAssertEqual(s.book.wealthBlocks.map(\.name), ["存在目标里", "存着不动", "日常能用", "借出去的"])
    }

    func testFixedCostsAccountDayAndRises() {
        let s = V3State()
        XCTAssertEqual(s.book.usualFixedAccount, "小店账户", "默认从用得最多的那个账户扣")
        XCTAssertEqual(s.book.fixedRises.map(\.item.name), ["水电", "预约软件"], "涨得多的排前面")
        XCTAssertEqual(s.book.fixedRises.map(\.rise), [eur("12"), eur("5")])
        XCTAssertFalse(s.change("加好了") { try $0.addFixedCost(name: "店面保险", amount: self.eur("35"), day: 12, account: "日常卡") }, "生活的账户不能扣店里的固定开销")
        XCTAssertFalse(s.change("加好了") { try $0.addFixedCost(name: "店面保险", amount: self.eur("35"), day: 32, account: "小店账户") })
        XCTAssertTrue(s.change("加好了") { try $0.addFixedCost(name: "店面保险", amount: self.eur("35"), day: 31, account: "店的信用卡") }, "店的信用卡也能扣")
        let x = s.book.fixedCosts.first { $0.name == "店面保险" }
        XCTAssertEqual(x?.note, "每月 31 日 · 店的信用卡")
        XCTAssertEqual(s.book.fixedRises.count, 2, "新加的不算涨")
        // 改贵了：记住原来多少，出现在「比上个月多了的」里；再改一次，还是跟最早那个数比
        XCTAssertTrue(s.change("改好了") { try $0.editFixedCost("店面房租", amount: self.eur("650"), day: 5, account: "小店账户") })
        XCTAssertTrue(s.change("改好了") { try $0.editFixedCost("店面房租", amount: self.eur("660")) })
        XCTAssertEqual(s.book.fixedRises.first?.item.name, "店面房租")
        XCTAssertEqual(s.book.fixedRises.first?.rise, eur("60"))
        XCTAssertEqual(s.book.fixedCosts.first { $0.name == "店面房租" }?.note, "每月 5 日 · 小店账户")
        // 停着的不算
        XCTAssertTrue(s.change("停") { try $0.setFixedCost("水电", paused: true) })
        XCTAssertFalse(s.book.fixedRises.contains { $0.item.name == "水电" })
        // 分期也能选从哪扣；店里的账户不行
        XCTAssertFalse(s.change("记") { try $0.addInstallment(name: "新冰箱", total: self.eur("600"), periods: 12, paid: 0, day: 8, from: "小店账户") })
        XCTAssertTrue(s.change("记") { try $0.addInstallment(name: "新冰箱", total: self.eur("600"), periods: 12, paid: 0, day: 8, from: "日常卡") })
        XCTAssertEqual(s.book.upcoming.last?.account, "日常卡")
    }

    func testShopChannelsExpensesAndFlow() {
        let s = V3State()
        let bank = s.book.account("小店账户")!.balance, cash = s.book.account("店里现金")!.balance
        // 按渠道记今天：每个渠道的钱进各自的账户
        XCTAssertTrue(s.change("记") { try $0.recordShopDay(18, channels: [.init("小店账户", self.eur("112")), .init("店里现金", self.eur("74"))]) })
        let day = s.book.shopDays.first { $0.day == 18 }!
        XCTAssertEqual(day.total, eur("186"))
        XCTAssertEqual(s.book.channels(of: day).map(\.account), ["小店账户", "店里现金"])
        XCTAssertEqual(s.book.account("小店账户")?.balance, bank + eur("112"))
        XCTAssertEqual(s.book.account("店里现金")?.balance, cash + eur("74"))
        // 改同一天：只算差的；只填总数就进常用的那个渠道
        XCTAssertTrue(s.change("改") { try $0.recordShopDay(18, channels: [.init($0.usualShopChannel, self.eur("200"))]) })
        XCTAssertEqual(s.book.account("小店账户")?.balance, bank + eur("200"))
        XCTAssertEqual(s.book.account("店里现金")?.balance, cash)
        // 新加一个渠道（店账户）马上能用；生活的账户、欠款账户不能当渠道
        XCTAssertTrue(s.change("加") { try $0.addShopAccount(emoji: "📟", name: "收款机", balance: .zero, owes: false) })
        XCTAssertTrue(s.change("改") { try $0.recordShopDay(18, channels: [.init("收款机", self.eur("50")), .init("小店账户", self.eur("150"))]) })
        XCTAssertEqual(s.book.account("收款机")?.balance, eur("50"))
        XCTAssertFalse(s.change("改") { try $0.recordShopDay(18, channels: [.init("日常卡", self.eur("50"))]) })
        XCTAssertFalse(s.change("改") { try $0.recordShopDay(18, channels: [.init("店的信用卡", self.eur("50"))]) })
        // 老记法的那些天也能按渠道看
        let old = s.book.shopDays.first { $0.day == 17 }!
        XCTAssertEqual(s.book.channels(of: old).map(\.amount).reduce(.zero, +), old.total)
        // 休息：把这天收的从各个账户里退回去
        XCTAssertTrue(s.change("休") { try $0.markShopRest(18) })
        XCTAssertEqual(s.book.account("收款机")?.balance, .zero)
        XCTAssertEqual(s.book.account("小店账户")?.balance, bank)
        // 店里的开销：分类、账户、日期
        let out = s.book.shopFlowOut, life = s.book.month.spent
        XCTAssertTrue(s.change("记") { try $0.recordShopExpense(name: "胶带", amount: self.eur("12"), category: "包装耗材", account: "店里现金", daysAgo: 2) })
        XCTAssertEqual(s.book.shopFlowOut, out + eur("12"))
        XCTAssertEqual(s.book.account("店里现金")?.balance, cash - eur("12"))
        XCTAssertEqual(s.book.month.spent, life, "店里的开销不算进生活这个月花掉的")
        XCTAssertEqual(s.book.shopFlow.first { $0.detail.contains("胶带") }?.day, 16)
        XCTAssertFalse(s.change("记") { try $0.recordShopExpense(name: "x", amount: self.eur("5"), category: "餐饮", account: "店里现金") }, "只认生意的分类")
        XCTAssertFalse(s.change("记") { try $0.recordShopExpense(name: "x", amount: self.eur("5"), category: "进货", account: "日常卡") }, "生活的账户不能付店里的开销")
        // 刷店的信用卡：欠的变多
        XCTAssertTrue(s.change("记") { try $0.recordShopExpense(name: "海报", amount: self.eur("30"), category: "广告", account: "店的信用卡") })
        XCTAssertEqual(s.book.account("店的信用卡")?.balance, eur("210"))
        // 流水：收的是正的、花的是负的，新的在前，全是店里的
        let flow = s.book.shopFlow
        XCTAssertEqual(flow.map(\.day), flow.map(\.day).sorted(by: >))
        XCTAssertEqual(s.book.shopFlowIn, s.book.shopSalesTotal)
        XCTAssertEqual(TrialBook.shopCategories.count, 11)
        // 按日子记：这个月里的进那一天；上个月的按渠道各记一笔店里的收入；还没到的不行
        let b2 = s.book.account("小店账户")!.balance
        XCTAssertTrue(s.change("记") { try $0.recordShopIncome(daysAgo: 2, channels: [.init("小店账户", self.eur("90"))]) })
        XCTAssertEqual(s.book.shopDays.first { $0.day == 16 }?.total, eur("90"), "16 号原来没记")
        XCTAssertTrue(s.change("记") { try $0.recordShopIncome(daysAgo: 30, channels: [.init("小店账户", self.eur("70")), .init("店里现金", self.eur("10"))]) })
        XCTAssertEqual(s.book.account("小店账户")?.balance, b2 + eur("160"))
        XCTAssertEqual(s.book.entries.filter { $0.side == .biz && $0.daysAgo == 30 }.count, 2)
        XCTAssertFalse(s.change("记") { try $0.recordShopIncome(daysAgo: -1, channels: [.init("小店账户", self.eur("70"))]) })
        XCTAssertFalse(s.change("记") { try $0.recordShopIncome(daysAgo: 30, channels: [.init("日常卡", self.eur("70"))]) })
        // 进货、还供货商也能选账户
        XCTAssertTrue(s.change("进") { try $0.addPurchase(name: "花泥", amount: self.eur("20"), note: "今天", account: "店里现金") })
        XCTAssertEqual(s.book.account("店里现金")?.balance, cash - eur("32") + eur("10"))
        XCTAssertFalse(s.change("进") { try $0.addPurchase(name: "花泥", amount: self.eur("20"), note: "今天", account: "日常卡") })
    }

    func testDeleteAndEditGoals() {
        let s = V3State()
        let have = s.book.totals.have, daily = s.book.account("日常卡")!.balance, jar = s.book.sum(.goal)
        let small = s.book.smallGoals[0]
        // 改大目标：名字、金额；已存的不变
        XCTAssertTrue(s.change("改") { try $0.editBigGoal(name: "换新笔记本", total: self.eur("1600")) })
        XCTAssertEqual(s.book.journey.name, "换新笔记本")
        XCTAssertEqual(s.book.journey.total, eur("1600"))
        XCTAssertEqual(s.book.journey.saved, eur("519"))
        XCTAssertFalse(s.change("改") { try $0.editBigGoal(name: small.name, total: self.eur("1600")) }, "不能和小目标重名")
        // 删大目标，钱挪给一个小目标：钱还在目标罐里
        XCTAssertFalse(s.change("删") { try $0.removeBigGoal(moneyTo: .bigGoal) })
        XCTAssertTrue(s.change("删") { try $0.removeBigGoal(moneyTo: .smallGoal(small.id)) })
        XCTAssertEqual(s.book.journey.total, .zero, "删完没有大目标")
        XCTAssertEqual(s.book.smallGoals[0].saved, small.saved + eur("519"))
        XCTAssertEqual(s.book.sum(.goal), jar)
        XCTAssertEqual(s.book.totals.have, have, "钱只是换了地方")
        XCTAssertFalse(s.change("删") { try $0.removeBigGoal() }, "没有大目标了")
        // 撤销：大目标回来
        s.undo()
        XCTAssertEqual(s.book.journey.saved, eur("519"))
        // 删大目标，钱放回账户（不说放哪，就是第一个日常能用的）
        XCTAssertTrue(s.change("删") { try $0.removeBigGoal() })
        XCTAssertEqual(s.book.account("日常卡")?.balance, daily + eur("519"))
        XCTAssertEqual(s.book.sum(.goal), jar - eur("519"))
        XCTAssertEqual(s.book.totals.have, have)
        XCTAssertFalse(s.change("删") { try $0.removeSmallGoal(small.id, moneyTo: .bigGoal) }, "没有大目标，挪不过去")
        XCTAssertFalse(s.change("删") { try $0.removeSmallGoal(small.id, moneyTo: .smallGoal(small.id)) }, "不能挪给自己")
        XCTAssertFalse(s.change("删") { try $0.removeSmallGoal(small.id, moneyTo: .account("小店账户")) }, "不能放进店里的账户")
        let other = s.book.smallGoals[1]
        XCTAssertTrue(s.change("删") { try $0.removeSmallGoal(small.id, moneyTo: .smallGoal(other.id)) })
        XCTAssertEqual(s.book.smallGoals.first { $0.id == other.id }?.saved, other.saved + small.saved)
        XCTAssertEqual(s.book.smallGoals.count, 2)
    }

    func testJarMatchesGoalsAndFinishedBigGoal() {
        let s = V3State()
        XCTAssertEqual(s.book.sum(.goal), eur("714"), "519 + 120 + 60 + 15")
        XCTAssertEqual(s.book.sum(.goal), s.book.goalMoney)
        XCTAssertFalse(s.book.journey.isFinished, "示例的大目标还在走")
        XCTAssertFalse(s.change("收") { try $0.archiveBigGoal() }, "没存够不能收")
        let have = s.book.totals.have
        // 存够大目标 → 收进走完的路，钱放回日常卡，位置空出来
        XCTAssertTrue(s.change("存") { _ = try $0.deposit($0.journey.total - $0.journey.saved, from: "储蓄") })
        XCTAssertTrue(s.book.journey.isFinished)
        XCTAssertEqual(s.book.sum(.goal), s.book.goalMoney)
        XCTAssertTrue(s.change("收") { try $0.archiveBigGoal() })
        XCTAssertEqual(s.book.journey.total, .zero)
        XCTAssertEqual(s.book.finishedGoals.first?.name, "换新电脑")
        XCTAssertEqual(s.book.finishedGoals.first?.date, "2026 年 11 月")
        XCTAssertEqual(s.book.sum(.goal), s.book.goalMoney)
        XCTAssertEqual(s.book.sum(.goal), eur("195"), "只剩小目标的钱")
        XCTAssertEqual(s.book.totals.have, have)
        // 定一个新的大目标：从 0 开始，不会把小目标的钱算成它的
        XCTAssertTrue(s.change("定") { try $0.startGoal(name: "去海边住一周", total: self.eur("800")) })
        XCTAssertEqual(s.book.journey.saved, .zero)
        XCTAssertEqual(s.book.sum(.goal), s.book.goalMoney)
    }

    func testFilesGoThroughXia() async throws {
        let s = V3State()
        s.onboardingStep = nil
        XCTAssertEqual(V3AddSheet.ways, ["说一句", "自己填"], "记一笔里没有「拖文件」了")
        let before = s.book.entries.count
        // 交一份流水：打开聊天，带着文件，什么都还没写入
        s.handToXia()
        XCTAssertTrue(s.chatOpen)
        XCTAssertEqual(s.chat.last?.attachment, "📄 晴空银行 11 月流水.csv")
        XCTAssertEqual(s.book.entries.count, before, "确认之前不写入")
        try await Task.sleep(for: .seconds(1))
        guard case .statement(_, let total, let added, let skipped)? = s.chat.last?.confirm else { return XCTFail("夏夏应该回一张流水确认卡") }
        XCTAssertEqual(total, added + skipped)
        XCTAssertEqual(s.book.entries.count, before, "卡出来了也还没写入")
        // 链接、带着「要不要买」的图：不是来记账的
        XCTAssertFalse(s.hand(.link("https://example.com/x"), text: ""))
        XCTAssertFalse(s.hand(.image(NSImage(size: .init(width: 4, height: 4)), "耳机.jpg"), text: "这个要不要买"))
        // 一张图：当小票，回小票确认卡
        XCTAssertTrue(s.hand(.image(NSImage(size: .init(width: 4, height: 4)), "小票.jpg"), text: ""))
        XCTAssertNotNil(s.chat.last?.thumb)
        try await Task.sleep(for: .seconds(1))
        guard case .receipt(let place, let amount, let account)? = s.chat.last?.confirm else { return XCTFail("夏夏应该回一张小票确认卡") }
        XCTAssertEqual(place, "Super Sol"); XCTAssertEqual(amount, eur("23,40")); XCTAssertEqual(account, "日常卡")
        XCTAssertEqual(s.book.entries.count, before)
    }

    func testMonthSwitchIsSharedAndClamped() {
        let s = V3State()
        XCTAssertTrue(s.isThisMonth); XCTAssertEqual(s.monthLabel, "11 月")
        XCTAssertEqual(s.book.months.map(\.month), [9, 10, 11])
        s.setMonth(.init(2026, 10))
        XCTAssertEqual(s.monthLabel, "10 月")
        s.page = .spending; XCTAssertEqual(s.monthKey, .init(2026, 10), "换页还是同一个月")
        XCTAssertEqual(s.monthData.spentTotal, eur("1504,40"))
        XCTAssertEqual(s.monthData.sliceTotal, eur("1504,40"))
        XCTAssertEqual(s.monthData.left, eur("635,60"))
        XCTAssertNotEqual(s.monthData.topSlices().map(\.name), s.book.spendSlices().map(\.name), "圆环和单子是那个月的")
        s.setMonth(.init(2027, 3)); XCTAssertTrue(s.isThisMonth, "还没到的月份选不了")
        s.setMonth(.init(2020, 1)); XCTAssertEqual(s.monthKey, .init(2026, 9), "最早到有数据的那个月")
        s.setMonth(s.book.thisMonth); XCTAssertNil(s.viewMonth, "回到这个月")
        XCTAssertEqual(s.monthData.spentTotal, s.book.month.spentTotal)
    }

    func testDonutKnowsWhichSliceTheMouseIsOn() {
        // 两段各一半：右半边是第一段，左半边是第二段；圆心和环外面都不算
        let slices: [(id: String, value: Double)] = [("甲", 50), ("乙", 50)]
        let side: CGFloat = 200
        func hit(_ x: CGFloat, _ y: CGFloat) -> String? { V3Donut<EmptyView>.slice(at: CGPoint(x: x, y: y), side: side, slices: slices) }
        XCTAssertEqual(hit(180, 100), "甲")
        XCTAssertEqual(hit(20, 100), "乙")
        XCTAssertEqual(hit(110, 15), "甲", "正上方偏右一点是第一段的开头")
        XCTAssertEqual(hit(90, 15), "乙", "正上方偏左一点是最后一段的结尾")
        XCTAssertNil(hit(100, 100), "圆心是空的")
        XCTAssertNil(hit(2, 2), "环外面")
    }

    func testOneGoalOneAccount() {
        let s = V3State()
        XCTAssertTrue(s.book.goalAccountsAreConsistent, "示例：每个目标各有一个存钱罐，已存 = 余额")
        XCTAssertEqual(s.book.accounts.filter { $0.block == .goal }.map(\.balance), [eur("519"), eur("120"), eur("60"), eur("15")])
        XCTAssertFalse(s.book.accounts.contains { $0.name == "目标罐" }, "合在一起的那个目标罐没了")
        XCTAssertEqual(s.book.goalPlaceCandidates.map(\.name), ["储蓄"], "已有账户只列存起来的，不列日常卡、现金、信用卡、别的目标的")
        var plain = V3State.demoBook; plain.lifePins = []
        XCTAssertEqual(plain.pinned(on: .life).map(\.name), ["日常卡", "换新电脑 存钱罐"], "默认置顶日常卡和大目标那张")
        var have = s.book.totals.have
        // 存一笔 = 从日常卡转到这个目标的账户，总数不变
        XCTAssertTrue(s.change("存") { _ = try $0.deposit(self.eur("30"), from: "日常卡") })
        XCTAssertEqual(s.book.bigGoalHome?.balance, eur("549")); XCTAssertEqual(s.book.totals.have, have)
        XCTAssertFalse(s.change("存") { _ = try $0.deposit(self.eur("5"), from: "新跑鞋 存钱罐") }, "不能拿别的目标的钱来存")
        XCTAssertTrue(s.book.goalAccountsAreConsistent)
        // 在管理账户里改目标账户的余额：目标已存跟着变
        XCTAssertTrue(s.change("改") { try $0.editAccount("换新电脑 存钱罐", newName: "换新电脑 存钱罐", balance: self.eur("600"), secret: false) })
        XCTAssertEqual(s.book.journey.saved, eur("600"))
        have = s.book.totals.have   // 手动把余额改多了 51，后面拿这个数当基准
        // 小目标满了先删一个，再加一个放进已有账户的：储蓄里的 2.400 算已存，储蓄不再能给别的目标用
        let shoes = s.book.smallGoals.first { $0.name == "新跑鞋" }!
        XCTAssertTrue(s.change("删") { try $0.removeSmallGoal(shoes.id, moneyTo: .account("日常卡")) })
        XCTAssertNil(s.book.account("新跑鞋 存钱罐"), "为它新开的存钱罐跟着删")
        XCTAssertEqual(s.book.totals.have, have)
        XCTAssertFalse(s.change("加") { try $0.addSmallGoal(name: "攒个底", target: self.eur("3000"), place: .existing("日常卡")) }, "日常卡不能拿来放目标的钱")
        XCTAssertTrue(s.change("加") { try $0.addSmallGoal(name: "攒个底", target: self.eur("3000"), place: .existing("储蓄")) })
        let base = s.book.smallGoals.first { $0.name == "攒个底" }!
        XCTAssertEqual(base.saved, eur("2400")); XCTAssertFalse(base.ownsAccount)
        XCTAssertTrue(s.book.goalPlaceCandidates.isEmpty, "一个账户只能对一个目标")
        XCTAssertFalse(s.change("定") { try $0.addSmallGoal(name: "x", target: self.eur("50"), place: .existing("储蓄")) })
        XCTAssertTrue(s.book.goalAccountsAreConsistent)
        XCTAssertEqual(s.book.totals.have, have)
        // 删这个目标：钱留在原账户，储蓄留着、只是不再算目标的
        XCTAssertTrue(s.change("删") { try $0.removeSmallGoal(base.id, moneyTo: .stay) })
        XCTAssertEqual(s.book.account("储蓄")?.balance, eur("2400")); XCTAssertEqual(s.book.account("储蓄")?.block, .emergency)
        XCTAssertEqual(s.book.goalPlaceCandidates.map(\.name), ["储蓄"])
        XCTAssertFalse(s.change("删") { try $0.removeBigGoal(moneyTo: .stay) }, "新开的存钱罐会删，钱不能留在里面")
        // 换大目标：账户跟着目标走
        let trip = s.book.smallGoals.first { $0.name == "周末短途旅行" }!
        XCTAssertTrue(s.change("换") { try $0.promoteSmallGoal(trip.id) })
        XCTAssertEqual(s.book.bigGoalHome?.name, "周末短途旅行 存钱罐")
        XCTAssertTrue(s.book.goalAccountsAreConsistent)
        // 改名：存钱罐跟着改名
        XCTAssertTrue(s.change("改") { try $0.editBigGoal(name: "去海边", total: self.eur("300")) })
        XCTAssertEqual(s.book.bigGoalHome?.name, "去海边 存钱罐")
        // 删大目标：钱回日常卡，存钱罐删掉；再定一个新的放进储蓄
        XCTAssertTrue(s.change("删") { try $0.removeBigGoal() })
        XCTAssertNil(s.book.account("去海边 存钱罐"))
        XCTAssertTrue(s.change("定") { try $0.startGoal(name: "攒首付", total: self.eur("9000"), place: .existing("储蓄")) })
        XCTAssertEqual(s.book.journey.saved, eur("2400")); XCTAssertFalse(s.book.bigGoalOwnsAccount)
        XCTAssertTrue(s.book.goalAccountsAreConsistent)
        XCTAssertEqual(s.book.totals.have, have, "怎么折腾，总数都不变")
    }

    func testSurpriseExpenses() {
        let s = V3State()
        let oct = TrialBook.MonthKey(2026, 10)
        // 10 月两笔：看牙 120、手机换屏幕 89，都是之前标成意外的（按规则它们没到那个月花销的一成）
        XCTAssertEqual(s.book.surprises(in: oct).map(\.place), ["牙科诊所 Sonrisa", "手机换屏幕"])
        XCTAssertEqual(s.book.surprises(in: oct).map(\.amount).reduce(.zero, +), -eur("209"))
        XCTAssertTrue(s.book.surprises(in: s.book.thisMonth).isEmpty, "11 月都是平常的花销")
        // 「这不算意外」：拿掉，能撤销
        let tooth = s.book.surprises(in: oct)[0]
        XCTAssertTrue(s.change("好") { try $0.markSurprise(tooth.id, false) })
        XCTAssertEqual(s.book.surprises(in: oct).map(\.place), ["手机换屏幕"])
        s.undo()
        XCTAssertEqual(s.book.surprises(in: oct).count, 2)
        // 这个月记一笔大的：按规则算意外；流水里也能手动标、手动取消
        XCTAssertTrue(s.change("记") { try $0.record(name: "看病", emoji: "💊", amount: self.eur("180"), account: "日常卡", place: "急诊") })
        XCTAssertEqual(s.book.surprises(in: s.book.thisMonth).map(\.place), ["急诊"])
        let coffee = s.book.entries.first { $0.name == "咖啡" }!
        XCTAssertTrue(s.change("标") { try $0.markSurprise(coffee.id, true) })
        XCTAssertEqual(s.book.surprises(in: s.book.thisMonth).count, 2)
        XCTAssertFalse(s.change("标") { try $0.markSurprise(UUID(), true) })
        // 用的是正式账本那条规则的同一段：同类 3 次以上看 3 倍，否则看一成
        XCTAssertTrue(Outlook.isUnusual(amount: 100_00, sameCategory: [10_00, 12_00, 30_00], monthly: 5000_00))
        XCTAssertFalse(Outlook.isUnusual(amount: 30_00, sameCategory: [10_00, 12_00, 30_00], monthly: 100_00))
        XCTAssertTrue(Outlook.isUnusual(amount: 120_00, sameCategory: [], monthly: 1000_00))
        XCTAssertFalse(Outlook.isUnusual(amount: 89_00, sameCategory: [], monthly: 1500_00))
    }

    func testRealLedgerSnapshotIsReadOnly() {
        let real = DemoData.make(endingOn: LocalDate(year: 2026, month: 11, day: 18))
        let s = V3State(snapshotOf: real, today: LocalDate(year: 2026, month: 11, day: 18))
        XCTAssertTrue(s.readOnly); XCTAssertNil(s.onboardingStep)
        XCTAssertFalse(s.book.accounts.isEmpty); XCTAssertFalse(s.book.entries.isEmpty)
        let before = s.book
        // 只看不写：记一笔、改、删都被挡住，并且说人话
        let acc = s.book.accounts(for: .pay, side: .life).first?.name ?? ""
        XCTAssertFalse(s.change("记") { try $0.record(name: "午饭", emoji: "🍜", amount: self.eur("9"), account: acc) })
        XCTAssertTrue(s.toast?.text.contains("只能看") ?? false)
        XCTAssertTrue(s.book == before)
        XCTAssertEqual(s.monthLabel, "11 月")
    }

    func testRealLedgerWritesGoThroughChangeRecords() {
        let day = LocalDate(year: 2026, month: 11, day: 18)
        let real = DemoData.make(endingOn: day)
        let s = V3State(snapshotOf: real, today: day, writable: true)
        s.author = "小满"
        let n = real.transactions.count, changes = real.changes.count
        let acc = s.book.accounts(for: .pay, side: .life).first { $0.kind == .own }!.name
        let before = s.book.account(acc)!.balance
        // 记一笔：正式账本多一笔流水 + 一条写明作者的改动记录；界面上的余额跟着变
        XCTAssertTrue(s.change("记好了") { try $0.record(name: "餐饮", emoji: "🥗", amount: self.eur("12,50"), account: acc, place: "La Tasca", daysAgo: 1) })
        XCTAssertEqual(s.real?.transactions.count, n + 1)
        let tx = s.real!.transactions.last!
        XCTAssertEqual(tx.amount, -eur("12,50")); XCTAssertEqual(tx.category, "餐饮"); XCTAssertEqual(tx.description, "La Tasca")
        XCTAssertEqual(tx.date, LocalDate(year: 2026, month: 11, day: 17), "昨天记的落在昨天")
        XCTAssertEqual(s.real?.changes.count, changes + 1)
        XCTAssertEqual(s.real?.changes.last?.author, "小满")
        XCTAssertEqual(s.book.account(acc)?.balance, before - eur("12,50"))
        XCTAssertTrue(s.book.entries.contains { $0.id == tx.id })
        // 改分类、改金额：都是正式账本自己的改法
        XCTAssertTrue(s.change("归好了") { try $0.recategorize(entry: tx.id, emoji: "🛒", name: "超市", always: false) })
        XCTAssertEqual(s.real?.transactions.first { $0.id == tx.id }?.category, "超市")
        XCTAssertTrue(s.change("改好了") { try $0.setAmount(entry: tx.id, to: self.eur("15")) })
        XCTAssertEqual(s.real?.transactions.first { $0.id == tx.id }?.amount, -eur("15"))
        XCTAssertEqual(s.book.account(acc)?.balance, before - eur("15"))
        // 撤销：一步一步退回去
        s.undo(); XCTAssertEqual(s.real?.transactions.first { $0.id == tx.id }?.amount, -eur("12,50"))
        s.undo(); XCTAssertEqual(s.real?.transactions.first { $0.id == tx.id }?.category, "餐饮")
        // 删，再撤销
        XCTAssertTrue(s.change("删掉了") { _ = try $0.delete(entry: tx.id) })
        XCTAssertEqual(s.real?.transactions.count, n)
        s.undo(); XCTAssertEqual(s.real?.transactions.count, n + 1)
        s.undo(); XCTAssertEqual(s.real?.transactions.count, n, "记的那一笔也撤掉了")
        XCTAssertEqual(s.book.account(acc)?.balance, before)
        // 还没接的（目标、订阅、转账…）：拒绝，正式账本一个字不动
        let snapshot = s.real
        XCTAssertFalse(s.change("改") { try $0.setMonthlyPlan(self.eur("123")) })
        XCTAssertTrue(s.toast?.text.contains("还没接上") ?? false)
        XCTAssertEqual(s.real, snapshot)
        // 没写记账人：不让写
        s.author = "  "
        XCTAssertFalse(s.change("记") { try $0.record(name: "餐饮", emoji: "🥗", amount: self.eur("5"), account: acc) })
        XCTAssertEqual(s.real, snapshot)
    }

    // MARK: 检查报告里的数（每个数只有一处算法，记一笔后一起变）

    /// 这个月花掉 = 固定要付的 + 平时花的 = 圆环各段加起来。任何时候都得成立。
    private func assertSpendingAgrees(_ s: V3State, _ note: String, line: UInt = #line) {
        XCTAssertEqual(s.book.spendSliceTotal, s.book.month.spentTotal, "花销页：大数和圆环、分类对不上 · \(note)", line: line)
        XCTAssertEqual(s.monthData.spentTotal, s.book.month.spentTotal, "按月取的数和总览的不是一个 · \(note)", line: line)
        XCTAssertEqual(s.monthData.sliceTotal, s.monthData.spentTotal, line: line)
        XCTAssertEqual(s.book.month.left, s.book.month.income - s.book.month.spentTotal - s.book.month.forGoals, line: line)
    }

    func testSpendingPageAgreesWithItselfAfterEveryChange() {
        let s = V3State()
        assertSpendingAgrees(s, "一开始")
        let total = s.book.month.spentTotal, left = s.book.month.left
        // 记两笔：大数、圆环、那一类都跟着变
        XCTAssertTrue(s.change("记") { try $0.record(name: "餐饮", emoji: "🥗", amount: self.eur("100"), account: "日常卡", place: "Bar Luna") })
        XCTAssertTrue(s.change("记") { try $0.record(name: "宠物", emoji: "🐾", amount: self.eur("650"), account: "日常卡", place: "宠物医院") })
        XCTAssertEqual(s.book.month.spentTotal, total + eur("750"))
        XCTAssertEqual(s.book.month.left, left - eur("750"))
        XCTAssertEqual(s.book.spendSlices().first { $0.name == "餐饮" }?.amount, eur("168,40"))
        XCTAssertEqual(s.book.spendSlices().first { $0.name == "宠物" }?.amount, eur("650"), "新的一类自己出现在圆环里")
        assertSpendingAgrees(s, "记两笔后")
        // 删一笔原来就有的超市：圆环也少
        let market = s.book.entries.first { $0.name == "超市" && $0.daysAgo == 0 }!
        XCTAssertTrue(s.change("删") { _ = try $0.delete(entry: market.id) })
        XCTAssertEqual(s.book.spendSlices().first { $0.name == "超市" }?.amount, eur("142,19") + market.amount)
        assertSpendingAgrees(s, "删一笔后")
        // 改分类、改金额、撤销
        let bar = s.book.entries.first { $0.place == "Bar Luna" }!
        XCTAssertTrue(s.change("改") { try $0.recategorize(entry: bar.id, emoji: "☕", name: "咖啡", always: false) })
        XCTAssertEqual(s.book.spendSlices().first { $0.name == "餐饮" }?.amount, eur("68,40"))
        assertSpendingAgrees(s, "改分类后")
        XCTAssertTrue(s.change("改") { try $0.setAmount(entry: bar.id, to: self.eur("40")) })
        assertSpendingAgrees(s, "改金额后")
        s.undo(); s.undo(); s.undo(); s.undo(); s.undo()
        XCTAssertEqual(s.book.month.spentTotal, total)
        assertSpendingAgrees(s, "全撤销后")
        // 记到上个月的那一笔：不算进这个月
        XCTAssertTrue(s.change("记") { try $0.record(name: "餐饮", emoji: "🥗", amount: self.eur("30"), account: "日常卡", daysAgo: 25) })
        XCTAssertEqual(s.book.month.spentTotal, total)
        assertSpendingAgrees(s, "记到上个月后")
        // 过去的月份：总数和分类也对得上
        for k in s.book.months { XCTAssertEqual(s.book.monthData(k).sliceTotal, s.book.monthData(k).spentTotal, "\(k.month) 月") }
    }

    func testFixedCostsAreNotChargedTwice() {
        let s = V3State()
        let left = s.book.month.left, total = s.book.month.spentTotal
        XCTAssertEqual(s.book.fixedPlan.values.reduce(.zero, +), s.book.month.fixed, "固定要付的 892 就是这几样加起来")
        // 手记房租 650：固定开销里已经算过，「还能随便花」不动；账户里的钱照样少
        let card = s.book.account("日常卡")!.balance
        XCTAssertTrue(s.change("记") { try $0.record(name: "房租", emoji: "🏠", amount: self.eur("650"), account: "日常卡") })
        XCTAssertEqual(s.book.month.left, left, "不扣第二遍")
        XCTAssertEqual(s.book.month.spentTotal, total)
        XCTAssertEqual(s.book.account("日常卡")?.balance, card - eur("650"))
        XCTAssertEqual(s.book.fixedPaid["房租"], eur("650"))
        assertSpendingAgrees(s, "手记房租后")
        // 房租涨了，再交 50：多出来的才算平时花的
        XCTAssertTrue(s.change("记") { try $0.record(name: "房租", emoji: "🏠", amount: self.eur("50"), account: "日常卡") })
        XCTAssertEqual(s.book.month.left, left - eur("50"))
        assertSpendingAgrees(s, "多交 50 后")
        // 订阅同理：计划 42，记 9,99 不动；删掉房租那笔，也不会多退
        XCTAssertTrue(s.change("记") { try $0.record(name: "订阅", emoji: "🔁", amount: self.eur("9,99"), account: "日常卡") })
        XCTAssertEqual(s.book.month.left, left - eur("50"))
        let rent = s.book.entries.first { $0.name == "房租" && $0.amount == -self.eur("650") }!
        XCTAssertTrue(s.change("删") { _ = try $0.delete(entry: rent.id) })
        XCTAssertEqual(s.book.month.left, left - eur("50"))
        XCTAssertEqual(s.book.fixedPaid["房租"], .zero)
        assertSpendingAgrees(s, "删掉房租那笔后")
    }

    func testShopNumbersHaveOneAlgorithmAndFollowTheBooks() {
        let s = V3State()
        let m = s.book.shopMonth()
        XCTAssertEqual(m.income, eur("2881")); XCTAssertEqual(m.costs, eur("1124,50")); XCTAssertEqual(m.purchases, eur("460")); XCTAssertEqual(m.loanPaid, eur("350"))
        XCTAssertEqual(m.earned, eur("1756,50"), "真正赚了 = 收的 − 开销")
        XCTAssertEqual(m.cashChange, eur("946,50"), "手里实际多了 = 真正赚了 − 进的货 − 还的贷款")
        XCTAssertEqual(m.income, s.book.shopFlowIn); XCTAssertEqual(m.out, s.book.shopFlowOut, "和流水页是同一份")
        XCTAssertEqual(s.monthData.shopIn, m.income)
        XCTAssertEqual(s.book.shopPer100.map(\.euros).reduce(0, +), 100)
        XCTAssertEqual(s.book.purchasesThisMonth.map(\.amount).reduce(.zero, +), -eur("460"), "货值页和流水是同一份：鲜花 340 + 绿植 120")
        // 一天收多少不亏：固定 1.790 + 贷款 350 + 进货 460，除以打算开门的 25 天（周日休息不算）
        XCTAssertEqual(s.book.plannedOpenDays, 25)
        XCTAssertEqual(s.book.dailyBreakEven, eur("104"))
        // 店一共欠：贷款 8.400 + 店的信用卡 180 + 赊着的 320
        XCTAssertEqual(s.book.shopOwesTotal, eur("8900")); XCTAssertEqual(s.book.shopOwesTotal, s.book.shopWorth.owes)
        XCTAssertEqual(s.book.shopDueNext, eur("850"), "贷款月供 350 + 信用卡 180 + 赊着的 320")
        let back = s.book.shopBack, months = s.book.paybackMonths()!
        // 记收 2.000、进货 900：首页、回本、体检、不亏线都跟着变
        XCTAssertTrue(s.change("记") { try $0.recordShopDay(18, channels: [.init("小店账户", self.eur("2000"))]) })
        XCTAssertTrue(s.change("进") { try $0.recordShopExpense(name: "年底备货", amount: self.eur("900"), category: "进货", account: "小店账户") })
        let n = s.book.shopMonth()
        XCTAssertEqual(n.income, eur("4881")); XCTAssertEqual(n.earned, eur("3756,50")); XCTAssertEqual(n.purchases, eur("1360"))
        XCTAssertEqual(n.cashChange, eur("2046,50"))
        XCTAssertEqual(s.book.shopBack, back + eur("2000")); XCTAssertLessThan(s.book.paybackMonths()!, months)
        XCTAssertEqual(s.book.dailyBreakEven, eur("140"), "(1.790 + 350 + 1.360) ÷ 25")
        XCTAssertEqual(s.book.shopPer100.map(\.euros).reduce(0, +), 100)
        // 记一笔开销（不是进货）：真正赚了少这么多
        XCTAssertTrue(s.change("记") { try $0.recordShopExpense(name: "修门", amount: self.eur("56,50"), category: "维修", account: "店里现金") })
        XCTAssertEqual(s.book.shopMonth().earned, eur("3700"))
        // 周日休息：一周里那天的平均是 0
        XCTAssertEqual(s.book.shopWeekdayAverages.count, 7); XCTAssertEqual(s.book.shopWeekdayAverages[6], .zero)
    }

    func testMonthComparisonsComeFromStoredMonths() {
        let s = V3State()
        XCTAssertEqual(s.book.netMoreThanLastMonth, eur("490"), "净剩 2.975,61 − 10 月底 2.485,61")
        XCTAssertEqual(s.book.spentLessThanLastMonthSameDay, eur("86"), "10 月花到 18 号是 1.249,39")
        let oct = s.book.monthData(.init(2026, 10))
        XCTAssertEqual(oct.have - oct.owe, oct.net, "月底净剩 = 有 − 欠")
        XCTAssertEqual(s.book.netChange(in: .init(2026, 10)), eur("385,41"))
        XCTAssertEqual(oct.left, eur("635,60"), "总览切到 10 月和小结用的是同一份")
        // 趋势页的两个数也是现算的
        XCTAssertEqual(s.book.projectedMonthSpend, eur("1535,39"), "已经花掉 1.163,39 + 一天 31 × 还有 12 天")
        XCTAssertEqual(s.book.upcomingTotal, eur("1490"), "房租 650 + 信用卡 640 + 手机分期 200")
        // 记一笔以后，「比上月同期」跟着变
        XCTAssertTrue(s.change("记") { try $0.record(name: "餐饮", emoji: "🥗", amount: self.eur("86"), account: "日常卡") })
        XCTAssertEqual(s.book.spentLessThanLastMonthSameDay, .zero)
        XCTAssertEqual(s.book.netMoreThanLastMonth, eur("404"))
    }

    func testRealLedgerAccountChanges() {
        let day = LocalDate(year: 2026, month: 11, day: 18)
        let real = DemoData.make(endingOn: day)
        let s = V3State(snapshotOf: real, today: day, writable: true)
        s.author = "小满"
        let have = s.book.inHand, n = real.accounts.count
        // 加一个账户（带现有的钱）：正式账本多一个账户 + 一笔期初余额；合计多这么多
        XCTAssertTrue(s.change("加") { try $0.addAccount(emoji: "💳", name: "新开的卡", note: "", balance: self.eur("300"), kind: .own) })
        XCTAssertEqual(s.real?.accounts.count, n + 1)
        let id = s.real!.accounts.last!.id
        XCTAssertEqual(s.real?.transactions.last?.flow, .opening)
        XCTAssertEqual(s.book.account("新开的卡")?.balance, eur("300"))
        XCTAssertEqual(s.book.inHand, have + eur("300"))
        XCTAssertEqual(s.real?.changes.last?.author, "小满")
        // 改名 + 改余额：账户改名，期初余额挪了差的那么多，流水一笔没多
        let txs = s.real!.transactions.count
        XCTAssertTrue(s.change("改") { try $0.editAccount("新开的卡", newName: "旅行卡", balance: self.eur("450"), secret: false) })
        XCTAssertEqual(s.real?.accounts.first { $0.id == id }?.name, "旅行卡")
        XCTAssertEqual(s.book.account("旅行卡")?.balance, eur("450"))
        XCTAssertEqual(s.real?.transactions.count, txs)
        // 置顶、换底色、换先后：记在正式账本的账户上（只加了两个字段）
        XCTAssertTrue(s.change("置顶") { try $0.setPinned("旅行卡", true) })
        XCTAssertNotNil(s.real?.accounts.first { $0.id == id }?.cardPin)
        XCTAssertTrue(s.book.pinned(on: .life).contains { $0.name == "旅行卡" })
        XCTAssertTrue(s.change("换") { try $0.setCardStyle("旅行卡", 3) })
        XCTAssertEqual(s.real?.accounts.first { $0.id == id }?.cardStyle, 3)
        XCTAssertEqual(s.book.account("旅行卡")?.cardLook, 3)
        XCTAssertTrue(s.change("排") { try $0.movePin("旅行卡", to: 0) })
        XCTAssertEqual(s.real?.accounts.first { $0.id == id }?.cardPin, 0)
        XCTAssertEqual(s.book.pinned(on: .life).first?.name, "旅行卡")
        // 存下来再读回来：字段还在；没有这两个字段的老数据照样读得出来
        let data = try! JSONEncoder().encode(s.real!.accounts.first { $0.id == id }!)
        XCTAssertEqual(try! JSONDecoder().decode(FinanceCore.Account.self, from: data).cardStyle, 3)
        let oldJSON = Data(#"{"id":"x","name":"老账户","kind":"bank"}"#.utf8)
        XCTAssertNil(try! JSONDecoder().decode(FinanceCore.Account.self, from: oldJSON).cardPin)
        // 撤销到底：账户没了，合计回到原来
        for _ in 0..<12 { s.undo() }
        XCTAssertEqual(s.real?.accounts.count, n)
        XCTAssertEqual(s.book.inHand, have)
        // 删一个还有流水的账户：正式账本自己的规矩，不让删
        let busy = s.book.accounts(for: .pay, side: .life).first { $0.kind == .own }!.name
        let before = s.real
        XCTAssertFalse(s.change("删") { $0.accounts.removeAll { $0.name == busy } })
        XCTAssertEqual(s.real, before)
    }

    func testRealLedgerGoals() throws {
        let day = LocalDate(year: 2026, month: 11, day: 18)
        var real = DemoData.make(endingOn: day)
        // 示例里目标满了：先腾一个位置，再做迁移（每个目标各一个账户）
        try real.removeGoal(real.goals.last!.id, author: "测试")
        try real.giveEveryGoalItsOwnAccount(today: day, author: "迁移")
        let s = V3State(snapshotOf: real, today: day, writable: true)
        s.author = "小满"
        XCTAssertTrue(s.book.goalAccountsAreConsistent, "迁移以后：每个目标已存 = 它那个账户的余额")
        let total = s.book.inHand
        let big = s.book.journey
        let realBig = real.goals.first { $0.name == big.name }!
        let from = s.book.accounts(for: .moveOut, side: .life).first { $0.kind == .own && $0.block == .daily && $0.balance > self.eur("100") }!.name
        // 存一笔：正式账本里是一次存钱（两笔，转进目标的账户），不算花销；总数不变
        let month = s.book.month.spentTotal
        XCTAssertTrue(s.change("存") { _ = try $0.deposit(self.eur("40"), from: from) })
        XCTAssertEqual(Plans.goals(s.real!).first { $0.id == realBig.id }?.saved, big.saved + eur("40"))
        XCTAssertEqual(s.book.journey.saved, big.saved + eur("40"))
        XCTAssertEqual(s.real?.changes.last?.kind, .goalDeposit)
        XCTAssertEqual(s.real?.changes.last?.author, "小满")
        XCTAssertEqual(s.book.inHand, total, "存一笔前后总数不变")
        XCTAssertEqual(s.book.month.spentTotal, month, "不算花销")
        XCTAssertTrue(s.book.goalAccountsAreConsistent)
        // 改名字和金额
        XCTAssertTrue(s.change("改") { try $0.editBigGoal(name: big.name + "（新）", total: big.total + self.eur("100")) })
        XCTAssertEqual(s.real?.goals.first { $0.id == realBig.id }?.target, big.total + eur("100"))
        XCTAssertEqual(s.real?.goals.first { $0.id == realBig.id }?.name, big.name + "（新）")
        // 定一个新的小目标，新开存钱罐：正式账本多一个账户、多一个带账户的目标
        let goals = s.real!.goals.count, accounts = s.real!.accounts.count
        XCTAssertTrue(s.change("加") { try $0.addSmallGoal(name: "周末看海", target: self.eur("240")) })
        XCTAssertEqual(s.real?.goals.count, goals + 1); XCTAssertEqual(s.real?.accounts.count, accounts + 1)
        XCTAssertEqual(s.real?.accounts.last?.name, "周末看海 存钱罐")
        XCTAssertEqual(s.real?.goals.last?.savingsAccountID, s.real?.accounts.last?.id)
        XCTAssertTrue(s.real!.goalsWithoutOwnAccount.isEmpty); XCTAssertTrue(s.real!.goalsSharingAnAccount.isEmpty)
        XCTAssertEqual(s.book.inHand, total)
        // 撤销：新目标和它的存钱罐一起退回去
        s.undo(); s.undo()
        XCTAssertEqual(s.real?.goals.count, goals); XCTAssertEqual(s.real?.accounts.count, accounts)
        // 换大目标：正式账本里把那个小目标钉成大目标
        if let small = s.book.smallGoals.first {
            let oldBig = s.book.journey.name
            XCTAssertTrue(s.change("换") { try $0.promoteSmallGoal(small.id) })
            XCTAssertEqual(s.real?.goals.first { $0.pinned }?.name, small.name)
            XCTAssertEqual(s.book.journey.name, small.name)
            XCTAssertTrue(s.book.smallGoals.contains { $0.name == oldBig })
            XCTAssertEqual(s.book.inHand, total)
            s.undo()
            XCTAssertEqual(s.book.journey.name, oldBig)
        }
        // 删大目标，钱放回一个账户：正式账本里是一笔转账 + 删掉目标；它的账户留着；总数不变
        let name = s.book.journey.name, saved = s.book.journey.saved, n = s.real!.goals.count, accs = s.real!.accounts.count
        let jar = s.book.bigGoalHome!.name, dest = s.book.account(from)!.balance
        XCTAssertTrue(s.change("删") { try $0.removeBigGoal(moneyTo: .account(from)) })
        XCTAssertEqual(s.real?.goals.count, n - 1)
        XCTAssertFalse(s.real!.goals.contains { $0.name == name })
        XCTAssertEqual(s.real?.accounts.count, accs, "账户只加不删")
        XCTAssertEqual(s.book.account(from)?.balance, dest + saved)
        XCTAssertEqual(s.book.account(jar)?.balance, .zero)
        XCTAssertEqual(s.book.inHand, total, "钱只是换了地方")
        // 还没接的：目标走完收起来 → 拒绝，账本不动
        let snapshot = s.real
        XCTAssertFalse(s.change("收") { $0.finishedGoals.append(.init(name: "x", total: .zero, date: "", small: true)) })
        XCTAssertTrue(s.toast?.text.contains("还没接上") ?? false)
        XCTAssertEqual(s.real, snapshot)
    }

    func testRealLedgerTransfersDebtsAndSubscriptions() throws {
        let day = LocalDate(year: 2026, month: 11, day: 18)
        let real = DemoData.make(endingOn: day)
        let s = V3State(snapshotOf: real, today: day, writable: true)
        s.author = "小满"
        let total = s.book.inHand, spent = s.book.month.spentTotal
        // 两个自己的账户之间转：正式账本里是一笔账户间转账（两笔流水，不算收支），总数不变
        let two = s.book.transferSources(.life).filter { $0.balance > self.eur("50") }.prefix(2).map(\.name)
        let a0 = s.book.account(two[0])!.balance, a1 = s.book.account(two[1])!.balance
        XCTAssertTrue(s.change("转") { try $0.move(self.eur("25"), from: two[0], to: two[1]) })
        XCTAssertEqual(s.real?.changes.last?.kind, .transfer)
        XCTAssertEqual(s.real?.changes.last?.author, "小满")
        XCTAssertEqual(s.book.account(two[0])?.balance, a0 - eur("25")); XCTAssertEqual(s.book.account(two[1])?.balance, a1 + eur("25"))
        XCTAssertEqual(s.book.inHand, total); XCTAssertEqual(s.book.month.spentTotal, spent, "转账不算花销")
        s.undo()
        XCTAssertEqual(s.book.account(two[0])?.balance, a0)
        // 还信用卡：从自己的账户转给信用卡，欠的变少
        if let card = s.book.accounts.first(where: { $0.isCreditCard && $0.side == .life && $0.balance > self.eur("20") }) {
            XCTAssertTrue(s.change("还") { try $0.repay(debt: card.name, amount: self.eur("20"), from: two[0]) })
            XCTAssertEqual(s.book.account(card.name)?.balance, card.balance - eur("20"))
            XCTAssertEqual(s.book.month.spentTotal, spent, "还信用卡不算花销")
            s.undo()
        }
        // 还借的钱：正式账本里是这笔借款的一次还款
        if let debt = Plans.debts(real, today: day).first(where: { $0.direction == .iOweThem && $0.outstanding > self.eur("10") }) {
            XCTAssertTrue(s.change("还") { try $0.repay(debt: debt.counterparty, amount: self.eur("10"), from: two[0]) })
            XCTAssertEqual(Plans.debts(s.real!, today: day).first { $0.id == debt.id }?.outstanding, debt.outstanding - eur("10"))
            XCTAssertEqual(s.real?.changes.last?.kind, .repay)
            s.undo()
        }
        // 记一笔新的欠款：正式账本多一笔借款
        let debts = s.real!.debts.count
        XCTAssertTrue(s.change("记") { try $0.addDebt(name: "阿杰", amount: self.eur("80"), owedToMe: false, note: "12 月还") })
        XCTAssertEqual(s.real?.debts.count, debts + 1)
        XCTAssertEqual(s.real?.debts.last?.counterparty, "阿杰")
        XCTAssertEqual(s.book.account("阿杰")?.balance, eur("80"))
        s.undo()
        XCTAssertEqual(s.real?.debts.count, debts)
        // 订阅：加一个、标成要退、拿掉
        let subs = s.real!.subscriptions.count
        XCTAssertTrue(s.change("加") { try $0.addSubscription(name: "读书会员", amount: self.eur("5,99"), note: "", forWork: false) })
        XCTAssertEqual(s.real?.subscriptions.count, subs + 1)
        XCTAssertEqual(s.real?.subscriptions.last?.amount, eur("5,99"))
        XCTAssertTrue(s.change("退") { try $0.setSubscription("读书会员", dropped: true) })
        XCTAssertNotNil(s.real?.subscriptions.last?.cancelledOn)
        s.undo(); s.undo()
        XCTAssertEqual(s.real?.subscriptions.count, subs)
        XCTAssertEqual(s.book.inHand, total, "一路折腾下来，手里的钱没变")
    }

    /// 固定开销接正式账本：自己加的能改、能停、能拿掉；从流水里认出来的只能拿掉（记进「不算固定开销」）。
    func testRealLedgerFixedCosts() throws {
        let day = LocalDate(year: 2026, month: 11, day: 18)
        let real = DemoData.make(endingOn: day)
        guard real.businessBook != nil else { throw XCTSkip("示例正式账本没开生意模式") }
        let s = V3State(snapshotOf: real, today: day, writable: true)
        s.author = "小满"
        let acc = s.book.shopHeld[0].name
        let rules = s.real!.recurring.count
        // 加一样：正式账本里多一条每月自动记的规则，新界面的列表里也看得到
        XCTAssertTrue(s.change("加") { try $0.addFixedCost(name: "店面保险", amount: self.eur("35"), day: 12, account: acc) })
        XCTAssertEqual(s.real?.recurring.count, rules + 1)
        XCTAssertEqual(s.book.fixedCosts.first { $0.name == "店面保险" }?.amount, eur("35"))
        func rule() -> Recurring? { s.real?.recurring.first { $0.template.description == "店面保险" } }
        // 改多少、几号
        XCTAssertTrue(s.change("改") { try $0.editFixedCost("店面保险", amount: self.eur("40"), day: 20, account: acc) })
        XCTAssertEqual(rule()?.template.amount, -eur("40")); XCTAssertEqual(rule()?.nextDate, LocalDate(year: 2026, month: 11, day: 20))
        XCTAssertEqual(s.book.fixedCosts.first { $0.name == "店面保险" }?.day, 20)
        // 停一停、接着付
        XCTAssertTrue(s.change("停") { try $0.setFixedCost("店面保险", paused: true) })
        XCTAssertEqual(rule()?.paused, true); XCTAssertEqual(s.book.fixedCosts.first { $0.name == "店面保险" }?.off, true)
        XCTAssertTrue(s.change("接着付") { try $0.setFixedCost("店面保险", paused: false) })
        XCTAssertEqual(rule()?.paused, false)
        // 拿掉，撤销一次就回来
        XCTAssertTrue(s.change("拿掉") { try $0.removeFixedCost("店面保险") })
        XCTAssertNil(rule()); XCTAssertNil(s.book.fixedCosts.first { $0.name == "店面保险" })
        s.undo()
        XCTAssertEqual(rule()?.template.amount, -eur("40"))
        XCTAssertEqual(s.real?.changes.last?.author, "小满")
        // 从流水里认出来的：改不了；拿掉 = 记进「不算固定开销」，以后不再认；能撤销
        guard let guess = s.book.fixedCosts.first(where: { $0.tag == LedgerBridge.guessedTag }) else { return }
        let keep = s.real
        XCTAssertFalse(s.change("改") { try $0.editFixedCost(guess.name, amount: guess.amount + self.eur("1")) })
        XCTAssertTrue(s.real == keep)
        XCTAssertTrue(s.change("不算") { try $0.removeFixedCost(guess.name) })
        XCTAssertEqual(s.real?.profile.notFixed?.count, (keep?.profile.notFixed?.count ?? 0) + 1)
        XCTAssertNil(s.book.fixedCosts.first { $0.name == guess.name })
        s.undo()
        XCTAssertNotNil(s.book.fixedCosts.first { $0.name == guess.name })
    }

    func testRealLedgerShopSide() throws {
        let day = LocalDate(year: 2026, month: 11, day: 18)
        var real = DemoData.make(endingOn: day)
        guard real.businessBook != nil else { throw XCTSkip("示例正式账本没开生意模式") }
        // 把今天店里已经记的收入拿掉，好试「今天还没记」的情况
        let shopBook = real.businessBook!.id
        let todays = real.transactions.filter { $0.bookID == shopBook && $0.date == day && $0.amount > .zero }.map(\.id)
        if !todays.isEmpty { try real.removeTransactions(todays, author: "测试") }
        // 10 号多一笔从银行流水导进来的收入（不是「每天记账」记的）
        let shopAccount = real.transactions.first { $0.bookID == shopBook && $0.amount > .zero }!.accountID
        try real.addTransaction(Transaction(date: LocalDate(year: 2026, month: 11, day: 10), amount: Money(cents: 45_00), description: "转账收款",
                                            accountID: shopAccount, bookID: shopBook, category: "营业收入", source: "晴空银行.csv"), author: "测试")
        let s = V3State(snapshotOf: real, today: day, writable: true)
        s.author = "小满"
        XCTAssertTrue(s.book.showBiz)
        let held = s.book.shopHeld
        XCTAssertFalse(held.isEmpty)
        let acc = held[0].name, bal = held[0].balance, n = s.real!.transactions.count
        // 记今天按渠道收了多少：正式账本里是这天的营业收入（记在生意账本、那个账户上）
        XCTAssertEqual(s.book.shopDays.first { $0.day == 18 }?.state, .missing)
        XCTAssertTrue(s.change("记") { try $0.recordShopDay(18, channels: [.init(acc, self.eur("186"))]) })
        XCTAssertEqual(s.real?.transactions.count, n + 1)
        let tx = s.real!.transactions.last!
        XCTAssertEqual(tx.amount, eur("186")); XCTAssertEqual(tx.bookID, shopBook); XCTAssertEqual(tx.date, day); XCTAssertEqual(tx.category, "营业收入")
        XCTAssertEqual(s.book.account(acc)?.balance, bal + eur("186"))
        XCTAssertEqual(s.book.shopDays.first { $0.day == 18 }?.total, eur("186"))
        XCTAssertEqual(s.real?.changes.last?.author, "小满")
        // 改已经记过的那天：旧的那笔删掉、照新的数再记，笔数不变；撤销一次就回到改之前
        XCTAssertTrue(s.change("改") { try $0.recordShopDay(18, channels: [.init(acc, self.eur("200"))]) })
        XCTAssertEqual(s.real?.transactions.count, n + 1)
        XCTAssertEqual(s.book.shopDays.first { $0.day == 18 }?.total, eur("200"))
        XCTAssertEqual(s.book.account(acc)?.balance, bal + eur("200"))
        XCTAssertEqual(s.book.shopFlow.filter { $0.day == 18 && $0.amount > .zero }.map(\.amount), [eur("200")], "那天只有一行")
        s.undo()
        XCTAssertEqual(s.real?.transactions.count, n + 1)
        XCTAssertEqual(s.book.shopDays.first { $0.day == 18 }?.total, eur("186"))
        XCTAssertEqual(s.book.account(acc)?.balance, bal + eur("186"))
        // 那天要是有别处来的收入（不是「每天记账」记的）：分不清改哪笔，拒绝，账本不动
        let keep = s.real
        XCTAssertFalse(s.change("改") { try $0.recordShopDay(10, channels: [.init(acc, self.eur("1"))]) })
        XCTAssertTrue(s.real == keep)
        // 店里的开销、进货：都是生意账本里的一笔流水
        XCTAssertTrue(s.change("记") { try $0.recordShopExpense(name: "胶带", amount: self.eur("12"), category: "包装耗材", account: acc) })
        XCTAssertEqual(s.real?.transactions.last?.bookID, shopBook); XCTAssertEqual(s.real?.transactions.last?.category, "包装耗材")
        XCTAssertTrue(s.change("进") { try $0.addPurchase(name: "花泥", amount: self.eur("20"), note: "今天", account: acc) })
        XCTAssertEqual(s.real?.transactions.last?.category, "进货")
        XCTAssertEqual(s.book.account(acc)?.balance, bal + eur("154"))
        XCTAssertEqual(s.book.month.spentTotal, LedgerBridge.snapshot(of: real, today: day).month.spentTotal, "店里的开销不算进生活的花销")
        // 从店里拿回家：正式账本的「两边转钱」
        let home = s.book.accounts(for: .receive, side: .life).first!.name
        let homeBal = s.book.account(home)!.balance
        XCTAssertTrue(s.change("转") { try $0.transferBetweenSides(self.eur("100"), toHome: true, shopAccount: acc, homeAccount: home) })
        XCTAssertEqual(s.book.account(home)?.balance, homeBal + eur("100"))
        XCTAssertEqual(s.book.account(acc)?.balance, bal + eur("54"))
        // 把今天标成休息：那天记的收入拿掉，正式账本记下这天休息；开门天数少一天；撤销一次回到原样
        let snapshot = s.real, open = s.book.shopDays.filter { $0.state == .open }.count
        XCTAssertTrue(s.change("休息") { try $0.markShopRest(18) })
        XCTAssertEqual(s.real?.isShopRest(day), true)
        XCTAssertEqual(s.book.shopDays.first { $0.day == 18 }?.state, .rest)
        XCTAssertEqual(s.book.shopDays.filter { $0.state == .open }.count, open - 1)
        XCTAssertEqual(s.real?.transactions.count, (snapshot?.transactions.count ?? 0) - 1)
        // 休息的那天又记了收入：就不算休息了
        XCTAssertTrue(s.change("记") { try $0.recordShopDay(18, channels: [.init(acc, self.eur("90"))]) })
        XCTAssertEqual(s.real?.isShopRest(day), false)
        XCTAssertEqual(s.book.shopDays.first { $0.day == 18 }?.total, eur("90"))
        s.undo(); s.undo()
        XCTAssertEqual(s.real?.isShopRest(day), false)
        XCTAssertEqual(Set(s.real?.transactions ?? []), Set(snapshot?.transactions ?? []), "流水和标休息之前一样")
        // 撤销到底
        for _ in 0..<4 { s.undo() }
        XCTAssertEqual(s.real?.transactions.count, n)
        XCTAssertEqual(s.book.account(acc)?.balance, bal)
    }

    /// 第 8 步：正式账本上，文件交给夏夏是真读真导；照片不演；没接上的设置页直说。
    func testRealLedgerImportThroughXiaAndHonestReplies() async throws {
        let model = LedgerModel.demo()
        model.author = "小满"
        let s = V3State(model: model)
        let n = model.ledger.transactions.count
        // 一份编出来的流水，放在临时文件夹里
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("xiaxia-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("晴空银行 流水.csv")
        try "Fecha;Concepto;Importe\n03/11/2026;Papeleria Nube;-7,35\n04/11/2026;Cafe Brisa;-3,10\n".write(to: url, atomically: true, encoding: .utf8)
        s.handToXia(file: url)
        try await Task.sleep(for: .seconds(0.8))
        guard case .realStatement(let name, let account, let added)? = s.chat.last?.confirm else { return XCTFail("应该回一张真流水的确认卡") }
        XCTAssertEqual(added, 2)
        XCTAssertEqual(model.ledger.transactions.count, n, "确认之前不写入")
        // 换个账户再数一遍，还是不写
        let other = s.statementAccounts.first { $0 != account }!
        XCTAssertNotNil(s.statementReply(name, account: other).confirm)
        XCTAssertEqual(model.ledger.transactions.count, n)
        // 点「导进来」：进的是 app 那本账，写明记账人，整批能撤销
        XCTAssertEqual(s.importStatement(name, account: account)?.fresh, 2)
        XCTAssertEqual(model.ledger.transactions.count, n + 2)
        XCTAssertEqual(model.ledger.changes.last?.author, "小满")
        XCTAssertTrue(s.book.entries.contains { $0.place == "Cafe Brisa" })
        XCTAssertNil(s.importStatement(name, account: account), "同一份再导：全是重复，不写")
        XCTAssertEqual(model.ledger.transactions.count, n + 2)
        s.undo()
        XCTAssertEqual(model.ledger.transactions.count, n)
        // 照片：不出示例小票那张卡，账本不动
        XCTAssertTrue(s.hand(.image(NSImage(size: .init(width: 4, height: 4)), "小票.jpg"), text: ""))
        try await Task.sleep(for: .seconds(0.6))
        XCTAssertNil(s.chat.last?.confirm)
        // 读不成字的文件：直说读不了
        XCTAssertNil(s.statementReply("对账单.pdf", account: account).confirm)
        // 没给文件：不拿示例流水来演
        let chats = s.chat.count
        s.handToXia()
        XCTAssertEqual(s.chat.count, chats + 1); XCTAssertNil(s.chat.last?.confirm)
        XCTAssertEqual(model.ledger.transactions.count, n)
    }

    func testRealLedgerMemoriesAuthorAndUnwiredSettings() throws {
        let model = LedgerModel.demo()
        model.author = "小满"
        let s = V3State(model: model)
        // 记账人是同一个
        s.author = "小晴"
        XCTAssertEqual(model.author, "小晴")
        // 记一条、彻底忘掉
        XCTAssertTrue(s.change("记下了") { try $0.remember(.topic, topic: "停车位", line: "每月 60 €") })
        XCTAssertEqual(model.ledger.changes.last?.author, "小晴")
        let memo = try XCTUnwrap(s.book.memos.first { $0.topic == "停车位" })
        XCTAssertNotNil(model.ledger.memories.first { $0.id == memo.id })
        s.forget(memo: memo.id)
        XCTAssertNil(model.ledger.memories.first { $0.id == memo.id })
        XCTAssertNil(s.book.memos.first { $0.topic == "停车位" })
        // 账本改名
        XCTAssertTrue(s.change("改好了") { try $0.renameBook(.life, to: "我的日子") })
        XCTAssertEqual(model.ledger.books.first { !$0.isBusiness }?.name, "我的日子")
        // 试用版里演的那几个动作（假连接、假删除）在正式账本上不生效，账本不动
        let before = model.ledger
        s.deleteEverything()
        s.connect("Claude 桌面版")
        XCTAssertEqual(model.ledger, before)
        // 五页设置都能开（接的是 app 的账本模型）
        for sub in [V3State.SettingsSub.ai, .business, .money, .sync, .data, .memory] { s.openSettings(sub); XCTAssertEqual(s.settingsSub, sub) }
        // 管哪边：关掉生意那一边，生意的账还在；再打开
        XCTAssertTrue(model.businessOn); XCTAssertTrue(s.showsBiz)
        let shopTx = model.ledger.transactions.count
        XCTAssertTrue(s.setBusiness(on: false))
        XCTAssertFalse(model.businessOn); XCTAssertEqual(model.ledger.transactions.count, shopTx, "生意的账还在")
        XCTAssertEqual(s.side, .life)
        XCTAssertTrue(s.setBusiness(on: true))
        XCTAssertTrue(model.businessOn)
        XCTAssertEqual(model.ledger.changes.last?.author, "小晴")
        // 主币种
        s.setBaseCurrency("USD")
        XCTAssertEqual(model.ledger.baseCurrency, "USD")
        s.setBaseCurrency("EUR")
        // 删掉全部数据（内存里的示例账本，没有文件，所以也没有备份）
        s.wipeEverything()
        XCTAssertTrue(model.ledger.transactions.isEmpty)
        XCTAssertTrue(s.book.entries.isEmpty)
    }

    /// 新用户：空账本自动进引导；走完之前账本一个字不动；走完把填的写进去；有数据的账本不进引导。
    func testEmptyRealLedgerStartsWithOnboardingAndWritesAtTheEnd() throws {
        let model = LedgerModel.empty()
        model.author = "小满"
        let s = V3State(model: model)
        XCTAssertEqual(s.onboardingStep, 0); XCTAssertTrue(s.firstRun)
        let before = model.ledger
        s.nextStep(); s.nextStep()
        s.wish = "三年后不用为钱发愁"
        s.nextStep()
        var list = StartingAccounts(rows: [])
        let card = try list.add(.daily); list.setText(card, "1.200")
        let cash = try list.add(.cash); list.setText(cash, "60")
        s.startingAccounts = list
        s.nextStep()
        XCTAssertEqual(model.ledger, before, "走完之前账本不动")
        s.nextStep()
        XCTAssertNil(s.onboardingStep); XCTAssertFalse(s.firstRun)
        XCTAssertFalse(model.businessOn, "没选生意就不开生意那一边")
        XCTAssertEqual(model.ledger.accounts.map(\.name), ["日常卡", "现金"])
        XCTAssertEqual(s.book.inHand, eur("1260"))
        XCTAssertEqual(s.book.memos.first?.lines, ["三年后不用为钱发愁"])
        XCTAssertTrue(model.ledger.changes.allSatisfy { $0.author == "小满" })
        // 一步撤回
        s.undo()
        XCTAssertTrue(model.ledger.accounts.isEmpty)
        // 全都跳过：什么都不写，照样能进去
        let m2 = LedgerModel.empty()
        let s2 = V3State(model: m2)
        let empty = m2.ledger
        for _ in 0..<5 { s2.nextStep() }
        XCTAssertNil(s2.onboardingStep); XCTAssertEqual(m2.ledger, empty)
        // 引导里选了「两边都管」：走完以后生意那一边是开着的
        let m3 = LedgerModel.empty()
        let s3 = V3State(model: m3)
        s3.nextStep(); s3.mode = .both
        for _ in 0..<4 { s3.nextStep() }
        XCTAssertTrue(m3.businessOn); XCTAssertTrue(s3.showsBiz)
        // 有数据的账本不进引导
        XCTAssertNil(V3State(model: LedgerModel.demo()).onboardingStep)
    }

    func testNewLookSharesTheAppsLedgerModel() throws {
        // app 的账本模型（内存里的示例账本，不碰任何文件）；新界面接在它上面
        let model = LedgerModel.demo()
        model.author = "小满"
        let s = V3State(model: model)
        XCTAssertFalse(s.readOnly); XCTAssertEqual(s.author, "小满")
        let n = model.ledger.transactions.count
        let acc = s.book.accounts(for: .pay, side: .life).first { $0.kind == .own }!.name
        let bal = s.book.account(acc)!.balance
        // 在新界面记一笔：写进的是 app 那本账（旧界面马上也看得到），由模型负责存
        XCTAssertTrue(s.change("记好了") { try $0.record(name: "餐饮", emoji: "🥗", amount: self.eur("12,50"), account: acc, place: "La Tasca") })
        XCTAssertEqual(model.ledger.transactions.count, n + 1)
        XCTAssertEqual(model.ledger.changes.last?.author, "小满")
        XCTAssertEqual(s.book.account(acc)?.balance, bal - eur("12,50"))
        // 在别处改了账本（旧界面、AI、命令行都走这个模型）：新界面跟着变
        let id = model.ledger.accounts.first { $0.name == acc }!.id
        try model.edit(quiet: true) { l in
            try l.addTransaction(Transaction(date: .today, amount: Money(cents: -500), description: "别处记的", accountID: id, category: "超市"), author: "AI")
        }
        XCTAssertEqual(s.book.account(acc)?.balance, bal - eur("12,50"), "还没刷新")
        s.refreshFromModel()
        XCTAssertEqual(s.book.account(acc)?.balance, bal - eur("17,50"))
        XCTAssertTrue(s.book.entries.contains { $0.place == "别处记的" })
        // 撤销新界面记的那一笔：模型里也没了
        s.undo()
        XCTAssertFalse(model.ledger.transactions.contains { $0.description == "La Tasca" && $0.amount == Money(cents: -12_50) })
        // 做不了的改动：模型一个字不动
        let before = model.ledger
        XCTAssertFalse(s.change("改") { try $0.setMonthlyPlan(self.eur("123")) })
        XCTAssertEqual(model.ledger, before)
        // 默认还是旧界面
        XCTAssertFalse(V3Launch.newLook)
    }

    func testNoSecretStashAndTwoBlocks() {
        let s = V3State()
        XCTAssertFalse(s.book.accounts.contains { $0.kind == .secret }, "示例里没有私房钱了")
        XCTAssertFalse(s.book.accounts.contains { $0.name.contains("私房") || $0.note.contains("应急") || $0.label.contains("应急") })
        // 两块：存在目标里 + 日常能用 = 一共有
        XCTAssertEqual(s.book.sum(.goal) + (s.book.totals.have - s.book.sum(.goal)), s.book.totals.have)
        XCTAssertEqual(s.book.usualMonthlySpend, eur("1822"), "固定要付 892 + 平时每天 31 × 30")
        XCTAssertEqual(s.book.handRunway.monthsText, "2,2", "手里 3.981,61（不含目标里的 519）÷ 1.822")
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
        XCTAssertEqual(s.book.bigGoalHome?.balance, eur("539"), "大目标的钱在它自己的存钱罐里")
        XCTAssertEqual(s.book.sum(.goal), eur("734"), "四个存钱罐一共 = 大目标 539 + 小目标 195")
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
        XCTAssertEqual(s.book.journey.saved, eur("539"), "应急钱去掉以后不再对半分：存多少进多少")
        XCTAssertEqual(s.book.sum(.emergency), eur("2400"))
    }

    func testAddAccountChangesTotals() {
        let s = V3State()
        s.addAccount(emoji: "🤝", name: "跟朋友借的", note: "欠的钱", balance: eur("300"), kind: .debt)
        XCTAssertEqual(s.book.totals.owe, eur("2140"))
        XCTAssertEqual(s.book.totals.net, eur("2675,61"))
        s.addAccount(emoji: "🧑", name: "借给小王", note: "别人欠我", balance: eur("50"), kind: .lent)
        XCTAssertEqual(s.book.totals.have, eur("4865,61"), "借出去的也是自己的钱：再借出 50，一共有多 50")
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
        XCTAssertTrue(s.change("加好了") { try $0.addFixedCost(name: "店面保险", amount: self.eur("35"), day: 12, account: "店里现金") })
        XCTAssertEqual(s.book.fixedTotal, eur("1825"))
        let net = s.book.totals.net
        XCTAssertTrue(s.change("转好了") { try $0.transferBetweenSides(self.eur("300"), toHome: true, shopAccount: "小店账户", homeAccount: "日常卡") })
        XCTAssertEqual(s.book.totals.net, net + eur("300"), "店里拿回家 300：生活这边多 300")
        XCTAssertEqual(s.book.account("小店账户")?.balance, shop + eur("100") - eur("300"), "店里少 300")
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
        XCTAssertEqual(V3State.Page.biz.map(\.rawValue), ["bizHome", "sales", "shopFlow", "shopWealth", "fixed", "stock", "bizDebts", "payback", "checkup"])
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
        XCTAssertFalse(s.change("设好了") { try $0.setEmergency(accounts: ["换新电脑 存钱罐"], months: 3) })
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
        XCTAssertEqual(s.book.transferShortcuts.map(\.title), ["存进储蓄", "还信用卡", "取现金", "放进换新电脑 存钱罐"])
        XCTAssertTrue(s.change("转好了") { try $0.transfer(self.eur("100"), from: "日常卡", to: "储蓄") })
        XCTAssertEqual(s.book.account("储蓄")?.balance, eur("2500"))
        XCTAssertEqual(s.book.totals.net, net, "自己账户之间转，净剩不变")
        XCTAssertTrue(s.change("转好了") { try $0.transfer(self.eur("640"), from: "日常卡", to: "信用卡") }, "转给信用卡就是还款")
        XCTAssertEqual(s.book.account("信用卡")?.balance, .zero)
        let saved = s.book.journey.saved
        XCTAssertTrue(s.change("转好了") { try $0.transfer(self.eur("20"), from: "现金", to: "换新电脑 存钱罐") }, "转进目标的账户就是存一笔")
        XCTAssertEqual(s.book.journey.saved, saved + eur("20"))
        XCTAssertFalse(s.change("转好了") { try $0.transfer(self.eur("20"), from: "现金", to: "现金") }, "从和到不能是同一个")
        XCTAssertFalse(s.change("转好了") { try $0.transfer(self.eur("20"), from: "换新电脑 存钱罐", to: "现金") }, "目标罐里的钱不能这样转出来")
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
        XCTAssertNil(s.book.smallGoals.first { $0.id == shoes.id }, "存够了：从小目标里拿走")
        XCTAssertEqual(s.book.finishedGoals.first?.name, "新跑鞋", "收进走完的路")
        XCTAssertEqual(s.book.finishedGoals.first?.total, eur("95"))
        XCTAssertEqual(s.book.sum(.goal), s.book.goalMoney, "目标罐 = 还在走的目标已存之和")
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
        XCTAssertEqual(s.book.totals.have, eur("4815,61"), "生活家底的「一共有」不含店里的钱")
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
