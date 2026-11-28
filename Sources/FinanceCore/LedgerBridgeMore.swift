import Foundation

// v3 接正式账本 第 8 步：导入流水、夏夏的记忆、账本改名。
// 一样的规矩：写入一律走正式账本已有的写法，带作者、记改动记录、能撤销；只加不删旧数据。

/// 不知道是哪家银行的 CSV：自己认出日期、金额、说明这几列。
public enum StatementGuess {
    static let dateNames = ["date", "fecha", "fecha operacion", "fecha valor", "fecha contable", "booking date", "transaction date",
                            "completed date", "日期", "交易日期", "交易时间", "记账日期", "时间"]
    static let amountNames = ["amount", "importe", "cantidad", "金额", "交易金额", "金额 元", "importe eur"]
    static let debitNames = ["debit", "cargo", "cargos", "debe", "支出", "支出金额", "withdrawal", "paid out"]
    static let creditNames = ["credit", "abono", "abonos", "haber", "收入", "收入金额", "deposit", "paid in"]
    static let descNames = ["description", "concepto", "descripcion", "movimiento", "details", "detalle", "描述", "摘要", "说明",
                            "交易对方", "商品", "备注", "对方户名", "merchant", "name", "payee"]

    /// 读一份 CSV。认不出来就说清缺哪一列。
    public static func read(_ text: String, accountID: String, source: String) throws -> ImportResult {
        let rows = CSV.parse(text)
        guard !rows.isEmpty else { throw ImportError.empty }
        // 有的银行在表头前面放几行说明：往下找到第一行同时有日期列和说明列的
        for (n, row) in rows.prefix(20).enumerated() {
            let keys = row.map { Dedup.normalize($0) }
            func find(_ names: [String]) -> String? { row.indices.first { names.contains(keys[$0]) }.map { String($0 + 1) } }
            guard let date = find(dateNames) else { continue }
            if keys.contains("completed date"), keys.contains("state"), n == 0 {
                return try Importers.revolutCSV(text, accountID: accountID, source: source)
            }
            let amount = find(amountNames), debit = find(debitNames), credit = find(creditNames)
            guard amount != nil || debit != nil || credit != nil else { throw ImportError.missingColumn("金额") }
            guard let desc = find(descNames) else { throw ImportError.missingColumn("说明") }
            let map = Importers.ColumnMap(date: date, amount: amount, debit: amount == nil ? debit : nil, credit: amount == nil ? credit : nil,
                                          description: desc, skipRows: n)
            return try Importers.genericCSV(text, map: map, accountID: accountID, source: source)
        }
        throw ImportError.missingColumn("日期")
    }
}

extension LedgerBridge {
    /// 一份流水读出来、和账本比过以后的样子。
    public struct StatementCheck: Equatable, Sendable {
        /// 文件里读懂了几笔。
        public var total: Int
        /// 账本里还没有的。
        public var fresh: Int
        /// 账本里已经有的（会跳过）。
        public var duplicates: Int
        /// 没读懂的行（合计行、没完成的交易…）。
        public var unread: Int
        /// 新的那几笔里的前几笔，给人先看一眼。
        public var sample: [String]
    }

