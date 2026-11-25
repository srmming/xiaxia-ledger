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
    case unknownTransaction(String, Int)
    case transferMismatch
    case unknownInstallment
    case unknownGoal
    case repayTooMuch(String)
    /// 已经有 1 个大目标、3 个小目标了（带上现在这几个的名字）。
    case tooManyGoals([String])

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
        case .unknownTransaction(let key, let n): n == 0 ? "找不到流水 \(key)" : "流水编号 \(key) 对上了 \(n) 笔，多写几位"
        case .transferMismatch: "转账两笔要一笔支出、一笔收入，金额相同"
        case .unknownInstallment: "找不到这个分期"
        case .unknownGoal: "找不到这个目标"
        case .repayTooMuch(let left): "还得比欠的多了，这笔只剩 \(left) 没还"
        case .tooManyGoals(let names):
            "已经有 1 个大目标、3 个小目标了（\(names.map { "「\($0)」" }.joined(separator: "、"))）。目标不在多，在于坚持：先完成或删掉一个再加新的。"
        }
    }
}

extension Ledger {
    func requireBook(_ id: String) throws { guard books.contains(where: { $0.id == id }) else { throw EditError.unknownBook(id) } }
    func requireAccount(_ id: String) throws { guard accounts.contains(where: { $0.id == id }) else { throw EditError.unknownAccount(id) } }

    @discardableResult
    mutating func record(_ kind: ChangeRecord.Kind, _ summary: String, ids: [UUID], author: String) -> ChangeRecord {
        var change = ChangeRecord(kind: kind, summary: summary, transactionIDs: ids, author: author)
        captureTransactionResults(&change)
        changes.append(change)
        return change
    }

    func captureTransactionResults(_ change: inout ChangeRecord) {
        guard !change.transactionIDs.isEmpty, change.kind != .remove else { return }
        let ids = Set(change.transactionIDs)
        change.resultingTransactions = transactions.filter { ids.contains($0.id) }
    }

    // MARK: 流水

    /// 记一笔普通收支。amount 正数 = 收入，负数 = 支出。
    @discardableResult
    public mutating func addTransaction(_ tx: Transaction, author: String) throws -> ChangeRecord {
        try requireAccount(tx.accountID)
        if let b = tx.bookID { try requireBook(b) }
        var tx = tx
        if tx.fx == nil { tx.fx = fxNote(accountID: tx.accountID, date: tx.date) }   // 外币账户：记下当天汇率
        transactions.append(tx)
        return record(.add, "记一笔 \(formatted(tx)) \(tx.description)", ids: [tx.id], author: author)
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
        captureTransactionResults(&change)
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
        if let now = Plans.debts(self, today: date, includeClosed: true).first(where: { $0.id == debtID }), amount > now.outstanding {
            throw EditError.repayTooMuch(now.outstanding.formatted)
        }
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
        let candidates = debts.filter { open.contains($0.id) }
        // 名字完全一样的优先（同时有「阿华」和「阿华2」时，说「阿华」就是阿华）。
        let exact = candidates.filter { $0.counterparty.trimmingCharacters(in: .whitespaces).lowercased() == key }
        return exact.isEmpty ? candidates.filter { $0.counterparty.lowercased().contains(key) } : exact
    }

    // MARK: 分期

    /// 建一个分期：买的那天记一笔全额支出（算支出），同时记一笔同额的「分期借款」进来（往来），账户余额不变。
    /// 之后每期扣款用 payInstallment / linkInstallmentPayment 记成还债，不再算支出。手续费、利息另记一笔普通支出。
    @discardableResult
    public mutating func addInstallment(name: String, bookID: String, accountID: String, total: Money, count: Int,
                                        purchaseDate: LocalDate, firstPayment: LocalDate, category: String? = nil,
                                        fee: Money? = nil, author: String) throws -> (Installment, ChangeRecord) {
        guard total.cents > 0, count > 0 else { throw EditError.amountMustBePositive }
        try requireBook(bookID); try requireAccount(accountID)
        let buy = Transaction(date: purchaseDate, amount: -total, description: name, accountID: accountID, bookID: bookID,
                              category: category, source: "分期购买")
        let loan = Transaction(date: purchaseDate, amount: total, description: "\(name)（分期借款）", accountID: accountID,
                               bookID: bookID, category: "分期", source: "分期购买", flow: .debt)
        var ids = [buy.id, loan.id]
        transactions += [buy, loan]
        if let fee, fee.cents != 0 {
            let f = Transaction(date: purchaseDate, amount: -fee.magnitude, description: "\(name) 分期手续费", accountID: accountID,
                                bookID: bookID, category: "手续费", source: "分期购买")
            transactions.append(f); ids.append(f.id)
        }
        var inst = Installment(name: name, bookID: bookID, accountID: accountID, total: total, count: count, firstDate: firstPayment)
        inst.purchaseID = buy.id
        installments.append(inst)
        var change = ChangeRecord(kind: .installment, summary: "记分期：\(name) \(total.formatted)，分 \(count) 期",
                                  transactionIDs: ids, author: author)
        change.installmentID = inst.id
        captureTransactionResults(&change)
        changes.append(change)
        return (inst, change)
    }

