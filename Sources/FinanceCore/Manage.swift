import Foundation

// 管理类的写入：账户间转账、改和删账户、账本、分类、借款、分期、目标。
// 和 Editor.swift 一样，每次写入记一条改动记录，都能撤销。

public enum ManageError: Error, LocalizedError, Equatable {
    case accountInUse(String, Int)
    case sameAccount
    case emptyName
    case nothingToChange

    public var errorDescription: String? {
        switch self {
        case .accountInUse(let name, let n): "「\(name)」里还有 \(n) 笔流水，不能直接删。可以先把这些流水删掉或改到别的账户。"
        case .sameAccount: "转出和转入不能是同一个账户"
        case .emptyName: "名字不能空着"
        case .nothingToChange: "没有要改的内容"
        }
    }
}

extension Ledger {
    // MARK: 账户间转账

    /// 自己的钱从一个账户挪到另一个：取现、转到 Revolut、还信用卡。两笔，不算收入也不算支出。
    @discardableResult
    public mutating func addAccountTransfer(amount: Money, from: String, to: String, date: LocalDate,
                                            bookID: String? = nil, note: String? = nil, author: String) throws -> ChangeRecord {
        guard amount.cents > 0 else { throw EditError.amountMustBePositive }
        guard from != to else { throw ManageError.sameAccount }
        try requireAccount(from); try requireAccount(to)
        if let bookID { try requireBook(bookID) }
        let fromName = accounts.first { $0.id == from }?.name ?? from
        let toName = accounts.first { $0.id == to }?.name ?? to
        let text = (note?.isEmpty == false ? note! : "\(fromName) → \(toName)")
        let tid = UUID()
        let outTx = Transaction(date: date, amount: -amount, description: text, accountID: from, bookID: bookID,
                                category: "账户间转账", transferID: tid, source: "手记", flow: .internal)
        let inTx = Transaction(date: date, amount: amount, description: text, accountID: to, bookID: bookID,
                               category: "账户间转账", transferID: tid, source: "手记", flow: .internal)
        transactions += [outTx, inTx]
        return record(.transfer, "账户间转账：\(fromName) → \(toName) \(amount.formatted)", ids: [outTx.id, inTx.id], author: author)
    }

    /// 把已有的流水（多半是导入的银行记录）标成「自己账户间转账」：不再算收入或支出。
    /// counterAccount 有值时，在那个账户补上另一半（比如取现：银行卡出、现金进）；另一半已经导入过就不用填。
    @discardableResult
    public mutating func markAsAccountTransfer(_ ids: [UUID], counterAccount: String? = nil, author: String) throws -> ChangeRecord {
        let set = Set(ids)
        let targets = transactions.filter { set.contains($0.id) }
        guard !targets.isEmpty else { throw EditError.unknownTransaction(ids.first?.uuidString ?? "", 0) }
        if let counterAccount { try requireAccount(counterAccount) }
        var extra: [Transaction] = []
        var links: [UUID: UUID] = [:]
        if let counterAccount {
            for t in targets where t.accountID != counterAccount {
                let tid = UUID()
                links[t.id] = tid
                extra.append(Transaction(date: t.date, amount: -t.amount, description: t.description, accountID: counterAccount,
                                         bookID: t.bookID, category: "账户间转账", transferID: tid, source: "手记", flow: .internal))
            }
        }
        var change = modify(targets.map(\.id), kind: .transfer,
                            summary: "\(targets.count) 笔标成账户间转账，不算收支", author: author) {
            $0.flow = .internal
            $0.category = "账户间转账"
            if let tid = links[$0.id] { $0.transferID = tid }
        }
        if !extra.isEmpty {
            transactions += extra
            change.transactionIDs += extra.map(\.id)
            changes[changes.count - 1] = change
        }
        return change
    }

    /// 和这笔流水成对的另一笔（转账的另一半）。删一笔转账时两笔一起删。
    public func pairedIDs(of id: UUID) -> [UUID] {
        guard let t = transactions.first(where: { $0.id == id }), let tid = t.transferID else { return [id] }
        return transactions.filter { $0.transferID == tid }.map(\.id)
    }

    // MARK: 一次改分类和账本

