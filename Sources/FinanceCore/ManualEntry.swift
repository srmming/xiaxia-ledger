import Foundation

// 自己动手记账要用的规则：算式金额、备注和标签、重复记账、复制、拆开、退款、批量加标签、搜索、「常记的」。
// app、fin、MCP 都只调这里，不各写一套。每次写入都记改动记录，能撤销。

// MARK: - 算式金额

extension Money {
    /// 算式金额：「12,50+3,20」「20-4,5」「3*2,20」。只认加、减、乘（乘号后面要是整数倍数，比如「3*2,20」或「2,20*3」）。
    /// 没有运算符就和 Money(parsing:) 一样。看不懂返回 nil。
    public static func evaluate(_ expression: String) -> Money? {
        let text = expression
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: "€", with: "")
            .replacingOccurrences(of: "\u{2212}", with: "-")
            .replacingOccurrences(of: "×", with: "*")
            .replacingOccurrences(of: "x", with: "*")
            .replacingOccurrences(of: "X", with: "*")
        guard !text.isEmpty else { return nil }
        // 按 + / - 切成几项（开头的负号算第一项的）。
        var terms: [(sign: Int64, text: String)] = []
        var current = ""
        var sign: Int64 = 1
        for (i, ch) in text.enumerated() {
            if (ch == "+" || ch == "-") && i > 0 && current.last != "*" {
                terms.append((sign, current))
                sign = ch == "-" ? -1 : 1
                current = ""
            } else {
                current.append(ch)
            }
        }
        terms.append((sign, current))
        var total: Int64 = 0
        for term in terms {
            guard let v = Self.product(term.text) else { return nil }
            total += term.sign * v
        }
        return Money(cents: total)
    }

    /// 一项里的乘法：「3*2,20」= 6,60。最多一个乘号，有一边要是整数。
    private static func product(_ text: String) -> Int64? {
        let parts = text.split(separator: "*", omittingEmptySubsequences: false).map(String.init)
        if parts.count == 1 { return Money(parsing: parts[0])?.cents }
        guard parts.count == 2 else { return nil }
        if let n = Int64(parts[0]), let m = Money(parsing: parts[1]) { return n * m.cents }
        if let m = Money(parsing: parts[0]), let n = Int64(parts[1]) { return m.cents * n }
        return nil
    }

    /// 写的是不是算式（有加减乘），界面上据此显示「= 结果」。
    public static func isExpression(_ text: String) -> Bool {
        let t = text.trimmingCharacters(in: .whitespaces)
        return t.dropFirst().contains { "+-−*×".contains($0) }
    }
}

// MARK: - 标签

public enum Tags {
    /// 整理用户写的标签：去掉 #、前后空格，空的不要，重复的只留一个（按出现顺序）。
    public static func clean(_ raw: [String]) -> [String] {
        var seen = Set<String>()
        var out: [String] = []
        for r in raw.flatMap({ $0.split(whereSeparator: { $0 == "," || $0 == "，" || $0 == " " }) }) {
            let t = r.trimmingCharacters(in: .whitespaces).trimmingCharacters(in: CharacterSet(charactersIn: "#＃"))
            guard !t.isEmpty, !seen.contains(t.lowercased()) else { continue }
            seen.insert(t.lowercased())
            out.append(t)
        }
        return out
    }

    /// 空数组存成 nil，账本里干净些。
    static func stored(_ list: [String]) -> [String]? { list.isEmpty ? nil : list }
}

extension Transaction {
    public var tagList: [String] { tags ?? [] }

    /// 搜索：说明、整理过的商户名、备注、标签、分类、金额。以 # 开头只按标签找。
    public func matches(_ query: String) -> Bool {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return true }
        if q.hasPrefix("#") || q.hasPrefix("＃") {
            let tag = String(q.dropFirst())
            return tagList.contains { $0.lowercased() == tag || (!tag.isEmpty && $0.lowercased().hasPrefix(tag)) }
        }
        if description.lowercased().contains(q) || Merchant.display(description).lowercased().contains(q) { return true }
        if let note, note.lowercased().contains(q) { return true }
        if tagList.contains(where: { $0.lowercased().contains(q) }) { return true }
        if (category ?? "").lowercased().contains(q) { return true }
        if amount.formatted.contains(q) || amount.magnitude.formatted.contains(q) { return true }
        if let m = Money(parsing: q), m.cents != 0, m.magnitude == amount.magnitude { return true }
        return false
    }

    /// 能不能当普通的一笔来改、复制、拆开（转账、借款、分期、目标里的那几笔不行）。
    public var isPlainEntry: Bool { flow == nil && !isTransfer }
}