    /// 记一期还款（新记一笔扣款）。
    @discardableResult
    public mutating func payInstallment(_ id: UUID, amount: Money? = nil, date: LocalDate, author: String) throws -> ChangeRecord {
        guard let i = installments.firstIndex(where: { $0.id == id }) else { throw EditError.unknownInstallment }
        let inst = installments[i]
        let pay = (amount ?? inst.perPayment).magnitude
        let n = inst.paidIDs.count + 1
        let tx = Transaction(date: date, amount: -pay, description: "\(inst.name) 第 \(n)/\(inst.count) 期", accountID: inst.accountID,
                             bookID: inst.bookID, category: "分期还款", source: "手记", flow: .debt)
        transactions.append(tx)
        installments[i].paidIDs.append(tx.id)
        var change = ChangeRecord(kind: .installmentPayment, summary: "记分期还款：\(inst.name) 第 \(n)/\(inst.count) 期 \(pay.formatted)",
                                  transactionIDs: [tx.id], author: author)
        change.installmentID = id
        captureTransactionResults(&change)
        changes.append(change)
        return change
    }

    /// 把导入的一笔银行扣款认成某期分期还款：改成「往来」，不再算支出。
    @discardableResult
    public mutating func linkInstallmentPayment(_ id: UUID, transactionID: UUID, author: String) throws -> ChangeRecord {
        guard let i = installments.firstIndex(where: { $0.id == id }) else { throw EditError.unknownInstallment }
        let inst = installments[i]
        let n = inst.paidIDs.count + 1
        installments[i].paidIDs.append(transactionID)
        var change = modify([transactionID], kind: .installmentPayment,
                            summary: "认成分期还款：\(inst.name) 第 \(n)/\(inst.count) 期", author: author) {
            $0.flow = .debt
            $0.bookID = inst.bookID
            if $0.category == nil { $0.category = "分期还款" }
        }
        change.installmentID = id
        changes[changes.count - 1] = change
        return change
    }

    /// 按名字找分期。
    public func findInstallments(named name: String) -> [Installment] {
        let key = name.trimmingCharacters(in: .whitespaces).lowercased()
        return installments.filter { $0.name.lowercased().contains(key) }
    }

    // MARK: 目标和储蓄

    /// 建一个目标。有专门的储蓄账户（如 Revolut 储蓄罐）就挂上，进度 = 那个账户余额；
    /// 没有就在现有账户里「划出」，进度 = 每笔存入累加（2026-11-21 ming 定：两种都支持）。
    /// locked = 锁定储蓄，存进去到期前不能取（宝宝存钱小游戏用）。
    @discardableResult
    /// 同时最多 1 个大目标 + 3 个小目标（存够了的不算），满了抛 tooManyGoals。main = 设成大目标（原来的大目标变小目标）；
    /// 没钉大目标时，目标页把排第一的当大目标（app 引导和 MCP 建第一个目标时会传 main = true）。
    public mutating func addGoal(name: String, bookID: String, target: Money, deadline: LocalDate? = nil,
                                 savingsAccountID: String? = nil, locked: Bool = false, main: Bool = false,
                                 icon: String? = nil, stash: GoalStash? = nil, stashNote: String? = nil,
                                 today: LocalDate = .today, author: String) throws -> (Goal, ChangeRecord) {
        guard target.cents > 0 else { throw EditError.amountMustBePositive }
        try requireBook(bookID)
        if let savingsAccountID { try requireAccount(savingsAccountID) }
        let active = activeGoalIDs()
        guard active.count < Plans.maxActiveGoals else {
            throw EditError.tooManyGoals(goals.filter { active.contains($0.id) }.map(\.name))
        }
        let isMain = main
        // 原来的大目标变小目标；撤销时放回去。
        let unpinned = isMain ? goals.filter(\.pinned) : []
        if isMain { for i in goals.indices { goals[i].pinned = false } }
        let goal = Goal(name: name, bookID: bookID, target: target, deadline: deadline, savingsAccountID: savingsAccountID, locked: locked,
                        pinned: isMain, icon: icon, stash: stash,
                        stashNote: stashNote.flatMap { $0.trimmingCharacters(in: .whitespaces).isEmpty ? nil : $0 }, startedOn: today)
        goals.append(goal)
        var change = ChangeRecord(kind: .goal, summary: "建目标「\(name)」\(target.formatted)\(locked ? "（锁定）" : "")",
                                  transactionIDs: [], author: author)
        if !unpinned.isEmpty { change.saveBefore(PlanSnapshot(goals: unpinned), in: self) }
        change.goalID = goal.id
        captureTransactionResults(&change)
        changes.append(change)
        return (goal, change)
    }

