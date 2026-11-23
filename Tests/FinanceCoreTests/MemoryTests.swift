import XCTest
@testable import FinanceCore

// 夏夏的记忆、每月整理、每月固定进出。测试只用编造的内容。
final class MemoryTests: XCTestCase {
    func d(_ y: Int, _ m: Int, _ day: Int) -> LocalDate { LocalDate(year: y, month: m, day: day) }
    let demoEnd = LocalDate(year: 2026, month: 11, day: 20)
    var demoNow: Date { Calendar(identifier: .gregorian).date(from: DateComponents(year: 2026, month: 11, day: 20, hour: 12))! }

    // MARK: 记

    func testSameTopicGetsOneEntry() throws {
        var l = Ledger.starter
        let first = try l.remember(kind: .topic, title: "工资", text: "明年 1 月起涨一点。", author: "Claude")
        XCTAssertTrue(first.summary.hasPrefix("记忆："))
        XCTAssertEqual(first.author, "Claude")
        try l.remember(kind: .topic, title: " 工资 ", text: "6 月和 12 月多发一份。", source: .confirmed, author: "Codex")
        XCTAssertEqual(l.memories.count, 1, "同名话题加在下面，不另开一条")
        XCTAssertEqual(l.memories[0].notes.map(\.source), [.said, .confirmed])
        XCTAssertEqual(l.memoryLineCount, 2)

        XCTAssertThrowsError(try l.remember(kind: .topic, title: "工资", text: "6 月和 12 月多发一份。", author: "Claude")) {
            XCTAssertEqual($0 as? MemoryError, .duplicate("工资"))
        }
        // 相近的话题先提示，说了「确实是另一件事」才新开。
        XCTAssertThrowsError(try l.remember(kind: .topic, title: "我的工资", text: "换个名字再记一遍。", author: "Claude")) { e in
            guard case .similarExists(let list)? = e as? MemoryError else { return XCTFail("\(e)") }
            XCTAssertTrue(list[0].contains("「工资」"))
        }
        try l.remember(kind: .topic, title: "我的工资", text: "换个名字再记一遍。", allowNew: true, author: "Claude")
        XCTAssertEqual(l.memories.count, 2)
        // 指定加到哪条下面。
        try l.remember(kind: .topic, title: "", text: "发薪日是 27 号。", into: l.memories[0].id, author: "你")
        XCTAssertEqual(l.memories[0].notes.count, 3)
    }

    func testRefusesEmptyLongSecretAndBadLinks() {
        var l = Ledger.starter
        XCTAssertThrowsError(try l.remember(kind: .topic, title: " ", text: "x", author: "AI")) { XCTAssertEqual($0 as? MemoryError, .emptyTitle) }
        XCTAssertThrowsError(try l.remember(kind: .topic, title: "x", text: "  ", author: "AI")) { XCTAssertEqual($0 as? MemoryError, .emptyText) }
        XCTAssertThrowsError(try l.remember(kind: .topic, title: "话题", text: String(repeating: "长", count: 301), author: "AI")) {
            XCTAssertEqual($0 as? MemoryError, .tooLong("这一行", 300))
        }
        XCTAssertThrowsError(try l.remember(kind: .topic, title: "银行卡", text: "卡号 4111 1111 1111 1111", author: "AI")) {
            XCTAssertEqual($0 as? MemoryError, .looksSecret)
        }
        XCTAssertThrowsError(try l.remember(kind: .topic, title: "话题", text: "x", links: ["account:nosuch"], author: "AI")) {
            XCTAssertEqual($0 as? MemoryError, .badLink("account:nosuch"))
        }
        XCTAssertThrowsError(try l.remember(kind: .topic, title: "话题", text: "x", links: ["planet:火星"], author: "AI"))
        XCTAssertTrue(l.memories.isEmpty)
        XCTAssertTrue(l.changes.isEmpty, "没记成的不留改动记录")
    }