extension Ledger {
    /// 账本里用过的所有标签，用得多的排前面。
    public var allTags: [String] {
        var count: [String: Int] = [:]
        for t in transactions { for tag in t.tagList { count[tag, default: 0] += 1 } }
        return count.sorted { $0.value == $1.value ? $0.key < $1.key : $0.value > $1.value }.map(\.key)
    }

    /// 给一批流水加 / 去标签。
    @discardableResult
    public mutating func tagTransactions(_ ids: [UUID], add: [String], remove: [String] = [], author: String) throws -> ChangeRecord {
        let add = Tags.clean(add), remove = Set(Tags.clean(remove).map { $0.lowercased() })
        guard !add.isEmpty || !remove.isEmpty else { throw ManageError.nothingToChange }
        let set = Set(ids)
        guard transactions.contains(where: { set.contains($0.id) }) else { throw EditError.unknownTransaction(ids.first?.uuidString ?? "", 0) }
        var parts: [String] = []
        if !add.isEmpty { parts.append("加标签 " + add.map { "#\($0)" }.joined(separator: " ")) }
        if !remove.isEmpty { parts.append("去掉标签 " + Tags.clean(Array(remove)).map { "#\($0)" }.joined(separator: " ")) }
        return modify(ids, kind: .edit, summary: "\(ids.count) 笔" + parts.joined(separator: "，"), author: author) {
            var list = $0.tagList.filter { !remove.contains($0.lowercased()) }
            for t in add where !list.contains(where: { $0.lowercased() == t.lowercased() }) { list.append(t) }
            $0.tags = Tags.stored(list)
        }
    }

    // MARK: - 复制、退款、拆开

    /// 照着一笔再记一笔（日期换成 date，默认今天）。上周的理发这周又去了，就复制一下。
    @discardableResult
    public mutating func duplicateTransaction(_ id: UUID, date: LocalDate = .today, author: String) throws -> ChangeRecord {
        guard let t = transactions.first(where: { $0.id == id }) else { throw EditError.unknownTransaction(id.uuidString, 0) }
        guard t.isPlainEntry else { throw ManualEntryError.notPlain }
        let copy = Transaction(date: date, amount: t.amount, description: t.description, accountID: t.accountID, bookID: t.bookID,
                               category: t.category, source: "手记", note: t.note, tags: t.tags)
        try requireAccount(copy.accountID)
        transactions.append(copy)
        return record(.add, "复制一笔：\(copy.description) \(copy.amount.formatted)（\(date)）", ids: [copy.id], author: author)
    }

    /// 给一笔支出记退款：钱回到同一个账户，分类「退款」，会冲减支出。amount 不填就是全额。
    @discardableResult
    public mutating func addRefund(of id: UUID, amount: Money? = nil, date: LocalDate = .today, author: String) throws -> ChangeRecord {
        guard let t = transactions.first(where: { $0.id == id }) else { throw EditError.unknownTransaction(id.uuidString, 0) }
        guard t.isPlainEntry, t.amount.isExpense else { throw ManualEntryError.refundNeedsExpense }
        let value = (amount ?? t.amount).magnitude
        guard value.cents > 0 else { throw EditError.amountMustBePositive }
        guard value <= t.amount.magnitude else { throw ManualEntryError.refundTooMuch(t.amount.magnitude.formatted) }
        let name = Merchant.display(t.description)
        let tx = Transaction(date: date, amount: value, description: "退款：\(name)", accountID: t.accountID, bookID: t.bookID,
                             category: Transaction.refundCategory, source: "手记", note: "原来那笔：\(t.date) \(t.amount.formatted)",
                             tags: t.tags)
        transactions.append(tx)
        return record(.add, "记退款：\(name) \(value.formatted)", ids: [tx.id], author: author)
    }