    /// 往目标里存钱。挂了储蓄账户：从 fromAccount 转进储蓄账户（两笔，转进储蓄，不算支出）。
    /// 没挂：在 fromAccount 里划出（一出一进两笔，账户余额不变，存入那笔记进进度）。
    @discardableResult
    /// heldBack = 「忍住了」没买的东西（如「咖啡」）：写进说明和备注，存入那笔带「忍住了」标签，月底数得出来。
    public mutating func deposit(goalID: UUID, amount: Money, fromAccount: String, date: LocalDate, heldBack: String? = nil,
                                 author: String) throws -> ChangeRecord {
        guard amount.cents > 0 else { throw EditError.amountMustBePositive }
        guard let i = goals.firstIndex(where: { $0.id == goalID }) else { throw EditError.unknownGoal }
        try requireAccount(fromAccount)
        let g = goals[i]
        let target = g.savingsAccountID ?? fromAccount
        let held = heldBack.flatMap { $0.trimmingCharacters(in: .whitespaces).isEmpty ? nil : $0.trimmingCharacters(in: .whitespaces) }
        let text = held.map { "忍住了「\($0)」，存进「\(g.name)」" } ?? "存进「\(g.name)」"
        let out = Transaction(date: date, amount: -amount, description: text, accountID: fromAccount, bookID: g.bookID,
                              category: "储蓄", source: "手记", flow: .saving)
        let inn = Transaction(date: date, amount: amount, description: text, accountID: target, bookID: g.bookID,
                              category: "储蓄", source: "手记", flow: .saving, tags: held == nil ? nil : [Plans.heldBackTag])
        transactions += [out, inn]
        goals[i].contributionIDs.append(inn.id)
        var change = ChangeRecord(kind: .goalDeposit, summary: held.map { "忍住了「\($0)」，往「\(g.name)」存 \(amount.formatted)" } ?? "往「\(g.name)」存 \(amount.formatted)",
                                  transactionIDs: [out.id, inn.id], author: author)
        change.goalID = goalID
        changes.append(change)
        return change
    }

    /// 从目标里取钱（存入的反过来）。锁定的目标不能取。
    @discardableResult
    public mutating func withdraw(goalID: UUID, amount: Money, toAccount: String, date: LocalDate, author: String) throws -> ChangeRecord {
        guard amount.cents > 0 else { throw EditError.amountMustBePositive }
        guard let i = goals.firstIndex(where: { $0.id == goalID }) else { throw EditError.unknownGoal }
        let g = goals[i]
        guard !g.locked else { throw EditError.lockedGoal(g.name) }
        try requireAccount(toAccount)
        let source = g.savingsAccountID ?? toAccount
        let out = Transaction(date: date, amount: -amount, description: "从「\(g.name)」取出", accountID: source, bookID: g.bookID,
                              category: "储蓄", source: "手记", flow: .saving)
        let inn = Transaction(date: date, amount: amount, description: "从「\(g.name)」取出", accountID: toAccount, bookID: g.bookID,
                              category: "储蓄", source: "手记", flow: .saving)
        transactions += [out, inn]
        goals[i].contributionIDs.append(out.id)   // 负数那笔，进度会减掉
        var change = ChangeRecord(kind: .goalDeposit, summary: "从「\(g.name)」取出 \(amount.formatted)", transactionIDs: [out.id, inn.id], author: author)
        change.goalID = goalID
        changes.append(change)
        return change
    }