    /// 把一份 CSV 流水导进正式账本里的一个账户。`dryRun` 时只数不写。重复的跳过，整批一条改动记录，能撤销。
    @discardableResult
    public static func importStatement(text: String, fileName: String, accountName: String, to ledger: inout Ledger,
                                       author: String, dryRun: Bool = false) throws -> (check: StatementCheck, change: ChangeRecord?) {
        let who = author.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !who.isEmpty else { throw TrialError("先在设置里填一下记账人是谁") }
        guard let account = ledger.accounts.first(where: { $0.name == accountName }) else { throw TrialError("先选这份流水是哪个账户的") }
        let read: ImportResult
        do { read = try StatementGuess.read(text, accountID: account.id, source: fileName) }
        catch let e as ImportError { throw TrialError("这份文件我读不懂：\(e.errorDescription ?? "格式不认识")。账本没动") }
        guard !read.transactions.isEmpty else { throw TrialError("这份流水里一笔都没读到，账本没动") }
        // 账户在哪一边，流水就记在哪个账本
        let shopIDs = Set(WealthBreakdown.businessAccounts(ledger))
        let book = (shopIDs.contains(account.id) ? ledger.books.first { $0.isBusiness } : ledger.books.first { !$0.isBusiness })?.id
        let rows = read.transactions.map { t -> Transaction in var c = t; if c.bookID == nil { c.bookID = book }; return c }
        var work = ledger
        let done = try work.importTransactions(rows, accountID: account.id, source: fileName, author: who)
        let check = StatementCheck(total: rows.count, fresh: done.added.count, duplicates: done.duplicates, unread: read.skipped.count,
                                   sample: done.added.prefix(3).map { "\($0.description) \($0.amount.formatted)" })
        if dryRun { return (check, nil) }
        guard let change = done.change else { throw TrialError("这 \(done.duplicates) 笔账本里都有了，没有新的") }
        ledger = work
        return (check, change)
    }

    /// 正式账本里夏夏的记忆，变成界面上的样子（一条一个话题，下面几行）。
    static func memos(of ledger: Ledger) -> [TrialBook.Memo] {
        ledger.memories().map { m in
            TrialBook.Memo(id: m.id, kind: m.kind == .rule ? .rule : m.kind == .lesson ? .lesson : .topic, topic: m.title,
                           lines: m.notes.map(\.text), source: m.notes.first?.source.label ?? "你说的", important: m.pinned)
        }
    }