    /// 一笔拆成几笔（超市小票里有吃的也有日用品）。每份写金额（正数）和分类，合计要等于原来的金额。
    /// 第一份沿用原来那笔，其余新记；撤销时变回原来那一笔。
    @discardableResult
    public mutating func splitTransaction(_ id: UUID, parts: [SplitPart], author: String) throws -> ChangeRecord {
        guard let i = transactions.firstIndex(where: { $0.id == id }) else { throw EditError.unknownTransaction(id.uuidString, 0) }
        let t = transactions[i]
        guard t.isPlainEntry else { throw ManualEntryError.notPlain }
        guard parts.count >= 2 else { throw ManualEntryError.splitNeedsTwo }
        guard parts.allSatisfy({ $0.amount.cents > 0 }) else { throw EditError.amountMustBePositive }
        let sum = parts.reduce(Money.zero) { $0 + $1.amount }
        guard sum == t.amount.magnitude else { throw ManualEntryError.splitMismatch(sum: sum.formatted, total: t.amount.magnitude.formatted) }
        let sign: Int64 = t.amount.isExpense ? -1 : 1
        var extra: [Transaction] = []
        for p in parts.dropFirst() {
            extra.append(Transaction(date: t.date, amount: Money(cents: sign * p.amount.cents), description: p.description ?? t.description,
                                     accountID: t.accountID, bookID: t.bookID, category: p.category ?? t.category,
                                     source: t.source, note: p.note, tags: t.tags))
        }
        let first = parts[0]
        let names = parts.map { "\($0.category ?? t.category ?? "未分类") \($0.amount.formatted)" }.joined(separator: " + ")
        var change = modify([t.id], kind: .edit, summary: "拆开：\(Merchant.display(t.description)) \(t.amount.magnitude.formatted) → \(names)",
                            author: author) {
            $0.amount = Money(cents: sign * first.amount.cents)
            if let c = first.category { $0.category = c }
            if let d = first.description { $0.description = d }
            if let n = first.note { $0.note = n }
        }
        transactions += extra
        change.transactionIDs += extra.map(\.id)
        changes[changes.count - 1] = change
        return change
    }

    // MARK: - 重复记账

    /// 记一笔并设成重复：这一笔现在就记上，以后每到日子（app 打开时、fin repeat run）自动再记。
    @discardableResult
    public mutating func addRecurring(_ tx: Transaction, frequency: Recurring.Frequency, until: LocalDate? = nil,
                                      author: String) throws -> ChangeRecord {
        guard tx.isPlainEntry else { throw ManualEntryError.notPlain }
        try requireAccount(tx.accountID)
        if let b = tx.bookID { try requireBook(b) }
        transactions.append(tx)
        let rule = Recurring(template: tx, frequency: frequency, start: tx.date, until: until)
        recurring.append(rule)
        let change = snapshotChange(.add, "记一笔并设成\(frequency.label)：\(tx.description) \(tx.amount.formatted)", ids: [tx.id],
                                    before: { var s = PlanSnapshot(); s.addedRecurringIDs = [rule.id]; return s }(), author: author)
        changes.append(change)
        return change
    }

    /// 把一笔已有的流水设成重复（从它的下一期开始自动记）。
    @discardableResult
    public mutating func makeRecurring(_ id: UUID, frequency: Recurring.Frequency, until: LocalDate? = nil,
                                       author: String) throws -> ChangeRecord {
        guard let t = transactions.first(where: { $0.id == id }) else { throw EditError.unknownTransaction(id.uuidString, 0) }
        guard t.isPlainEntry else { throw ManualEntryError.notPlain }
        let rule = Recurring(template: t, frequency: frequency, start: t.date, until: until)
        recurring.append(rule)
        let change = snapshotChange(.edit, "设成\(frequency.label)：\(t.description) \(t.amount.formatted)，下次 \(rule.nextDate)",
                                    before: { var s = PlanSnapshot(); s.addedRecurringIDs = [rule.id]; return s }(), author: author)
        changes.append(change)
        return change
    }

    /// 到日子的重复记账全部记上。没有到期的返回 nil（不写改动记录）。
    @discardableResult
    public mutating func postDueRecurring(today: LocalDate = .today, author: String) -> ChangeRecord? {
        let before = recurring
        var added: [Transaction] = []
        for k in recurring.indices where !recurring[k].paused {
            var guardCount = 0
            while recurring[k].nextDate <= today, guardCount < 400 {
                if let end = recurring[k].until, recurring[k].nextDate > end { break }
                guardCount += 1
                let r = recurring[k]
                guard accounts.contains(where: { $0.id == r.template.accountID }),
                      r.template.bookID.map({ b in books.contains { $0.id == b } }) ?? true else { break }
                added.append(Transaction(date: r.nextDate, amount: r.template.amount, description: r.template.description,
                                         accountID: r.template.accountID, bookID: r.template.bookID, category: r.template.category,
                                         source: "重复记账", note: r.template.note, tags: r.template.tags))
                recurring[k].count += 1
                recurring[k].nextDate = r.date(after: recurring[k].count)
            }
        }
        guard !added.isEmpty else { recurring = before; return nil }
        transactions += added
        let names = Dictionary(grouping: added, by: \.description).map { "\($0.key) \($0.value[0].amount.magnitude.formatted)" + ($0.value.count > 1 ? " ×\($0.value.count)" : "") }
            .sorted().joined(separator: "、")
        var snap = PlanSnapshot()
        snap.recurring = before
        let change = snapshotChange(.add, "自动记了 \(added.count) 笔重复的账：\(names)", ids: added.map(\.id), before: snap, author: author)
        changes.append(change)
        return change
    }