    func testLooksSecret() {
        XCTAssertTrue(MemorySearch.looksSecret("卡号 4111 1111 1111 1111"))
        XCTAssertTrue(MemorySearch.looksSecret("ES00 1234 5678 9012 3456 7890"))
        XCTAssertTrue(MemorySearch.looksSecret("网银密码 123456"))
        XCTAssertTrue(MemorySearch.looksSecret("PIN: 4821"))
        XCTAssertFalse(MemorySearch.looksSecret("明年 1 月起涨到 1.500 €"))
        XCTAssertFalse(MemorySearch.looksSecret("2026-01-01 到 2026-12-31 之间的房租 780 €"))
        XCTAssertFalse(MemorySearch.looksSecret("2026-01-01 - 2026-12-31"))
        XCTAssertFalse(MemorySearch.looksSecret("shopping 2026"))
        XCTAssertFalse(MemorySearch.looksSecret("密码这种东西别记"))
    }

    func testLimitsKeepMemorySmall() throws {
        var l = Ledger.starter
        // 一个话题最多 8 行。
        for i in 1...Memory.maxLines { try l.remember(kind: .rule, title: "甲", text: "第 \(i) 条", author: "你") }
        XCTAssertThrowsError(try l.remember(kind: .rule, title: "甲", text: "第 9 条", author: "你")) {
            XCTAssertEqual($0 as? MemoryError, .tooManyLines("甲"))
        }
        // 规矩一共最多 20 行。
        for i in 1...8 { try l.remember(kind: .rule, title: "乙", text: "第 \(i) 条", allowNew: true, author: "你") }
        for i in 1...4 { try l.remember(kind: .rule, title: "丙", text: "第 \(i) 条", allowNew: true, author: "你") }
        XCTAssertEqual(l.ruleLineCount, Memory.maxRuleLines)
        XCTAssertThrowsError(try l.remember(kind: .rule, title: "丙", text: "第 5 条", author: "你")) { XCTAssertEqual($0 as? MemoryError, .tooManyRules) }
        XCTAssertThrowsError(try l.remember(kind: .rule, title: "丁", text: "新的", allowNew: true, author: "你")) { XCTAssertEqual($0 as? MemoryError, .tooManyRules) }
        // 记得的事不占规矩的名额，但也挪不进去。
        try l.remember(kind: .topic, title: "房租", text: "合同到明年 8 月。", author: "你")
        let rent = try XCTUnwrap(l.findMemory("房租"))
        XCTAssertThrowsError(try l.editMemory(rent.id, kind: .rule, author: "你")) { XCTAssertEqual($0 as? MemoryError, .tooManyRules) }
    }

    /// 时间要记具体的：「明年 3 月」过一年再看就不知道是哪年了。
    func testRelativeTimeBecomesConcrete() throws {
        let day = d(2026, 11, 23)   // 周一
        XCTAssertEqual(MemoryDates.absolute("明年 3 月退健身房", on: day), "2027 年 3 月退健身房")
        XCTAssertEqual(MemoryDates.absolute("打算明年3月退掉", on: day), "打算 2027 年 3月退掉")
        XCTAssertEqual(MemoryDates.absolute("下个月 5 号交押金", on: day), "2026 年 12 月 5 号交押金")
        XCTAssertEqual(MemoryDates.absolute("他说明天还", on: day), "他说 2026 年 11 月 24 日还")
        XCTAssertEqual(MemoryDates.absolute("下周三交报表，去年没交", on: day), "2026 年 12 月 2 日（周三）交报表，2025 年没交")
        XCTAssertEqual(MemoryDates.absolute("这周先不记", on: day), "2026 年 11 月 23 日那一周先不记")
        XCTAssertEqual(MemoryDates.absolute("下个月开始存钱", on: d(2026, 12, 15)), "2027 年 1 月开始存钱", "12 月说下个月要跨年")
        // 不是在说哪一天的，不动。
        for same in ["以后天天记账", "以前天天喝咖啡", "每月 27 号发工资", "每年年底多发一份", "加上周末打车的钱", "基本月薪不变",
                     "2027 年 3 月退健身房"] {
            XCTAssertEqual(MemoryDates.absolute(same, on: day), same)
        }

        var l = Ledger.starter
        try l.remember(kind: .topic, title: "健身房", text: "明年 3 月退健身房", quote: "明年 3 月我要把健身房退了", date: day, author: "Claude")
        XCTAssertEqual(l.memories[0].notes[0].text, "2027 年 3 月退健身房")
        XCTAssertEqual(l.memories[0].notes[0].quote, "明年 3 月我要把健身房退了", "原话照留")
        let m = l.memories[0]
        try l.updateMemoryNote(m.id, noteID: m.notes[0].id, text: "改到后年再退", author: "你")
        XCTAssertEqual(l.memories[0].notes[0].text, "改到 \(LocalDate.today.year + 2) 年再退")
    }

