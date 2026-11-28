import Foundation

/// 试用的示例账本（设计稿里那一套，全是编的名字和数）。Mac 和 iPhone 的试用版用同一份，不各抄一份。
extension TrialBook {
    static func eur(_ s: String) -> Money { Money(parsing: s) ?? .zero }

    public static func goalNote(_ j: Journey) -> String {
        guard let next = j.nextStation, !j.isFinished else { return "\(j.name) · 走完了" }
        func short(_ m: Money) -> String {
            m.formatted.replacingOccurrences(of: "\u{00A0}€", with: "").replacingOccurrences(of: " €", with: "").replacingOccurrences(of: ",00", with: "")
        }
        return "\(j.name) · 这一站 \(short(j.saved)) / \(short(next.target))"
    }

    public static var demoJourney: Journey {
        var j = Journey(name: "换新电脑", why: "为了剪自己的片子",
                        stations: [
                            .init(id: 0, target: .zero, title: "出发"),
                            .init(id: 1, target: eur("50"), title: "第一步"),
                            .init(id: 2, target: eur("200")),
                            .init(id: 3, target: eur("700"), title: "走到一半"),
                            .init(id: 4, target: eur("1050")),
                            .init(id: 5, target: eur("1400"), title: "电脑到手"),
                        ],
                        saved: eur("519"), monthlyPlan: eur("200"), savedThisMonth: eur("80"), resisted: 13)
        j.resisted = 13
        return j
    }