    /// 一次给一批流水定分类和账本（整理未分类时用）。哪个是 nil 就不动哪个。
    @discardableResult
    public mutating func classify(_ ids: [UUID], category: String?, bookID: String?, author: String) throws -> ChangeRecord {
        guard category != nil || bookID != nil else { throw ManageError.nothingToChange }
        if let bookID { try requireBook(bookID) }
        var parts: [String] = []
        if let category { parts.append("分类「\(category)」") }
        if let bookID { parts.append("账本「\(bookName(bookID))」") }
        return modify(ids, kind: .categorize, summary: "\(ids.count) 笔定为" + parts.joined(separator: "、"), author: author) {
            if let category { $0.category = category }
            if let bookID { $0.bookID = bookID }
        }
    }

    /// 把一个分类整体改名（或并进另一个分类）。
    @discardableResult
    public mutating func renameCategory(_ old: String, to new: String, author: String) throws -> ChangeRecord {
        let name = new.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { throw ManageError.emptyName }
        let ids = transactions.filter { $0.category == old }.map(\.id)
        guard !ids.isEmpty else { throw ManageError.nothingToChange }
        return modify(ids, kind: .categorize, summary: "分类「\(old)」改名为「\(name)」（\(ids.count) 笔）", author: author) { $0.category = name }
    }

    // MARK: 账户和账本

    func snapshotChange(_ kind: ChangeRecord.Kind, _ summary: String, ids: [UUID] = [], before: PlanSnapshot,
                        previous: [Transaction]? = nil, author: String) -> ChangeRecord {
        var change = ChangeRecord(kind: kind, summary: summary, transactionIDs: ids, author: author)
        change.before = before
        change.previous = previous
        return change
    }

    /// 加一个账户，可以顺手填上现在的余额（记成期初余额）。整个能撤销。
    @discardableResult
    public mutating func createAccount(_ account: Account, openingBalance: Money? = nil, date: LocalDate = .today,
                                       author: String) throws -> ChangeRecord {
        guard !account.name.trimmingCharacters(in: .whitespaces).isEmpty else { throw ManageError.emptyName }
        accounts.append(account)
        var ids: [UUID] = []
        if let openingBalance, openingBalance.cents != 0 {
            let tx = Transaction(date: date, amount: openingBalance, description: "期初余额", accountID: account.id,
                                 category: "期初余额", source: "手记", flow: .opening)
            transactions.append(tx); ids.append(tx.id)
        }
        let extra = openingBalance.map { $0.cents != 0 ? "，现有 \($0.formatted)" : "" } ?? ""
        let change = snapshotChange(.account, "加账户「\(account.name)」\(account.isPrivate ? "（私房钱）" : "")\(extra)", ids: ids,
                                    before: PlanSnapshot(addedAccountIDs: [account.id]), author: author)
        changes.append(change)
        return change
    }

    /// 给新账户起一个不重复的 id。
    public func newAccountID(for name: String) -> String {
        var id = name.lowercased().filter { $0.isASCII && ($0.isLetter || $0.isNumber) }
        if id.isEmpty || accounts.contains(where: { $0.id == id }) { id = "acct-" + UUID().uuidString.prefix(6).lowercased() }
        return id
    }

    /// 改账户：名字、类型、是不是私房钱。
    @discardableResult
    public mutating func updateAccount(_ account: Account, author: String) throws -> ChangeRecord {
        guard let i = accounts.firstIndex(where: { $0.id == account.id }) else { throw EditError.unknownAccount(account.id) }
        guard !account.name.trimmingCharacters(in: .whitespaces).isEmpty else { throw ManageError.emptyName }
        let old = accounts[i]
        guard old != account else { throw ManageError.nothingToChange }
        accounts[i] = account
        let change = snapshotChange(.account, "改账户「\(old.name)」→「\(account.name)」\(account.isPrivate ? "（私房钱）" : "")",
                                    before: PlanSnapshot(accounts: [old]), author: author)
        changes.append(change)
        return change
    }