    // MARK: 找

    func testSearchWithoutVectors() throws {
        var l = Ledger.starter
        try l.remember(kind: .rule, title: "转给妈妈的钱", text: "转给妈妈的钱不算支出，算家里往来。", author: "Claude")
        try l.remember(kind: .topic, title: "工资", text: "明年 1 月起涨一点。", links: ["category:工资"], author: "Claude")
        try l.remember(kind: .lesson, title: "导入对账单", text: "还信用卡是账户互转，别记成支出。", author: "Claude")
        XCTAssertEqual(l.searchMemories("妈妈").first?.memory.title, "转给妈妈的钱")
        XCTAssertEqual(l.searchMemories("我工资多少").first?.memory.title, "工资")
        XCTAssertEqual(l.searchMemories("信用卡").first?.memory.title, "导入对账单")
        XCTAssertTrue(l.searchMemories("健身房").isEmpty)
        XCTAssertEqual(l.searchMemories("支出", kind: .lesson).map(\.memory.title), ["导入对账单"])
        XCTAssertEqual(l.memories(linkedTo: "category:工资").map(\.title), ["工资"])
        XCTAssertEqual(l.memories(kind: .rule).map(\.title), ["转给妈妈的钱"])

        let salary = try XCTUnwrap(l.findMemory("工资"))
        XCTAssertEqual(l.findMemory(salary.shortID)?.id, salary.id)
        XCTAssertEqual(l.findMemory(salary.id.uuidString)?.id, salary.id)
        XCTAssertNil(l.findMemory("没有这条"))
        XCTAssertEqual(l.findNote(nil, in: salary)?.id, salary.notes[0].id, "只有一行时不用说哪一行")
        XCTAssertEqual(l.findNote(String(salary.notes[0].id.uuidString.prefix(6)).lowercased(), in: salary)?.id, salary.notes[0].id)
        XCTAssertTrue(salary.described().contains("【记得的事】工资"))
        XCTAssertTrue(salary.described().contains("你说的"))
    }

    // MARK: 改、删、撤销

    func testEditMoveRemoveAndUndo() throws {
        var l = Ledger.starter
        try l.remember(kind: .topic, title: "收益", text: "我说收益是指店里赚的。", author: "Claude")
        let id = l.memories[0].id
        let noteID = l.memories[0].notes[0].id

        let moved = try l.editMemory(id, kind: .rule, pinned: true, author: "你")
        XCTAssertEqual(l.memories[0].kind, .rule)
        XCTAssertTrue(l.memories[0].pinned)
        _ = try l.undo(changeID: moved.id, author: "你")
        XCTAssertEqual(l.memories[0].kind, .topic)
        XCTAssertFalse(l.memories[0].pinned)
        XCTAssertThrowsError(try l.editMemory(id, kind: .topic, author: "你")) { XCTAssertEqual($0 as? MemoryError, .nothingToChange) }

        try l.updateMemoryNote(id, noteID: noteID, text: "我说收益是指店里赚的，不算工资。", source: .corrected,
                               story: .some("问收益时答成了工资加店里收入"), author: "Claude")
        XCTAssertEqual(l.memories[0].notes[0].editedBy, "Claude")
        XCTAssertEqual(l.memories[0].notes[0].source, .corrected)
        XCTAssertEqual(l.memories[0].notes[0].story, "问收益时答成了工资加店里收入")
        XCTAssertThrowsError(try l.updateMemoryNote(id, noteID: noteID, text: "我说收益是指店里赚的，不算工资。", author: "Claude")) {
            XCTAssertEqual($0 as? MemoryError, .nothingToChange)
        }
        try l.updateMemoryNote(id, noteID: noteID, story: .some(nil), author: "你")
        XCTAssertNil(l.memories[0].notes[0].story, "填空就是清掉")

        let removed = try l.removeMemory(id, author: "你")
        XCTAssertTrue(l.memories.isEmpty)
        XCTAssertTrue(removed.canUndo)
        _ = try l.undo(changeID: removed.id, author: "你")
        XCTAssertEqual(l.memories.map(\.title), ["收益"])

        let added = try l.remember(kind: .topic, title: "房租", text: "合同到明年 8 月。", author: "Claude")
        _ = try l.undo(changeID: added.id, author: "你")
        XCTAssertNil(l.findMemory("房租"))

        // 只删一行；最后一行删了，整条就没了。
        try l.remember(kind: .topic, title: "收益", text: "按月看。", author: "Claude")
        let second = l.memories[0].notes[1].id
        try l.removeMemory(id, noteID: second, author: "你")
        XCTAssertEqual(l.memories[0].notes.count, 1)
        try l.removeMemory(id, noteID: noteID, author: "你")
        XCTAssertTrue(l.memories.isEmpty)
        XCTAssertTrue(l.changes.allSatisfy { !$0.author.isEmpty })
    }