    /// 示例账本。每次拿到的是新的一份（里面的 id 是新的）。
    public static var demo: TrialBook {
        let j = demoJourney
        func item(_ e: String, _ n: String, _ note: String, _ a: String, tag: String = "", off: Bool = false, flag: Bool = false) -> TrialBook.Item {
            .init(emoji: e, name: n, note: note, amount: eur(a), tag: tag, off: off, flag: flag)
        }
        var b = TrialBook(
            accounts: [
                Account(emoji: "💳", name: "日常卡", note: "晴空银行 · 今天刚导入", balance: eur("1496,61")),
                Account(emoji: "🏦", name: "储蓄", note: "存着 · 不动", balance: eur("2400"), block: .emergency, short: "储蓄"),
                Account(emoji: "⭐", name: "换新电脑 存钱罐", note: goalNote(j), balance: eur("519"), block: .goal),
                Account(emoji: "🧳", name: "周末短途旅行 存钱罐", note: "存给「周末短途旅行」", balance: eur("120"), block: .goal),
                Account(emoji: "👟", name: "新跑鞋 存钱罐", note: "存给「新跑鞋」", balance: eur("60"), block: .goal),
                Account(emoji: "🎁", name: "给妈妈的生日礼物 存钱罐", note: "存给「给妈妈的生日礼物」", balance: eur("15"), block: .goal),
                Account(emoji: "💶", name: "现金", note: "钱包里 · 上次点数 11 月 10 日", balance: eur("85")),
                Account(emoji: "🏪", name: "小店账户", note: "店的银行卡 · 晴空银行", balance: eur("3679,39"), kind: .shop, block: .shop),
                Account(emoji: "💶", name: "店里现金", note: "收银抽屉里", balance: eur("240"), kind: .shop, block: .shop),
                Account(emoji: "💳", name: "店的信用卡", note: "欠 · 每月 10 日还", balance: eur("180"), kind: .debt, block: .none, side: .biz),
                Account(emoji: "🏦", name: "装修贷款", note: "欠 · 还剩 24 期，每月 350 €", balance: eur("8400"), kind: .debt, block: .none, side: .biz),
                Account(emoji: "💳", name: "信用卡", note: "欠 · 12 月 5 日要还", balance: eur("640"), kind: .debt, block: .none, short: "信用卡 · 欠"),
                Account(emoji: "📱", name: "手机分期", note: "欠 · 还剩 6 期，每月 200 €", balance: eur("1200"), kind: .debt, block: .none, short: "手机分期 · 欠"),
                Account(emoji: "🧑", name: "借给小李", note: "他欠我 · 说好 12 月还", balance: eur("120"), kind: .lent, block: .none, short: "小李欠我"),
            ],
            entries: [
                Entry(emoji: "🛒", name: "超市", meta: "Super Sol · 日常卡", amount: eur("-23,40"), tag: "流水导入", place: "Super Sol", account: "日常卡"),
                Entry(emoji: "☕", name: "咖啡", meta: "Café Nube · 现金", amount: eur("-3,20"), tag: "跟 AI 说的", place: "Café Nube", account: "现金"),
                Entry(emoji: "🥗", name: "午饭", meta: "La Tasca · 日常卡", amount: eur("-12,50"), tag: "拍小票", place: "La Tasca", account: "日常卡"),
                Entry(emoji: "💼", name: "私活进账", meta: "小林工作室 · 日常卡", amount: eur("420"), tag: "流水导入", daysAgo: 1, place: "小林工作室", account: "日常卡"),
                Entry(emoji: "❓", name: "Super Lumi", meta: "Super Lumi · 日常卡", amount: eur("-18,60"), tag: "等你看一眼", daysAgo: 1, place: "Super Lumi", account: "日常卡"),
            ],
            upcoming: [
                Entry(emoji: "🏠", name: "房租", meta: "12 月 1 日 · 13 天后", amount: eur("650")),
                Entry(emoji: "💳", name: "信用卡", meta: "12 月 5 日 · 日常卡够付", amount: eur("640"), red: true),
                Entry(emoji: "📱", name: "手机分期", meta: "12 月 8 日 · 第 7 / 12 期", amount: eur("200"), red: true),
            ],
            month: FreeToSpend(income: eur("2340"), fixed: eur("892"), forGoals: eur("200"), spent: eur("271,39"), daysLeft: 12),
            journey: j,
            letters: [
                Letter(title: "第一步", quote: "「两周，50 €，你没断过一天…」", date: "9 月 20 日",
                       tag: "第 1 站 · 存到 50 € · 第一步", headline: "第一步，走出来了。",
                       paragraphs: ["小满：", "两周，50 €，你没断过一天。", "那天你说先试试看。现在试过了：你做得到。",
                                    "下一站是 200。不急，照这个步子走就行。"],
                       facts: [["17 天", "从出发到这儿"], ["3 次", "忍住没买"], ["0 次", "断过"]]),
                Letter(title: "200 €", quote: "「那周你推掉了两顿外卖…」", date: "10 月 12 日",
                       tag: "第 2 站 · 存到 200 €", headline: "200 了。",
                       paragraphs: ["小满：", "那周你推掉了两顿外卖，自己煮了面。省下的 31 块，你顺手就存进来了。",
                                    "我没提醒你，是你自己想起来的。", "电脑还远，可是你已经在路上了。"],
                       facts: [["39 天", "从出发到这儿"], ["8 次", "忍住没买"], ["2 顿", "外卖换成自己煮"]]),
            ],
            splitWithEmergency: nil,
            monthlyMust: eur("860"))
        b.usualDailySpend = eur("31")
        b.smallGoals = [
            .init(name: "周末短途旅行", target: eur("300"), saved: eur("120"), due: "明年 3 月前"),
            .init(name: "新跑鞋", target: eur("95"), saved: eur("60"), due: "12 月底前"),
            .init(name: "给妈妈的生日礼物", target: eur("80"), saved: eur("15"), due: "明年 2 月 9 日前"),
        ]
        b.shopLoanMonthly = eur("350")
        b.shopBackBefore = eur("14971,50")
        // 固定要付的 892 是哪几样：月初就整个算进去了，手记到这几类时先对它，不扣第二遍
        b.fixedPlan = ["房租": eur("650"), "手机分期": eur("200"), "订阅": eur("42")]
        // 一个目标对一个账户：各自的存钱罐
        b.bigGoalAccount = b.account("换新电脑 存钱罐")?.id
        for i in b.smallGoals.indices { b.smallGoals[i].account = b.account(TrialBook.jarName(b.smallGoals[i].name))?.id }
        b.spendByCategory = [
            .init(emoji: "🏠", name: "房租", amount: eur("650"), lastMonth: eur("650")), .init(emoji: "📱", name: "手机分期", amount: eur("200"), lastMonth: eur("200")),
            .init(emoji: "🛒", name: "超市", amount: eur("142,19"), lastMonth: eur("162")), .init(emoji: "🥗", name: "餐饮", amount: eur("68,40"), lastMonth: eur("104")),
            .init(emoji: "🔁", name: "订阅", amount: eur("42"), lastMonth: eur("42")), .init(emoji: "🚇", name: "交通", amount: eur("32"), lastMonth: eur("32")),
            .init(emoji: "☕", name: "咖啡", amount: eur("28,80"), lastMonth: eur("45,50")),
        ]
        b.subscriptions = [
            item("☁️", "云盘 Plus", "12 月 2 日扣", "4,99"),
            item("🎬", "视频会员", "12 月 4 日扣", "9,99"),
            item("🎵", "音乐", "12 月 9 日扣", "10,99"),
            item("✂️", "剪辑软件", "12 月 15 日扣", "12,04", tag: "赚钱用的", flag: true),
            item("📰", "新闻", "12 月 21 日扣", "3,99"),
        ]
        b.wanted = [
            item("⌚", "运动手表", "还要冷静 21 小时", "189"),
            item("👟", "跑鞋", "冷静完了，还想要吗？", "95", tag: "该回答了"),
            item("🎮", "游戏手柄", "上周忍住了 · 存进目标", "59", off: true),
        ]
        func fixed(_ e: String, _ n: String, _ day: Int, _ a: String, last: String? = nil, flag: Bool = false) -> TrialBook.Item {
            .init(emoji: e, name: n, note: "每月 \(day) 日 · 小店账户", amount: eur(a), tag: flag ? "可省" : "必要", flag: flag,
                  account: "小店账户", day: day, lastMonth: last.map { eur($0) })
        }
        b.fixedCosts = [
            fixed("🧑", "给自己发的工资", 1, "1000"),
            fixed("🏠", "店面房租", 3, "600"),
            fixed("📣", "广告", 10, "80", flag: true),
            fixed("💡", "水电", 15, "70", last: "58"),
            fixed("🗓", "预约软件", 20, "40", last: "35", flag: true),
        ]
        b.purchases = [item("📦", "鲜花补货", "11 月 12 日", "340"), item("📦", "包装纸和丝带", "10 月 28 日", "310"), item("📦", "花瓶和花器", "10 月 6 日", "240")]
        b.stockEstimates = [item("📅", "9 月 30 日", "第三季度末", "2600"), item("📅", "6 月 30 日", "第二季度末", "2400"), item("📅", "开店时", "2025 年 10 月", "4200")]
        b.capital = [item("🔨", "装修", "2025 年 9 月", "14000"), item("💺", "设备和桌椅", "2025 年 9 月", "9800"),
                     item("📦", "第一批货", "2025 年 10 月", "4200"), item("🔑", "押金", "退租时能拿回", "4170")]
        b.shopDebts = [item("📦", "供货商赊账", "12 月 3 日到期", "320"), item("🧑", "熟客挂账", "11 月 9 日 · 说下次来付", "85", flag: true)]
        b.memos = [
            .init(kind: .topic, topic: "我想要的", lines: ["三年后不用为钱发愁", "先换台电脑，剪自己的片子"], source: "你说的", important: true),
            .init(kind: .rule, topic: "转给妈妈的钱", lines: ["每月 5 日转 150 €，不算支出，算家里的"], source: "你纠正的"),
            .init(kind: .topic, topic: "工资", lines: ["每月 28 日前后到，晚几天不用提醒", "私活的钱不固定，别算进每月进账"], source: "夏夏看出来的，你确认过"),
            .init(kind: .topic, topic: "Café Nube", lines: ["付现金。一周超过 4 次时说一声"], source: "你说的"),
            .init(kind: .rule, topic: "超过 100 € 的东西", lines: ["先放进想要清单冷静 48 小时"], source: "你说的"),
            .init(kind: .rule, topic: "店里和家里", lines: ["店里的钱不拿来付家里的开销，要用就走「两边转钱」"], source: "你说的"),
            .init(kind: .lesson, topic: "晴空银行 的流水", lines: ["「To EUR」开头的是自己账户之间转，不算花"], source: "夏夏看出来的，你确认过"),
            .init(kind: .lesson, topic: "Super Lumi", lines: ["小票上印的是总公司的名字，认成超市"], source: "你纠正的"),
        ]
        // 11 月每天收了多少：和设计稿同一个算法。11 月 1 日是周日；周日休息；16 号没记；18 号是今天，还没记。
        var r = 11.0
        for d in 1...30 {
            r = (r * 9301 + 49297).truncatingRemainder(dividingBy: 233280)
            let wd = (d + 5) % 7
            var amt = 120 + Int((r / 233280 * 140).rounded())
            if wd == 5 { amt += 170 }
            let state: TrialBook.ShopDay.State = d > 18 ? .future : wd == 6 ? .rest : d == 16 || d == 18 ? .missing : .open
            let cash = state == .open ? Money(cents: Int64(amt * 2 / 5) * 100) : .zero
            let card = state == .open ? Money(cents: Int64(amt) * 100) - cash : .zero
            b.shopDays.append(.init(day: d, cash: cash, card: card, state: state))
        }
        // 11 月店里的开销（全是编的）：哪天、哪一类、从哪个账户出
        func spend(_ day: Int, _ cat: String, _ what: String, _ a: String, from: String = "小店账户") {
            let c = TrialBook.shopCategories.first { $0.name == cat } ?? TrialBook.Category("🧾", "其他")
            b.entries.append(.init(emoji: c.emoji, name: c.name, meta: "\(what) · \(from)", amount: -eur(a), tag: "自己记的", daysAgo: 18 - day,
                                   side: .biz, place: what, account: from))
        }
        spend(17, "设备", "新花剪两把", "24,90", from: "店里现金")
        spend(15, "水电网", "11 月水电", "70")
        spend(14, "维修", "修冷柜", "60", from: "店里现金")
        spend(12, "进货", "鲜花补货", "340")
        spend(10, "广告", "街区小报广告", "80", from: "店的信用卡")
        spend(9, "交通运输", "送花的油费", "35", from: "店里现金")
        spend(7, "平台抽成", "外送平台 10 月抽成", "28,60")
        spend(5, "包装耗材", "包装纸和丝带", "46")
        spend(4, "进货", "绿植和多肉", "120")
        spend(3, "房租", "店面房租", "600")
        spend(2, "员工工资", "周末帮工", "180")
        // 过去两个月存下来的数（全是编的），给月份切换用
        func slice(_ e: String, _ n: String, _ a: String, _ last: String) -> TrialBook.SpendSlice { .init(emoji: e, name: n, amount: eur(a), lastMonth: eur(last)) }
        func past(_ e: String, _ n: String, _ place: String, _ a: String, _ ago: Int) -> TrialBook.Entry {
            .init(emoji: e, name: n, meta: "\(place) · 日常卡", amount: -eur(a), tag: "流水导入", daysAgo: ago, place: place, account: "日常卡")
        }
        b.pastMonths = [
            .init(key: .init(2026, 10), income: eur("2340"), fixed: eur("892"), forGoals: eur("200"), spent: eur("612,40"),
                  slices: [slice("🏠", "房租", "650", "650"), slice("📱", "手机分期", "200", "200"), slice("🛒", "超市", "162", "171,30"), slice("💊", "看病", "120", "0"),
                           slice("🥗", "餐饮", "136,50", "88"), slice("📱", "话费", "89", "0"), slice("☕", "咖啡", "45,50", "39"), slice("🔁", "订阅", "42", "42"),
                           slice("🚇", "交通", "40", "36"), slice("🎬", "娱乐", "19,40", "25")],
                  entries: [past("💊", "看病", "牙科诊所 Sonrisa", "120", 28), past("📱", "话费", "手机换屏幕", "89", 35), past("🛒", "超市", "Super Sol", "41,20", 22)],
                  weekly: [eur("148"), eur("122"), eur("140"), eur("104"), eur("98,40")], shopIn: eur("4210"), shopOut: eur("2874"), net: eur("2485,61")),
            .init(key: .init(2026, 9), income: eur("2340"), fixed: eur("892"), forGoals: eur("150"), spent: eur("571,30"),
                  slices: [slice("🏠", "房租", "650", "650"), slice("📱", "手机分期", "200", "200"), slice("🛒", "超市", "171,30", "158"), slice("🥗", "餐饮", "88", "102"),
                           slice("🔁", "订阅", "42", "42"), slice("☕", "咖啡", "39", "41"), slice("🚇", "交通", "78", "36"), slice("🎬", "娱乐", "25", "12"), slice("👕", "衣服", "170", "0")],
                  entries: [past("👕", "衣服", "Tienda Azul", "170", 60), past("🛒", "超市", "Super Sol", "38,90", 55)],
                  weekly: [eur("130"), eur("162"), eur("121"), eur("158,30")], shopIn: eur("3890"), shopOut: eur("2790"), net: eur("2100,20")),
        ]
        // 月底有多少、欠多少（净剩 = 有 − 欠），和上个月花到同一天花了多少
        b.pastMonths[0].have = eur("4525,61"); b.pastMonths[0].owe = eur("2040"); b.pastMonths[0].sameDaySpent = eur("1249,39")
        b.pastMonths[1].have = eur("4240,20"); b.pastMonths[1].owe = eur("2140")
        // 到那两个月底一共赚回来多少（回本页那条线）：10 月底就是「以前赚回来的」，9 月底再减掉 10 月赚的
        b.pastMonths[0].shopBack = b.shopBackBefore
        // 到那两个月底大目标存了多少：10 月底 = 现在的减掉这个月存的，9 月底再减掉 10 月存的 200
        b.pastMonths[0].goalSavedEnd = b.journey.saved - b.journey.savedThisMonth
        b.pastMonths[1].goalSavedEnd = b.journey.saved - b.journey.savedThisMonth - eur("200")
        b.pastMonths[1].shopBack = b.shopBackBefore - (eur("4210") - eur("2874"))
        // 10 月的两笔意外开销（看牙、手机换屏幕）：金额都没到规则那条线（一个月花销的一成），是之前标成意外开销的
        for e in b.pastMonths.first?.entries ?? [] where e.name == "看病" || e.place == "手机换屏幕" { b.surpriseMarks[e.id] = true }
        // 置顶成卡片的几张
        for n in ["日常卡", "换新电脑 存钱罐", "储蓄", "信用卡", "小店账户", "店里现金", "店的信用卡"] { try? b.setPinned(n, true) }
        return b
    }

    /// 示例里原来就有的几条改动（撤不了：没有留它们之前的样子）。
}