    public func findGoals(named name: String) -> [Goal] {
        let key = name.trimmingCharacters(in: .whitespaces).lowercased()
        return goals.filter { $0.name.lowercased().contains(key) }
    }

    // MARK: 改一笔、删一笔、期初余额

    /// 改一笔流水（金额、说明、日期、账户、账本、分类）。改前的样子存进改动记录，能撤销。
    @discardableResult
    public mutating func editTransaction(_ updated: Transaction, author: String) throws -> ChangeRecord {
        guard transactions.contains(where: { $0.id == updated.id }) else { throw EditError.unknownTransaction(updated.id.uuidString, 0) }
        try requireAccount(updated.accountID)
        if let b = updated.bookID { try requireBook(b) }
        var updated = updated
        // 换了账户或日期：外币汇率按新的重新记（手动 / 按银行改过的汇率，账户没换就留着）。
        if let old = transactions.first(where: { $0.id == updated.id }),
           old.accountID != updated.accountID || (old.date != updated.date && (updated.fx?.source ?? "ecb") == "ecb") {
            updated.fx = fxNote(accountID: updated.accountID, date: updated.date)
        }
        let text = formatted(updated)
        return modify([updated.id], kind: .edit, summary: "改了一笔：\(updated.description) \(text)", author: author) { [updated] in
            $0 = updated
        }
    }

    /// 删一笔流水。删掉的内容存进改动记录，撤销时放回来。借款、分期、目标里引用它的地方一起去掉。
    @discardableResult
    public mutating func removeTransactions(_ ids: [UUID], author: String) throws -> ChangeRecord {
        let set = Set(ids)
        let removed = transactions.filter { set.contains($0.id) }
        guard !removed.isEmpty else { throw EditError.unknownTransaction(ids.first?.uuidString ?? "", 0) }
        transactions.removeAll { set.contains($0.id) }
        for k in debts.indices { debts[k].repaymentIDs.removeAll { set.contains($0) } }
        for k in installments.indices { installments[k].paidIDs.removeAll { set.contains($0) } }
        for k in goals.indices { goals[k].contributionIDs.removeAll { set.contains($0) } }
        let text = removed.count == 1 ? "删了一笔：\(removed[0].description) \(removed[0].amount.formatted)" : "删了 \(removed.count) 笔"
        var change = ChangeRecord(kind: .remove, summary: text, transactionIDs: removed.map(\.id), author: author)
        change.previous = removed
        changes.append(change)
        return change
    }

    /// 开账时的余额：记一笔「期初余额」，不算收入。已经有的话就改成新的金额。
    @discardableResult
    public mutating func setOpeningBalance(accountID: String, amount: Money, date: LocalDate, author: String) throws -> ChangeRecord {
        try requireAccount(accountID)
        let name = accounts.first { $0.id == accountID }?.name ?? accountID
        if let old = transactions.first(where: { $0.accountID == accountID && $0.flow == .opening }) {
            var t = old
            t.amount = amount; t.date = date
            return modify([old.id], kind: .opening, summary: "「\(name)」期初余额改成 \(amount.formatted)", author: author) { $0 = t }
        }
        let tx = Transaction(date: date, amount: amount, description: "期初余额", accountID: accountID, category: "期初余额",
                             source: "手记", flow: .opening)
        transactions.append(tx)
        return record(.opening, "「\(name)」期初余额 \(amount.formatted)", ids: [tx.id], author: author)
    }

    // MARK: 改已有流水

    /// 找流水：完整 id 或前几位（fin tx 里显示的 8 位）。
    public func findTransactions(_ keys: [String]) throws -> [Transaction] {
        try keys.map { key in
            let k = key.lowercased()
            let hits = transactions.filter { $0.id.uuidString.lowercased().hasPrefix(k) }
            guard hits.count == 1 else { throw EditError.unknownTransaction(key, hits.count) }
            return hits[0]
        }
    }

    /// 改一批流水，并把改之前的样子存进改动记录，方便撤销。
    mutating func modify(_ ids: [UUID], kind: ChangeRecord.Kind, summary: String, author: String,
                         _ body: (inout Transaction) -> Void) -> ChangeRecord {
        let set = Set(ids)
        var before: [Transaction] = []
        for k in transactions.indices where set.contains(transactions[k].id) {
            before.append(transactions[k])
            body(&transactions[k])
        }
        var change = ChangeRecord(kind: kind, summary: summary, transactionIDs: ids, author: author)
        change.previous = before
        change.resultingTransactions = transactions.filter { set.contains($0.id) }
        changes.append(change)
        return change
    }

