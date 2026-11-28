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