    /// 改一条重复记账（暂停 / 继续、改金额、改截止日）。
    @discardableResult
    public mutating func updateRecurring(_ rule: Recurring, author: String) throws -> ChangeRecord {
        guard let i = recurring.firstIndex(where: { $0.id == rule.id }) else { throw ManualEntryError.unknownRecurring }
        let old = recurring[i]
        guard old != rule else { throw ManageError.nothingToChange }
        try requireAccount(rule.template.accountID)
        recurring[i] = rule
        var snap = PlanSnapshot(); snap.recurring = [old]
        let what = old.paused != rule.paused ? (rule.paused ? "暂停" : "继续") : "改了"
        let change = snapshotChange(.edit, "\(what)重复记账：\(rule.template.description)", before: snap, author: author)
        changes.append(change)
        return change
    }

    /// 停掉一条重复记账。已经记上的流水不动。
    @discardableResult
    public mutating func removeRecurring(_ id: UUID, author: String) throws -> ChangeRecord {
        guard let i = recurring.firstIndex(where: { $0.id == id }) else { throw ManualEntryError.unknownRecurring }
        let old = recurring.remove(at: i)
        var snap = PlanSnapshot(); snap.recurring = [old]
        let change = snapshotChange(.edit, "停掉重复记账：\(old.template.description) \(old.template.amount.formatted)\(old.frequency.label)",
                                    before: snap, author: author)
        changes.append(change)
        return change
    }

    /// 按 id 前几位或说明找重复记账。
    public func findRecurring(_ key: String) -> [Recurring] {
        let k = key.trimmingCharacters(in: .whitespaces).lowercased()
        let byID = recurring.filter { $0.id.uuidString.lowercased().hasPrefix(k) }
        return byID.isEmpty ? recurring.filter { $0.template.description.lowercased().contains(k) } : byID
    }

    // MARK: - 常记的

    /// 「常记的」：最近 120 天里记过两次以上的同一笔（同名称、同金额、同分类、同账户），点一下就能再记。
    /// 不够的用最近手记的补上。income 为 nil 时两种都要。
    public func frequentEntries(income: Bool? = nil, today: LocalDate = .today, limit: Int = 6) -> [Transaction] {
        let since = today.adding(days: -120)
        struct Key: Hashable { var d: String; var a: Int64; var c: String?; var acc: String; var b: String? }
        var stats: [Key: (n: Int, last: Transaction)] = [:]
        let visible = Set(accounts.filter { !$0.isPrivate }.map(\.id))
        for t in transactions where t.isPlainEntry && t.date >= since && t.date <= today && visible.contains(t.accountID) {
            if let income, t.amount.isIncome != income { continue }
            guard t.category != Transaction.refundCategory else { continue }
            let key = Key(d: Merchant.display(t.description), a: t.amount.cents, c: t.category, acc: t.accountID, b: t.bookID)
            var s = stats[key] ?? (0, t)
            s.n += 1
            if t.date >= s.last.date { s.last = t }
            stats[key] = s
        }
        let manual: (Transaction) -> Bool = { ($0.source ?? "").hasPrefix("手记") }
        let ranked = stats.values.sorted {
            let a = ($0.n >= 2 ? 1 : 0, manual($0.last) ? 1 : 0), b = ($1.n >= 2 ? 1 : 0, manual($1.last) ? 1 : 0)
            if a != b { return a > b }
            return $0.n == $1.n ? $0.last.date > $1.last.date : $0.n > $1.n
        }
        return ranked.filter { $0.n >= 2 || manual($0.last) }.prefix(limit).map { s in
            var t = s.last
            t.description = Merchant.display(t.description)
            return t
        }
    }
}

