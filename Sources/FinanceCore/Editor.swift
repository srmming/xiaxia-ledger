import Foundation

/// 所有写入都走这里：app 和 fin 共用一套规则。每次写入记一条改动记录（写明作者），能撤销。
public enum EditError: Error, LocalizedError, Equatable {
    case unknownBook(String)
    case unknownAccount(String)
    case unknownDebt
    case unknownChange
    case alreadyUndone
    case notUndoable
    case amountMustBePositive
    case lockedGoal(String)

    public var errorDescription: String? {
        switch self {
        case .unknownBook(let id): "没有这个账本：\(id)"
        case .unknownAccount(let id): "没有这个账户：\(id)"
        case .unknownDebt: "找不到这笔借款"
        case .unknownChange: "找不到这条改动记录"
        case .alreadyUndone: "这条改动已经撤销过了"
        case .notUndoable: "这条改动后面还有依赖它的改动，先撤销后面的"
        case .amountMustBePositive: "金额要大于 0"
        case .lockedGoal(let name): "「\(name)」是锁定的储蓄，到期前不能动"
        }
    }
}

extension Ledger {
    func requireBook(_ id: String) throws { guard books.contains(where: { $0.id == id }) else { throw EditError.unknownBook(id) } }
    func requireAccount(_ id: String) throws { guard accounts.contains(where: { $0.id == id }) else { throw EditError.unknownAccount(id) } }

    @discardableResult
    mutating func record(_ kind: ChangeRecord.Kind, _ summary: String, ids: [UUID], author: String) -> ChangeRecord {
        let change = ChangeRecord(kind: kind, summary: summary, transactionIDs: ids, author: author)
        changes.append(change)
        return change
    }

    // MARK: 流水

    /// 记一笔普通收支。amount 正数 = 收入，负数 = 支出。
    @discardableResult
    public mutating func addTransaction(_ tx: Transaction, author: String) throws -> ChangeRecord {
        try requireAccount(tx.accountID)
        if let b = tx.bookID { try requireBook(b) }
        transactions.append(tx)
        return record(.add, "记一笔 \(tx.amount.formatted) \(tx.description)", ids: [tx.id], author: author)
    }

    // MARK: 账户

    @discardableResult
    public mutating func addAccount(_ account: Account, author: String) -> ChangeRecord {
        accounts.append(account)
        return record(.account, "加账户「\(account.name)」\(account.isPrivate ? "（私房钱）" : "")", ids: [], author: author)
    }

    /// 私房钱账户。app 默认把它们从总览、余额合计里拿掉。
    public var privateAccountIDs: Set<String> { Set(accounts.filter(\.isPrivate).map(\.id)) }

    // MARK: 借款往来

    /// 记一笔欠款。accountID 有值时同时记一笔「往来」流水（借出 = 钱出去，借入 = 钱进来）；
    /// 很早以前的旧账没有对应流水时可以不填。
    @discardableResult
    public mutating func addDebt(counterparty: String, direction: Debt.Direction, amount: Money, bookID: String,
                                 date: LocalDate, accountID: String?, dueDate: LocalDate? = nil, note: String? = nil,
                                 author: String) throws -> (Debt, ChangeRecord) {
        guard amount.cents > 0 else { throw EditError.amountMustBePositive }
        try requireBook(bookID)
        var ids: [UUID] = []
        if let accountID {
            try requireAccount(accountID)
            let signed = direction == .theyOweMe ? -amount : amount
            let tx = Transaction(date: date, amount: signed, description: direction == .theyOweMe ? "借给\(counterparty)" : "向\(counterparty)借",
                                 accountID: accountID, bookID: bookID, category: "借款往来", source: "手记", flow: .debt)
            transactions.append(tx); ids.append(tx.id)
        }
        let debt = Debt(counterparty: counterparty, direction: direction, principal: amount, bookID: bookID,
                        startDate: date, dueDate: dueDate, note: note)
        debts.append(debt)
        let text = direction == .theyOweMe ? "\(counterparty) 欠我 \(amount.formatted)" : "我欠 \(counterparty) \(amount.formatted)"
        var change = ChangeRecord(kind: .debt, summary: "记欠款：\(text)", transactionIDs: ids, author: author)
        change.debtID = debt.id
        changes.append(change)
        return (debt, change)
    }

    /// 记一笔还款：别人还我（钱进来），或我还别人（钱出去）。也记成「往来」，不算收支。
    @discardableResult
    public mutating func repay(debtID: UUID, amount: Money, date: LocalDate, accountID: String,
                               author: String) throws -> ChangeRecord {
        guard amount.cents > 0 else { throw EditError.amountMustBePositive }
        guard let i = debts.firstIndex(where: { $0.id == debtID }) else { throw EditError.unknownDebt }
        try requireAccount(accountID)
        let d = debts[i]
        let signed = d.direction == .theyOweMe ? amount : -amount
        let tx = Transaction(date: date, amount: signed,
                             description: d.direction == .theyOweMe ? "\(d.counterparty)还款" : "还\(d.counterparty)",
                             accountID: accountID, bookID: d.bookID, category: "借款往来", source: "手记", flow: .debt)
        transactions.append(tx)
        debts[i].repaymentIDs.append(tx.id)
        let left = Plans.debts(self, today: date, includeClosed: true).first { $0.id == debtID }?.outstanding ?? .zero
        let text = d.direction == .theyOweMe ? "\(d.counterparty) 还我 \(amount.formatted)" : "还 \(d.counterparty) \(amount.formatted)"
        return record(.repay, "记还款：\(text)，还欠 \(left.formatted)", ids: [tx.id], author: author)
    }

    /// 按名字找没结清的借款（AI 说「阿华还了我 100」时用）。
    public func openDebts(named name: String) -> [Debt] {
        let key = name.trimmingCharacters(in: .whitespaces).lowercased()
        let open = Set(Plans.debts(self, today: .today).map(\.id))
        return debts.filter { open.contains($0.id) && $0.counterparty.lowercased().contains(key) }
    }

    // MARK: 撤销

    /// 撤销一条改动：删掉它新增的流水；记欠款的改动连借款一起删。
    @discardableResult
    public mutating func undo(changeID: UUID, author: String) throws -> ChangeRecord {
        guard let i = changes.firstIndex(where: { $0.id == changeID }) else { throw EditError.unknownChange }
        let change = changes[i]
        guard !change.undone else { throw EditError.alreadyUndone }
        if let debtID = change.debtID {
            // 还款记录还在时不能先撤销借款本身。
            if let d = debts.first(where: { $0.id == debtID }), !d.repaymentIDs.isEmpty { throw EditError.notUndoable }
            debts.removeAll { $0.id == debtID }
        }
        let ids = Set(change.transactionIDs)
        transactions.removeAll { ids.contains($0.id) }
        for k in debts.indices { debts[k].repaymentIDs.removeAll { ids.contains($0) } }
        for k in installments.indices { installments[k].paidIDs.removeAll { ids.contains($0) } }
        for k in goals.indices { goals[k].contributionIDs.removeAll { ids.contains($0) } }
        changes[i].undone = true
        return record(.delete, "撤销：\(change.summary)", ids: [], author: author)
    }
}