    /// 「彻底忘掉」：账本文件里哪儿都找不到这条的字，改动记录也不能把它撤销回来。
    func testForgetLeavesNoTrace() throws {
        var l = Ledger.starter
        try l.remember(kind: .topic, title: "私事", text: "借给表哥两千块，别告诉家里。", quote: "这事别跟别人说", author: "Claude")
        let id = l.memories[0].id
        try l.updateMemoryNote(id, noteID: l.memories[0].notes[0].id, text: "借给表哥两千块。", author: "Claude")
        try l.remember(kind: .topic, title: "工资", text: "发薪日是 27 号。", author: "Claude")
        let removed = try l.removeMemory(id, author: "你")
        _ = try l.undo(changeID: removed.id, author: "你")
        XCTAssertNotNil(l.findMemory("私事"))

        let forgot = try l.forgetMemory(id, author: "你")
        XCTAssertFalse(forgot.canUndo)
        let text = String(decoding: try JSONEncoder().encode(l), as: UTF8.self)
        for word in ["私事", "表哥", "这事别跟别人说"] { XCTAssertFalse(text.contains(word), "账本里还留着「\(word)」") }
        XCTAssertTrue(text.contains("发薪日是 27 号"), "别的记忆不受影响")
        XCTAssertEqual(l.memories.map(\.title), ["工资"])
        // 以前那几条改动现在没东西可放回去了。
        for c in l.changes where c.summary.contains("已经忘掉") { XCTAssertFalse(c.canUndo, c.summary) }
        XCTAssertEqual(l.changes.filter { $0.summary.contains("已经忘掉") }.count, 4)
    }

    func testForgetOneLine() throws {
        var l = Ledger.starter
        try l.remember(kind: .topic, title: "工资", text: "每年 1 月调一次。", author: "Claude")
        try l.remember(kind: .topic, title: "工资", text: "老板私下说的，先别声张。", author: "Claude")
        try l.remember(kind: .topic, title: "工资", text: "发薪日是 27 号。", author: "Claude")
        let m = l.memories[0]
        try l.forgetMemory(m.id, noteID: m.notes[1].id, author: "你")
        XCTAssertEqual(l.memories[0].notes.map(\.text), ["每年 1 月调一次。", "发薪日是 27 号。"])
        let text = String(decoding: try JSONEncoder().encode(l), as: UTF8.self)
        XCTAssertFalse(text.contains("先别声张"))
        // 之前的改动撤销回去，也不会把那一行带回来。
        let third = try XCTUnwrap(l.changes.last { $0.summary.contains("又记了一行") && $0.canUndo })
        _ = try l.undo(changeID: third.id, author: "你")
        XCTAssertFalse(l.memories[0].notes.contains { $0.text.contains("先别声张") })
    }

    // MARK: 每月整理