    /// 记忆上的改动：记一条、在话题下面加一行、删掉、标重要、挪到另一类。没动记忆返回 nil。
    static func applyMemos(before: TrialBook, after: TrialBook, to work: inout Ledger, today: LocalDate, author who: String) throws -> [ChangeRecord]? {
        guard before.memos != after.memos else { return nil }
        func kind(_ k: TrialBook.Memo.Kind) -> Memory.Kind { k == .rule ? .rule : k == .lesson ? .lesson : .topic }
        let was = Dictionary(before.memos.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        let now = Dictionary(after.memos.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        var records: [ChangeRecord] = []
        do {
            for m in after.memos {
                let source: Memory.Source = m.source.contains("确认") ? .confirmed : .written
                guard let old = was[m.id] else {
                    for (n, line) in m.lines.enumerated() {
                        records.append(try work.remember(kind: kind(m.kind), title: m.topic, text: line, source: source, date: today,
                                                         allowNew: n == 0, author: who))
                    }
                    continue
                }
                for line in m.lines where !old.lines.contains(line) {
                    records.append(try work.remember(kind: kind(m.kind), title: m.topic, text: line, source: source, date: today, into: m.id, author: who))
                }
                guard old.lines.allSatisfy(m.lines.contains) else { throw TrialError("改记忆里的一行，在接正式账本的这一版里还没接上，账本没动") }
                if old.kind != m.kind || old.important != m.important {
                    records.append(try work.editMemory(m.id, kind: old.kind != m.kind ? kind(m.kind) : nil,
                                                       pinned: old.important != m.important ? m.important : nil, author: who))
                }
            }
            for m in before.memos where now[m.id] == nil { records.append(try work.removeMemory(m.id, author: who)) }
        } catch let e as MemoryError { throw TrialError(e.errorDescription ?? "这条没记上，账本没动") }
        guard !records.isEmpty else { throw TrialError("这一步在接正式账本的这一版里还没接上，账本没动") }
        return records
    }

    /// 账本改名。没改名返回 nil。
    static func applyNames(before: TrialBook, after: TrialBook, to work: inout Ledger, author who: String) throws -> [ChangeRecord]? {
        guard before.lifeName != after.lifeName || before.shopName != after.shopName else { return nil }
        var records: [ChangeRecord] = []
        do {
            if before.lifeName != after.lifeName {
                guard let b = work.books.first(where: { !$0.isBusiness }) else { throw TrialError("账本里没有生活这一本") }
                records.append(try work.renameBook(b.id, to: after.lifeName, author: who))
            }
            if before.shopName != after.shopName {
                guard let b = work.books.first(where: { $0.isBusiness }) else { throw TrialError("账本里没有店这一本") }
                records.append(try work.renameBook(b.id, to: after.shopName, author: who))
            }
        } catch let e as ManageError { throw TrialError(e.errorDescription ?? "名字没改成，账本没动") }
        return records
    }
}

// MARK: - 新用户从零开始

extension LedgerBridge {
    /// 这本账是不是刚开始：一个账户都没有、一笔流水都没有。新界面看到这样的账本就先走引导。
    public static func isBrandNew(_ ledger: Ledger) -> Bool { ledger.accounts.isEmpty && ledger.transactions.isEmpty && ledger.debts.isEmpty }

    /// 引导走完，把里面填的东西写进正式账本：账户和现在有多少（开账余额）、别人欠我的 / 我欠别人的（借款）、想要的那句话（记忆）。
    /// 每样都走正式账本自己的写法，带作者、记改动记录、能撤销。金额没填或者读不懂的那一行按 0 算；一行都没有就什么都不写。
    @discardableResult
    public static func firstSetup(_ ledger: inout Ledger, accounts: StartingAccounts, wish: String, today: LocalDate, author: String) throws -> [ChangeRecord] {
        let who = author.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !who.isEmpty else { throw TrialError("先在设置里填一下记账人是谁") }
        var work = ledger
        var records: [ChangeRecord] = []
        guard let book = work.books.first(where: { !$0.isBusiness })?.id ?? work.books.first?.id else { throw TrialError("账本里还没有账本，先回旧界面建一个") }
        do {
            for row in accounts.rows {
                let amount = row.amount ?? .zero
                let name = row.displayName
                switch row.kind {
                case .lent, .borrowed, .installment:
                    // 不是账户：记成一笔借款。没填多少就先不记（借款不能是 0）
                    guard amount > .zero else { continue }
                    records.append(try work.addDebt(counterparty: name, direction: row.kind == .lent ? .theyOweMe : .iOweThem, amount: amount, bookID: book,
                                                    date: today, accountID: nil, note: row.kind == .installment ? "分期，开始用夏夏账本时还欠这么多" : "开始用夏夏账本时就有的",
                                                    author: who).1)
                case .daily, .cash, .savings, .jar, .credit, .custom:
                    guard !work.accounts.contains(where: { $0.name == name }) else { throw TrialError("有两个账户都叫「\(name)」，改一个名字") }
                    // 信用卡、自己起名又标成「欠的」那种：填的是欠多少，开账余额是负的
                    let owes = row.kind == .credit || (row.kind == .custom && row.owes)
                    let kind: AccountKind = owes ? .credit : row.kind == .cash ? .cash : row.kind == .savings || row.kind == .jar ? .savings : .bank
                    let opening = owes ? .zero - amount : amount
                    records.append(try work.createAccount(Account(id: work.newAccountID(for: name), name: name, kind: kind),
                                                          openingBalance: opening == .zero ? nil : opening, date: today, author: who))
                }
            }
            let line = wish.trimmingCharacters(in: .whitespacesAndNewlines)
            if !line.isEmpty {
                records.append(try work.remember(kind: .topic, title: "我想要的", text: line, source: .written, date: today, allowNew: true, author: who))
            }
        } catch let e as TrialError { throw e } catch { throw TrialError((error as? LocalizedError)?.errorDescription ?? "没写成，账本没动") }
        ledger = work
        return records
    }
}


// MARK: - 店的本钱、估货值、欠款

extension LedgerBridge {
    /// 店里这三样的改动。都没动返回 nil。
    /// - 本钱：改总数、加一样后来投的 → 正式账本的「生意本钱」（开店时间、以前赚回来多少照旧）。
    /// - 估货值：加一次估的数。
    /// - 欠款：记一笔（欠别人的 / 别人欠店的）→ 生意账本里的一笔借款；还清一笔 → 那笔借款的还款，钱从店里的账户出。
    static func applyShopBooks(before: TrialBook, after: TrialBook, to work: inout Ledger, today: LocalDate, author who: String) throws -> [ChangeRecord]? {
        func key(_ i: TrialBook.Item) -> String { "\(i.name)|\(i.amount.cents)|\(i.off)|\(i.flag)" }
        let capitalChanged = before.capital.map(key) != after.capital.map(key)
        let stockChanged = before.stockEstimates.map(\.id) != after.stockEstimates.map(\.id)
        let debtsChanged = before.shopDebts.map(key) != after.shopDebts.map(key)
        guard capitalChanged || stockChanged || debtsChanged else { return nil }
        guard let shop = work.businessBook?.id else { throw TrialError("先打开生意那一边") }
        var records: [ChangeRecord] = []
        do {
            if capitalChanged {
                let old = work.business?.capital
                // 名字对得上的那几样，原来挂着的流水照旧挂着
                let items = after.capital.map { i in Capital.Item(name: i.name, amount: i.amount, txIDs: old?.items.first { $0.name == i.name }?.txIDs) }
                let total = items.map(\.amount).reduce(.zero, +)
                guard total > .zero else { throw TrialError("本钱要比 0 大") }
                records.append(try work.setCapital(Capital(total: total, openedOn: old?.openedOn, recoveredBefore: old?.recoveredBefore ?? .zero, items: items), author: who))
            }
            if stockChanged {
                // 删掉的：界面上的顺序就是账本里从新到旧的顺序，按位置对上是哪一天估的
                let dates = (work.business?.stockEstimates ?? []).sorted { $0.date > $1.date }.map(\.date)
                for (i, old) in before.stockEstimates.enumerated() where !after.stockEstimates.contains(where: { $0.id == old.id }) {
                    guard dates.indices.contains(i) else { throw TrialError("没对上是哪一天估的，账本没动") }
                    records.append(try work.removeStockEstimate(on: dates[i], author: who))
                }
                // 新估的
                for new in after.stockEstimates where !before.stockEstimates.contains(where: { $0.id == new.id }) {
                    records.append(try work.addStockEstimate(new.amount, note: new.note, date: today, author: who))
                }
            }
            if debtsChanged {
                // 新记的
                for d in after.shopDebts where !before.shopDebts.contains(where: { $0.id == d.id }) {
                    records.append(try work.addDebt(counterparty: d.name, direction: d.flag ? .theyOweMe : .iOweThem, amount: d.amount, bookID: shop,
                                                    date: today, accountID: nil, note: d.note.isEmpty ? nil : d.note, author: who).1)
                }
                // 还清的：钱从余额少了这么多的那个店里账户出
                for d in after.shopDebts {
                    guard let o = before.shopDebts.first(where: { $0.id == d.id }), !o.off else { continue }
                    if o.tag == installmentTag {
                        // 分期还了一期（或最后一期）：少了多少就是这一期还了多少
                        let paid = o.amount - d.amount
                        guard paid > .zero else { continue }
                        guard work.installments.contains(where: { $0.id == o.id }) else { throw TrialError("「\(o.name)」这笔分期在账本里找不到了") }
                        records.append(try work.payInstallment(o.id, amount: paid, date: today, author: who))
                        continue
                    }
                    guard d.off else { continue }
                    guard let real = work.debts.first(where: { $0.id == o.id }) else { throw TrialError("「\(o.name)」是旧界面记的客人欠款，先回旧界面改") }
                    let payer = after.accounts.first { a in before.accounts.first { $0.id == a.id }.map { $0.balance - a.balance == o.amount } == true }
                    guard let payer, let acc = work.accounts.first(where: { $0.name == payer.name }) else { throw TrialError("没看出这笔钱是从哪个账户出的，账本没动") }
                    records.append(try work.repay(debtID: real.id, amount: o.amount, date: today, accountID: acc.id, author: who))
                }
                // 删掉的（记错了）：欠款连同它的借、还流水一起删；分期连同已经记的那几期一起删
                for o in before.shopDebts where !after.shopDebts.contains(where: { $0.id == o.id }) {
                    if work.debts.contains(where: { $0.id == o.id }) { records.append(try work.removeDebt(o.id, author: who)) }
                    else if work.installments.contains(where: { $0.id == o.id }) { records.append(try work.removeInstallment(o.id, author: who)) }
                    else { throw TrialError("「\(o.name)」是旧界面记的客人欠款，先回旧界面删。账本没动") }
                }
            }
        } catch let e as TrialError { throw e } catch { throw TrialError((error as? LocalizedError)?.errorDescription ?? "没写成，账本没动") }
        guard !records.isEmpty else { throw TrialError("这一步在接正式账本的这一版里还没接上，账本没动") }
        return records
    }
}


// MARK: - 分类

extension LedgerBridge {
    /// 正式账本里的支出分类，变成界面上「改分类」「自己填」里的那一排：用得多的在前，最后是「还没分」。
    static func categories(of ledger: Ledger) -> [TrialBook.Category] {
        var used: [String: Int] = [:]
        // 只算真的花销：转账、还款、存钱这些往来带的分类（「账户间转账」「分期还款」…）不是给用户挑的
        for t in ledger.transactions where !t.amount.isIncome && t.flow == nil && !t.isTransfer { if let c = t.category { used[c, default: 0] += 1 } }
        let custom = ledger.profile.categories.filter { !$0.income }.map(\.name)
        let names = Set(used.keys).union(custom).subtracting(["还没分", "未分类"])
        let sorted = names.sorted { (used[$0] ?? 0, $1) > (used[$1] ?? 0, $0) }
        return sorted.map { TrialBook.Category(emoji($0), $0) } + [TrialBook.Category("❓", "还没分")]
    }

    /// 分类上的改动：新建一个、改名（改成已有的名字就是并进去，流水一起改）。没动分类返回 nil。只换图标的这一版不接。
    static func applyCategories(before: TrialBook, after: TrialBook, to work: inout Ledger, author who: String) throws -> [ChangeRecord]? {
        let was = before.categories.map(\.name), now = after.categories.map(\.name)
        var records: [ChangeRecord] = []
        guard Set(was) != Set(now) else {
            guard before.categories != after.categories else { return nil }
            // 只换了图标
            for c in after.categories {
                guard let o = before.categories.first(where: { $0.name == c.name }), o.emoji != c.emoji else { continue }
                guard c.name != "还没分" else { throw TrialError("「还没分」的图标不换") }
                do { records.append(try work.setCategoryEmoji(c.name, emoji: c.emoji, author: who)) }
                catch { throw TrialError((error as? LocalizedError)?.errorDescription ?? "图标没换成，账本没动") }
            }
            return records.isEmpty ? nil : records
        }
        let gone = was.filter { !now.contains($0) }, new = now.filter { !was.contains($0) }
        do {
            if gone.count == 1, new.count <= 1 {
                // 改名：原来叫这个名字的流水现在叫什么，就是改成了什么
                let old = gone[0]
                let ids = Set(before.entries.filter { $0.name == old }.map(\.id))
                let target = new.first ?? after.entries.first { ids.contains($0.id) }?.name
                if let target, target != old, target != "还没分" {
                    records.append(try work.renameCategory(old, to: target, author: who))
                } else {
                    // 删掉：流水变回还没分（没有流水就只是把这个分类拿掉）
                    records.append(try work.removeCategory(old, moveTo: nil, author: who))
                }
            } else if gone.isEmpty {
                for n in new { records.append(try work.addCategory(n, income: false, author: who)) }
            } else {
                throw TrialError("一次改了好几个分类，这一步还没接上，账本没动")
            }
        } catch let e as TrialError { throw e } catch { throw TrialError((error as? LocalizedError)?.errorDescription ?? "分类没改成，账本没动") }
        return records
    }
}