    /// 改分类。
    @discardableResult
    public mutating func categorize(_ ids: [UUID], category: String, author: String) -> ChangeRecord {
        modify(ids, kind: .categorize, summary: "\(ids.count) 笔改成「\(category)」", author: author) { $0.category = category }
    }

    /// 分账本：这几笔属于哪个账本。
    @discardableResult
    public mutating func assignBook(_ ids: [UUID], bookID: String, author: String) throws -> ChangeRecord {
        try requireBook(bookID)
        let name = books.first { $0.id == bookID }?.name ?? bookID
        return modify(ids, kind: .assignBook, summary: "\(ids.count) 笔分到「\(name)」", author: author) { $0.bookID = bookID }
    }

    /// 把已有的两笔标成账本间转账（比如店账户转出、个人账户转入）。金额要一正一负、绝对值相同。
    @discardableResult
    public mutating func linkTransfer(out: UUID, into: UUID, author: String) throws -> ChangeRecord {
        guard let a = transactions.first(where: { $0.id == out }), let b = transactions.first(where: { $0.id == into }) else {
            throw EditError.unknownTransaction(out.uuidString, 0)
        }
        guard a.amount.isExpense, b.amount.isIncome, a.amount.magnitude == b.amount.magnitude else {
            throw EditError.transferMismatch
        }
        let tid = UUID()
        return modify([out, into], kind: .transfer,
                      summary: "标成转账：\(bookName(a.bookID)) → \(bookName(b.bookID)) \(b.amount.formatted)", author: author) {
            $0.transferID = tid
        }
    }

    /// 新记一笔账本间转账：同一个账户里，钱从一个账本挪到另一个（比如店里的现金拿回家用）。
    /// 记两笔，账户余额不变；单个账本照常算，「全部」里抵消。
    @discardableResult
    public mutating func addTransfer(amount: Money, fromBook: String, toBook: String, accountID: String, date: LocalDate,
                                     note: String? = nil, author: String) throws -> ChangeRecord {
        guard amount.cents > 0 else { throw EditError.amountMustBePositive }
        try requireBook(fromBook); try requireBook(toBook); try requireAccount(accountID)
        let tid = UUID()
        let text = note ?? "\(bookName(fromBook)) → \(bookName(toBook))"
        let outTx = Transaction(date: date, amount: -amount, description: text, accountID: accountID, bookID: fromBook,
                                category: books.first(where: { $0.id == fromBook })?.isBusiness == true ? "老板提款" : "转出", transferID: tid, source: "手记")
        let inTx = Transaction(date: date, amount: amount, description: text, accountID: accountID, bookID: toBook,
                               category: "转入", transferID: tid, source: "手记")
        transactions += [outTx, inTx]
        return record(.transfer, "记转账：\(text) \(amount.formatted)", ids: [outTx.id, inTx.id], author: author)
    }

    func bookName(_ id: String?) -> String { books.first { $0.id == id }?.name ?? (id ?? "未分") }

    // MARK: 导入

    /// 导入一批流水：去掉账本里已有的，剩下的加进来，记一条改动记录（整批能撤销）。
    @discardableResult
    public mutating func importTransactions(_ incoming: [Transaction], accountID: String, source: String,
                                            author: String) throws -> (added: [Transaction], duplicates: Int, change: ChangeRecord?) {
        try requireAccount(accountID)
        let fresh = Dedup.newTransactions(incoming, existing: transactions).map { t -> Transaction in
            var c = t
            if c.fx == nil { c.fx = fxNote(accountID: c.accountID, date: c.date) }   // 外币账户：记下当天汇率
            return c
        }
        let dupes = incoming.count - fresh.count
        guard !fresh.isEmpty else { return ([], dupes, nil) }
        transactions += fresh
        if let last = fresh.map(\.date).max(), last > (lastStatementDate[accountID] ?? LocalDate(year: 1, month: 1, day: 1)) {
            lastStatementDate[accountID] = last
        }
        let name = accounts.first { $0.id == accountID }?.name ?? accountID
        let change = record(.importBatch, "导入 \(name) \(fresh.count) 笔（\(source)，跳过重复 \(dupes) 笔）", ids: fresh.map(\.id), author: author)
        return (fresh, dupes, change)
    }