    func testMonthlyTidy() throws {
        var l = Ledger.starter
        l.accounts = [Account(id: "old", name: "旧卡", kind: .bank)]
        let now = Date()
        let longAgo = now.addingTimeInterval(-200 * 86_400)
        let past = d(2020, 1, 31), future = d(2099, 1, 31)

        try l.remember(kind: .rule, title: "规矩", text: "咖啡记在餐饮。", reviewOn: past, author: "你")
        try l.remember(kind: .topic, title: "阿杰借的钱", text: "月底前还清。", reviewOn: past, author: "你")
        try l.remember(kind: .topic, title: "阿杰借的钱", text: "一共借了三百。", reviewOn: future, author: "你")
        try l.remember(kind: .topic, title: "海边", text: "夏天想去海边玩。", author: "你")
        try l.remember(kind: .topic, title: "旧卡", text: "这张卡只用来付房租。", links: ["account:old"], author: "你")
        try l.remember(kind: .topic, title: "要紧事", text: "很久以前记的，但标了重要。", author: "你")
        try l.remember(kind: .lesson, title: "对账", text: "第 1 条", author: "Claude")
        for i in 2...(Memory.maxLines - 1) { try l.remember(kind: .lesson, title: "对账", text: "第 \(i) 条", author: "Claude") }
        try l.remember(kind: .topic, title: "房租", text: "合同到明年 8 月。", author: "你")

        func age(_ title: String) throws {
            let i = try XCTUnwrap(l.memories.firstIndex { $0.title == title })
            l.memories[i].createdAt = longAgo
            l.memories[i].updatedAt = longAgo
        }
        try age("海边")
        try age("要紧事")
        try age("规矩")
        try l.editMemory(try XCTUnwrap(l.findMemory("要紧事")).id, pinned: true, author: "你")
        try age("要紧事")
        l.accounts = []

        let list = l.memoryTidyList(now: now)
        let byTitle = Dictionary(uniqueKeysWithValues: list.map { ($0.title, $0) })
        XCTAssertEqual(Set(byTitle.keys), ["阿杰借的钱", "海边", "旧卡", "对账"], "规矩、标了重要的、还新的不列")
        XCTAssertEqual(byTitle["阿杰借的钱"]?.reason, .expired)
        XCTAssertEqual(byTitle["阿杰借的钱"]?.text, "月底前还清。")
        XCTAssertNotNil(byTitle["阿杰借的钱"]?.noteID, "两行里只有一行到期，只清那一行")
        XCTAssertEqual(byTitle["海边"]?.reason, .stale)
        XCTAssertEqual(byTitle["旧卡"]?.reason, .orphan)
        XCTAssertEqual(byTitle["对账"]?.reason, .crowded)
        XCTAssertEqual(byTitle["对账"]?.removable, false)
        XCTAssertTrue(l.memoryTidyDue(now: now), "最早那条记了一个多月，又有东西可清")

        // 「留着」：这条不再列出来。
        var kept = l
        try kept.keepMemory(try XCTUnwrap(kept.findMemory("海边")).id, author: "你", now: now)
        try kept.keepMemory(try XCTUnwrap(kept.findMemory("阿杰借的钱")).id, author: "你", now: now)
        XCTAssertEqual(Set(kept.memoryTidyList(now: now).map(\.title)), ["旧卡", "对账"])
        // AI 读出来用过的，也不算「没用上」。
        var used = l
        let sea = try XCTUnwrap(used.findMemory("海边")).id
        XCTAssertTrue(used.touchMemories([sea], now: now))
        XCTAssertFalse(used.touchMemories([sea], now: now.addingTimeInterval(3_600)), "一天内不重复记")
        XCTAssertFalse(used.memoryTidyList(now: now).contains { $0.title == "海边" })
        XCTAssertEqual(used.changes.count, l.changes.count, "读一下不进改动记录")

        // 清掉：一条改动，能一次撤销。
        let before = l
        let change = try l.tidyMemories(remove: list, author: "你", now: now)
        XCTAssertEqual(change.summary, "记忆：整理了一次，清掉 3 行")
        XCTAssertNil(l.findMemory("海边"))
        XCTAssertNil(l.findMemory("旧卡"))
        XCTAssertEqual(l.findMemory("阿杰借的钱")?.notes.map(\.text), ["一共借了三百。"])
        XCTAssertEqual(l.findMemory("对账")?.notes.count, Memory.maxLines - 1, "行数太多的不直接清")
        XCTAssertNotNil(l.findMemory("规矩"))
        XCTAssertEqual(l.profile.memoryTidiedAt, now)
        XCTAssertFalse(l.memoryTidyDue(now: now.addingTimeInterval(86_400)), "刚整理过，一个月内不再提醒")
        _ = try l.undo(changeID: change.id, author: "你")
        XCTAssertEqual(l.memories.map(\.id).sorted { $0.uuidString < $1.uuidString }, before.memories.map(\.id).sorted { $0.uuidString < $1.uuidString })
        XCTAssertEqual(l.findMemory("阿杰借的钱")?.notes.count, 2)
        XCTAssertNil(l.profile.memoryTidiedAt)
    }