/// 拆开时的一份。
public struct SplitPart: Hashable, Sendable {
    public var amount: Money          // 正数
    public var category: String?
    public var description: String?
    public var note: String?
    public init(amount: Money, category: String? = nil, description: String? = nil, note: String? = nil) {
        self.amount = amount; self.category = category; self.description = description; self.note = note
    }

    /// fin 用的写法：「30:超市」「18,30:日用品:洗衣液」。
    public init?(parsing text: String) {
        let bits = text.split(separator: ":", maxSplits: 2, omittingEmptySubsequences: false).map(String.init)
        guard let m = Money.evaluate(bits[0]), m.cents != 0 else { return nil }
        self.init(amount: m.magnitude, category: bits.count > 1 && !bits[1].isEmpty ? bits[1] : nil,
                  description: bits.count > 2 && !bits[2].isEmpty ? bits[2] : nil)
    }
}

/// 重复记账：一笔模板 + 多久一次。按开始那天的日子往后排（每月 31 号遇到小月就记在月底）。
public struct Recurring: Identifiable, Hashable, Codable, Sendable {
    public enum Frequency: String, Codable, Sendable, CaseIterable {
        case weekly, monthly, yearly
        public var label: String {
            switch self { case .weekly: "每周"; case .monthly: "每月"; case .yearly: "每年" }
        }
    }

    public var id: UUID
    public var template: Transaction
    public var frequency: Frequency
    /// 第一笔的日期，往后都按它排。
    public var start: LocalDate
    /// 已经记了几期之后的（第一笔算第 0 期，所以新建时是 1）。
    public var count: Int
    public var nextDate: LocalDate
    public var until: LocalDate?
    public var paused: Bool

    public init(id: UUID = UUID(), template: Transaction, frequency: Frequency, start: LocalDate, until: LocalDate? = nil) {
        self.id = id; self.template = template; self.frequency = frequency; self.start = start
        self.until = until; self.paused = false; self.count = 1
        self.nextDate = start
        self.nextDate = date(after: 1)
    }

    /// 第 n 期的日期（第 0 期 = start）。
    public func date(after n: Int) -> LocalDate {
        switch frequency {
        case .weekly: return start.adding(days: 7 * n)
        case .monthly: return start.adding(months: n)
        case .yearly: return start.adding(months: 12 * n)
        }
    }

    /// 一句话：「每月 1 号 · 房租 650,00 €」。
    public var summary: String {
        let when: String
        switch frequency {
        case .weekly: when = "每周\(["一", "二", "三", "四", "五", "六", "日"][start.weekdayIndex])"
        case .monthly: when = "每月 \(start.day) 号"
        case .yearly: when = "每年 \(start.month) 月 \(start.day) 号"
        }
        return "\(when) · \(template.description) \(template.amount.magnitude.formatted)"
    }
}

public enum ManualEntryError: Error, LocalizedError, Equatable {
    case notPlain
    case refundNeedsExpense
    case refundTooMuch(String)
    case splitNeedsTwo
    case splitMismatch(sum: String, total: String)
    case unknownRecurring

    public var errorDescription: String? {
        switch self {
        case .notPlain: "这笔是转账、借款、分期或目标的一部分，不能这样改。"
        case .refundNeedsExpense: "只有支出才能记退款。"
        case .refundTooMuch(let max): "退款不能比原来那笔多，最多 \(max)。"
        case .splitNeedsTwo: "至少拆成两份。"
        case .splitMismatch(let sum, let total): "拆开的几份合计 \(sum)，和原来的 \(total) 对不上。"
        case .unknownRecurring: "找不到这条重复记账。"
        }
    }
}

// MARK: - 日期加减（不带时区，按公历）

extension LocalDate {
    static let gregorian: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }()

    var utcDate: Date {
        Self.gregorian.date(from: DateComponents(year: year, month: month, day: day)) ?? Date(timeIntervalSince1970: 0)
    }

    init(utc date: Date) {
        let c = Self.gregorian.dateComponents([.year, .month, .day], from: date)
        self.init(year: c.year ?? 1970, month: c.month ?? 1, day: c.day ?? 1)
    }

    /// 星期几：0 = 周一 … 6 = 周日。
    public var weekdayIndex: Int {
        let w = Self.gregorian.component(.weekday, from: utcDate)   // 1 = 周日
        return (w + 5) % 7
    }
}