    // MARK: 撤销

    /// 撤销一条改动：新增的流水删掉，改过的流水换回改之前的样子；记欠款的改动连借款一起删。
    @discardableResult
    public mutating func undo(changeID: UUID, author: String) throws -> ChangeRecord {
        guard let i = changes.firstIndex(where: { $0.id == changeID }) else { throw EditError.unknownChange }
        let change = changes[i]
        guard !change.undone else { throw EditError.alreadyUndone }
        guard change.kind != .delete, change.syncConflicts == nil else { throw EditError.notUndoable }
        let reversals = try transactionReversals(for: change, later: changes.suffix(from: i + 1))

        var restoredPlan = change.before
        if let before = change.before {
            if let hashes = change.planFieldHashes {
                restoredPlan = try before.checked(in: self, hashes: hashes).snapshot
                let fields = try before.affectedFields(after: hashes)
                for next in changes.suffix(from: i + 1) where !next.undone {
                    guard let snapshot = next.before, let evidence = next.planFieldHashes else { continue }
                    for (row, changed) in try snapshot.affectedFields(after: evidence) {
                        if let ours = fields[row], ours.contains("*") || changed.contains("*") || !ours.isDisjoint(with: changed) {
                            throw BusinessError(message: "这次改过的字段后来又被修改，无法撤销")
                        }
                    }
                }
            } else if !changes.suffix(from: i + 1).filter({ !$0.undone }).isEmpty {
                throw BusinessError(message: "旧改动缺少字段记录，无法确认撤销是否会覆盖后续改动")
            }
        }
        if let debtID = change.debtID {
            // 还款记录还在时不能先撤销借款本身。
            if let d = debts.first(where: { $0.id == debtID }), !d.repaymentIDs.isEmpty { throw EditError.notUndoable }
            debts.removeAll { $0.id == debtID }
        }
        if let goalID = change.goalID, change.kind == .goal {
            if let g = goals.first(where: { $0.id == goalID }), !g.contributionIDs.isEmpty { throw EditError.notUndoable }
            goals.removeAll { $0.id == goalID }
        }
        if let instID = change.installmentID {
            if change.kind == .installment {
                // 已经有还款时不能先撤销分期本身。
                if let inst = installments.first(where: { $0.id == instID }), !inst.paidIDs.isEmpty { throw EditError.notUndoable }
                installments.removeAll { $0.id == instID }
            } else if let k = installments.firstIndex(where: { $0.id == instID }) {
                let ids = Set(change.transactionIDs)
                installments[k].paidIDs.removeAll { ids.contains($0) }
            }
        }
        if var before = restoredPlan {
            if before.changedBusiness == true {
                guard !changes.dropFirst(i + 1).contains(where: { !$0.undone && $0.before?.changedBusiness == true }) else { throw EditError.notUndoable }
                before.addedBookIDs = before.addedBookIDs?.filter { id in
                    !transactions.contains { $0.bookID == id } && !recurring.contains { $0.template.bookID == id }
                    && !debts.contains { $0.bookID == id } && !goals.contains { $0.bookID == id } && !installments.contains { $0.bookID == id }
                }
            }
            restore(before)
        }
        if change.kind == .remove, let previous = change.previous {
            // 删掉的流水：放回来（借款、分期、目标里的引用不自动恢复，改动记录里写明了）。
            let existing = Set(transactions.map(\.id))
            transactions += previous.filter { !existing.contains($0.id) }
            clearPhoneDeletes(previous.map(\.id))
        } else if let previous = change.previous {
            // 改过的流水：换回原样。
            for k in transactions.indices { if let row = reversals[transactions[k].id] { transactions[k] = row } }
            // 这次改动顺带新加的流水（比如标成转账时补的另一半）：删掉。
            let extra = Set(change.transactionIDs).subtracting(previous.map(\.id))
            if !extra.isEmpty { transactions.removeAll { extra.contains($0.id) } }
        } else {
            let ids = Set(change.transactionIDs)
            transactions.removeAll { ids.contains($0.id) }
            for k in debts.indices { debts[k].repaymentIDs.removeAll { ids.contains($0) } }
            for k in installments.indices { installments[k].paidIDs.removeAll { ids.contains($0) } }
            for k in goals.indices { goals[k].contributionIDs.removeAll { ids.contains($0) } }
        }
        changes[i].undone = true
        return record(.delete, "撤销：\(change.summary)", ids: [], author: author)
    }
}