    // MARK: 存

    func testReadsOldAndFutureFiles() throws {
        let json = #"{"id":"6F1D2C3B-0000-4000-8000-000000000001","kind":"fromTheFuture","title":"新种类","notes":[{"id":"6F1D2C3B-0000-4000-8000-000000000002","text":"x","source":"telepathy","date":"2026-11-20","author":"AI"}]}"#
        let m = try JSONDecoder().decode(Memory.self, from: Data(json.utf8))
        XCTAssertEqual(m.kind, .topic, "不认识的种类当成「记得的事」")
        XCTAssertEqual(m.notes[0].source, .said)
        XCTAssertFalse(m.pinned)
        // 旧账本文件没有记忆这一栏。
        var old = Ledger.starter
        try old.remember(kind: .topic, title: "工资", text: "明年涨一点。", author: "Claude")
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: try JSONEncoder().encode(old)) as? [String: Any])
        XCTAssertNotNil(object.removeValue(forKey: "memories"))
        let decoded = try JSONDecoder().decode(Ledger.self, from: try JSONSerialization.data(withJSONObject: object))
        XCTAssertTrue(decoded.memories.isEmpty)
    }

    // MARK: 示例账本、说明书、固定进出

    func testDemoLedgerHasMemories() throws {
        let l = DemoData.make(endingOn: demoEnd)
        XCTAssertEqual(Set(l.memories.map(\.kind)), Set(Memory.Kind.allCases))
        XCTAssertEqual(l.findMemory("工资")?.notes.count, 2)
        XCTAssertTrue(l.memories.contains { $0.pinned })
        XCTAssertTrue(l.memories.flatMap(\.notes).contains { $0.quote != nil && $0.story != nil })
        XCTAssertGreaterThanOrEqual(Set(l.memories.flatMap(\.notes).map(\.author)).count, 3)
        XCTAssertTrue(l.memories.allSatisfy { $0.updatedAt <= demoNow && $0.createdAt <= $0.updatedAt })

        let tidy = l.memoryTidyList(today: demoEnd, now: demoNow)
        XCTAssertEqual(Dictionary(uniqueKeysWithValues: tidy.map { ($0.title, $0.reason) }),
                       ["阿杰借的钱": .expired, "FitPlan 健身 App": .orphan, "夏天去海边": .stale])
        XCTAssertTrue(l.memoryTidyDue(today: demoEnd, now: demoNow))

        var brief = MemoryBrief(ledger: l)
        // 「该整理了」那几行跟真实的今天有关，这里不看。
        brief.tidy = nil
        XCTAssertEqual(brief.rules.count, 3)
        XCTAssertTrue(brief.rules.contains { $0.hasPrefix("收益：") })
        XCTAssertEqual(Set(brief.index.map(\.title)), ["工资", "房租", "阿杰借的钱", "FitPlan 健身 App", "夏天去海边", "导入对账单", "对账"])
        XCTAssertFalse(brief.howTo.isEmpty)
        let prompt = try XCTUnwrap(brief.promptText)
        XCTAssertTrue(prompt.contains("- 收益：我说「收益」是指小店赚的钱"))
        XCTAssertTrue(prompt.contains("「导入对账单」（做事经验）"))
        XCTAssertFalse(prompt.contains("到期可能要涨"), "记得的事只给标题，正文要用的时候再读")
        XCTAssertNil(MemoryBrief(ledger: .starter).promptText)
    }

    func testContextCarriesMemoryAndToolGuide() {
        let l = DemoData.make()
        let c = LedgerContext(ledger: l)
        XCTAssertEqual(c.memory.rules.count, 3)
        XCTAssertFalse(c.memory.index.isEmpty)
        XCTAssertTrue(c.toolGuide.contains { $0.contains("summary") })
        XCTAssertTrue(c.regulars.contains { $0.hasPrefix("工资：") }, "\(c.regulars)")
        XCTAssertTrue(LedgerContext(ledger: .starter).regulars.isEmpty)
    }

    func testRegularsFindSalaryAndRent() throws {
        let l = DemoData.make(endingOn: demoEnd)
        let list = Regulars.detect(l, today: demoEnd, hidden: l.privateAccountIDs)
        let salary = try XCTUnwrap(list.first { $0.id == "+工资" }, "\(list.map(\.id))")
        XCTAssertTrue(salary.income)
        XCTAssertEqual(salary.typical, Money(cents: 138_000))
        XCTAssertEqual(salary.day, 27)
        XCTAssertEqual(salary.months, 12)
        XCTAssertEqual(salary.extraMonths, [6, 12], "年中、年终双薪另起了名字，也要算进来")
        XCTAssertEqual(salary.category, "工资")
        XCTAssertEqual(salary.line(currency: "EUR"), "工资：每月 27 号前后进，约 1.380,00 €（最近一年每个月都有；6、12 月多一份）")
        let rent = try XCTUnwrap(list.first { $0.id == "-房租" })
        XCTAssertEqual(rent.typical, Money(cents: 78_000))
        XCTAssertEqual(rent.day, 1)
        XCTAssertEqual(list.first?.income, true, "收入排前面")
        XCTAssertTrue(Regulars.lines(l, today: demoEnd).count <= 12)
    }

    func testRegularsDropStoppedOnes() {
        var l = Ledger.starter
        l.accounts = [Account(id: "bank", name: "卡", kind: .bank)]
        for m in 1...6 {
            l.transactions.append(Transaction(date: d(2026, m, 5), amount: Money(cents: -3_490), description: "健身房月费", accountID: "bank",
                                              bookID: "personal", category: "运动"))
        }
        // 一个月去好几次的超市、金额忽高忽低的进账：不算固定。
        let erratic: [Int64] = [1_000, 9_000, 2_500, 30_000, 4_000, 15_000]
        for m in 1...6 {
            for day in [3, 10, 17, 24] {
                l.transactions.append(Transaction(date: d(2026, m, day), amount: Money(cents: -2_500), description: "绿篮超市", accountID: "bank",
                                                  bookID: "personal", category: "超市"))
            }
            l.transactions.append(Transaction(date: d(2026, m, 12), amount: Money(cents: erratic[m - 1]), description: "朋友转账", accountID: "bank",
                                              bookID: "personal", category: "其它"))
        }
        let june = Regulars.detect(l, today: d(2026, 6, 20))
        XCTAssertEqual(june.map(\.id), ["-健身房月费"])
        XCTAssertEqual(june.first?.months, 6)
        XCTAssertEqual(june.first?.line(currency: "EUR"), "健身房月费：每月 5 号前后扣，约 34,90 €（最近一年里有 6 个月）")
        XCTAssertTrue(Regulars.detect(l, today: d(2026, 11, 20)).isEmpty, "停了半年的不算")
        // 才两个月的看不出来。
        l.transactions.removeAll { $0.date.month > 2 }
        XCTAssertTrue(Regulars.detect(l, today: d(2026, 2, 20)).isEmpty)
    }

    #if os(macOS)
    func testBuiltInChatOpensWithMemory() {
        let l = DemoData.make(endingOn: demoEnd)
        let p = ChatRunner.prompt(question: "这个月收益多少", voice: "温柔一点。", aim: nil, where: "用户正在看「总览」页。", history: [],
                                  memory: MemoryBrief(ledger: l).promptText)
        XCTAssertTrue(p.contains("收益：我说「收益」是指小店赚的钱"))
        XCTAssertTrue(p.contains("summary") && p.contains("regulars") && p.contains("remember"))
        XCTAssertTrue(p.hasSuffix("用户这一句：这个月收益多少"))
        let plain = ChatRunner.prompt(question: "你好", voice: "", aim: nil, where: "", history: [])
        XCTAssertFalse(plain.contains("用户定的规矩"))
    }
    #endif
}