    /// 删账户。里面还有流水（期初余额不算）就不让删。
    @discardableResult
    public mutating func removeAccount(_ id: String, author: String) throws -> ChangeRecord {
        guard let old = accounts.first(where: { $0.id == id }) else { throw EditError.unknownAccount(id) }
        let inside = transactions.filter { $0.accountID == id }
        let real = inside.filter { $0.flow != .opening }
        guard real.isEmpty else { throw ManageError.accountInUse(old.name, real.count) }
        accounts.removeAll { $0.id == id }
        transactions.removeAll { $0.accountID == id }
        var change = snapshotChange(.remove, "删账户「\(old.name)」", ids: inside.map(\.id),
                                    before: PlanSnapshot(accounts: [old]), previous: inside, author: author)
        if inside.isEmpty { change.kind = .account }
        changes.append(change)
        return change
    }

    @discardableResult
    public mutating func addBook(name: String, author: String) throws -> ChangeRecord {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { throw ManageError.emptyName }
        var id = trimmed.lowercased().filter { $0.isASCII && ($0.isLetter || $0.isNumber) }
        if id.isEmpty || books.contains(where: { $0.id == id }) { id = "book-" + UUID().uuidString.prefix(6).lowercased() }
        books.append(Book(id: id, name: trimmed))
        let change = snapshotChange(.account, "加账本「\(trimmed)」", before: PlanSnapshot(addedBookIDs: [id]), author: author)
        changes.append(change)
        return change
    }

    @discardableResult
    public mutating func renameBook(_ id: String, to name: String, author: String) throws -> ChangeRecord {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { throw ManageError.emptyName }
        guard let i = books.firstIndex(where: { $0.id == id }) else { throw EditError.unknownBook(id) }
        let old = books[i]
        guard old.name != trimmed else { throw ManageError.nothingToChange }
        books[i].name = trimmed
        let change = snapshotChange(.account, "账本「\(old.name)」改名为「\(trimmed)」", before: PlanSnapshot(books: [old]), author: author)
        changes.append(change)
        return change
    }

    // MARK: 借款

    /// 这笔借款名下的所有流水：借出 / 借入那一笔，加上每次还款。
    public func debtTransactionIDs(_ id: UUID) -> [UUID] {
        var ids = changes.filter { $0.debtID == id && $0.kind == .debt && !$0.undone }.flatMap(\.transactionIDs)
        if let d = debts.first(where: { $0.id == id }) { ids += d.repaymentIDs }
        let existing = Set(transactions.map(\.id))
        return ids.filter { existing.contains($0) }
    }

    /// 改借款：对方名字、约定还款日、备注；closed = 不用还了。
    @discardableResult
    public mutating func updateDebt(_ debt: Debt, author: String) throws -> ChangeRecord {
        guard let i = debts.firstIndex(where: { $0.id == debt.id }) else { throw EditError.unknownDebt }
        let old = debts[i]
        guard old != debt else { throw ManageError.nothingToChange }
        debts[i] = debt
        let text = debt.closed && !old.closed ? "「\(debt.counterparty)」的借款结清，剩下的不用还了"
            : !debt.closed && old.closed ? "「\(debt.counterparty)」的借款重新打开" : "改了「\(debt.counterparty)」的借款"
        let change = snapshotChange(.debt, text, before: PlanSnapshot(debts: [old]), author: author)
        changes.append(change)
        return change
    }

    /// 删掉一笔借款，连同它的借出 / 还款流水。
    @discardableResult
    public mutating func removeDebt(_ id: UUID, author: String) throws -> ChangeRecord {
        guard let old = debts.first(where: { $0.id == id }) else { throw EditError.unknownDebt }
        let ids = Set(debtTransactionIDs(id))
        let removed = transactions.filter { ids.contains($0.id) }
        transactions.removeAll { ids.contains($0.id) }
        debts.removeAll { $0.id == id }
        let change = snapshotChange(.remove, "删了和「\(old.counterparty)」的借款 \(old.principal.formatted)", ids: removed.map(\.id),
                                    before: PlanSnapshot(debts: [old]), previous: removed, author: author)
        changes.append(change)
        return change
    }

    // MARK: 分期

    /// 这个分期名下的流水：买的那笔、分期借款那笔、手续费、每期还款。
    public func installmentTransactionIDs(_ id: UUID) -> [UUID] {
        var ids = changes.filter { $0.installmentID == id && $0.kind == .installment && !$0.undone }.flatMap(\.transactionIDs)
        if let inst = installments.first(where: { $0.id == id }) {
            if let p = inst.purchaseID, !ids.contains(p) { ids.append(p) }
            ids += inst.paidIDs
        }
        let existing = Set(transactions.map(\.id))
        return ids.filter { existing.contains($0) }
    }

    /// 删掉一个分期。keepPayments = true 时已经扣的款留在流水里（变回普通支出要自己改），否则一起删。
    @discardableResult
    public mutating func removeInstallment(_ id: UUID, author: String) throws -> ChangeRecord {
        guard let old = installments.first(where: { $0.id == id }) else { throw EditError.unknownInstallment }
        let ids = Set(installmentTransactionIDs(id))
        let removed = transactions.filter { ids.contains($0.id) }
        transactions.removeAll { ids.contains($0.id) }
        installments.removeAll { $0.id == id }
        let change = snapshotChange(.remove, "删了分期「\(old.name)」", ids: removed.map(\.id),
                                    before: PlanSnapshot(installments: [old]), previous: removed, author: author)
        changes.append(change)
        return change
    }

    // MARK: 目标

    /// 改目标：名字、金额、截止日期、锁不锁。
    @discardableResult
    public mutating func updateGoal(_ goal: Goal, author: String) throws -> ChangeRecord {
        guard let i = goals.firstIndex(where: { $0.id == goal.id }) else { throw EditError.unknownGoal }
        guard goal.target.cents > 0 else { throw EditError.amountMustBePositive }
        let old = goals[i]
        guard old != goal else { throw ManageError.nothingToChange }
        goals[i] = goal
        let change = snapshotChange(.goal, "改了目标「\(goal.name)」", before: PlanSnapshot(goals: [old]), author: author)
        changes.append(change)
        return change
    }

    /// 删掉一个目标。在现有账户里「划出」的存入记录一起删（账户余额不变）；专门储蓄账户里的钱和流水不动。
    @discardableResult
    public mutating func removeGoal(_ id: UUID, author: String) throws -> ChangeRecord {
        guard let old = goals.first(where: { $0.id == id }) else { throw EditError.unknownGoal }
        var removed: [Transaction] = []
        if old.savingsAccountID == nil {
            // 划出的每次存取是一出一进两笔，都在存钱的改动记录里。
            let ids = Set(changes.filter { $0.goalID == id && $0.kind == .goalDeposit && !$0.undone }.flatMap(\.transactionIDs))
            removed = transactions.filter { ids.contains($0.id) }
            transactions.removeAll { ids.contains($0.id) }
        }
        goals.removeAll { $0.id == id }
        let change = snapshotChange(.remove, "删了目标「\(old.name)」", ids: removed.map(\.id),
                                    before: PlanSnapshot(goals: [old]), previous: removed.isEmpty ? nil : removed, author: author)
        changes.append(change)
        return change
    }

    // MARK: 撤销时放回去

    mutating func restore(_ s: PlanSnapshot) {
        for a in s.accounts ?? [] {
            if let i = accounts.firstIndex(where: { $0.id == a.id }) { accounts[i] = a } else { accounts.append(a) }
        }
        for b in s.books ?? [] {
            if let i = books.firstIndex(where: { $0.id == b.id }) { books[i] = b } else { books.append(b) }
        }
        for d in s.debts ?? [] {
            if let i = debts.firstIndex(where: { $0.id == d.id }) { debts[i] = d } else { debts.append(d) }
        }
        for x in s.installments ?? [] {
            if let i = installments.firstIndex(where: { $0.id == x.id }) { installments[i] = x } else { installments.append(x) }
        }
        for g in s.goals ?? [] {
            if let i = goals.firstIndex(where: { $0.id == g.id }) { goals[i] = g } else { goals.append(g) }
        }
        for id in s.addedAccountIDs ?? [] where !transactions.contains(where: { $0.accountID == id && $0.flow != .opening }) {
            accounts.removeAll { $0.id == id }
        }
        for id in s.addedBookIDs ?? [] where !transactions.contains(where: { $0.bookID == id }) {
            books.removeAll { $0.id == id }
        }
    }
}
