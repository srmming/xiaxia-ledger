import Foundation

/// 迁移：一个目标对一个账户（v3 的规矩）。
/// 老账本里有些目标没有专门的账户，钱是在日常的卡里「划出来」记个数的。迁移就是给这样的目标各开一个存钱罐账户，
/// 把已经划出来的钱真的挪进去。只加账户、加转账、给目标填上账户；不删、不改任何旧流水。
/// 前后保证：每个目标存了多少不变；所有账户余额加起来不变；每一步都记进改动记录（带作者），能一条条撤销。
extension Ledger {
    /// 还没有自己账户的目标。
    public var goalsWithoutOwnAccount: [Goal] { goals.filter { $0.savingsAccountID == nil } }

    /// 和别的目标共用一个账户的目标（按规矩一个账户只能对一个目标；这种不自动拆，列出来让人决定）。
    public var goalsSharingAnAccount: [Goal] {
        let counts = Dictionary(grouping: goals.compactMap(\.savingsAccountID), by: { $0 }).mapValues(\.count)
        return goals.filter { g in g.savingsAccountID.map { (counts[$0] ?? 0) > 1 } ?? false }
    }

    /// 给一个目标填上（或换）专门的账户。能撤销。
    @discardableResult
    public mutating func setGoalAccount(_ id: UUID, accountID: String?, author: String) throws -> ChangeRecord {
        guard let i = goals.firstIndex(where: { $0.id == id }) else { throw EditError.unknownGoal }
        if let accountID {
            try requireAccount(accountID)
            guard !goals.contains(where: { $0.id != id && $0.savingsAccountID == accountID }) else {
                throw BusinessError(message: "这个账户已经是另一个目标的了，一个账户只能对一个目标")
            }
        }
        let old = goals[i]
        guard old.savingsAccountID != accountID else { throw ManageError.nothingToChange }
        goals[i].savingsAccountID = accountID
        let where_ = accountID.flatMap { a in accounts.first { $0.id == a }?.name } ?? "不单独放"
        let change = snapshotChange(.goal, "目标「\(old.name)」的钱放在：\(where_)", before: PlanSnapshot(goals: [old]), author: author)
        changes.append(change)
        return change
    }

    /// 给每个还没有自己账户的目标开一个存钱罐，把已经存的钱挪进去。返回做了哪些改动（没有要迁的就是空的）。
    @discardableResult
    public mutating func giveEveryGoalItsOwnAccount(today: LocalDate = .today, author: String) throws -> [ChangeRecord] {
        var work = self
        var records: [ChangeRecord] = []
        for g in goalsWithoutOwnAccount {
            // 这个目标的钱现在记在哪几个账户里、各多少（存入是正的、取出是负的）
            let ids = work.goalContributionIDs(g)
            var perAccount: [String: Money] = [:]
            for t in work.transactions where ids.contains(t.id) { perAccount[t.accountID, default: .zero] = perAccount[t.accountID, default: .zero] + t.amount }
            let saved = Plans.goals(work).first { $0.id == g.id }?.saved ?? .zero
            var name = TrialBook.jarName(g.name), n = 2
            while work.accounts.contains(where: { $0.name == name }) { name = "\(TrialBook.jarName(g.name)) \(n)"; n += 1 }
            let jar = Account(id: work.newAccountID(for: name), name: name, kind: .savings)
            records.append(try work.createAccount(jar, date: today, author: author))
            // 目标和它的账户算同一边（生意账本的目标，存钱罐算店里的）
            if work.books.first(where: { $0.id == g.bookID })?.isBusiness == true, work.businessBook != nil {
                records.append(try work.setAccountSide(jar.id, side: .business, author: author))
            }
            // 真的把钱挪进去：从原来划出的那几个账户，各挪各的；加起来正好是已经存的
            var left = saved
            for (acc, sum) in perAccount.sorted(by: { $0.key < $1.key }) where sum > .zero && left > .zero {
                let move = min(sum, left)
                records.append(try work.addAccountTransfer(amount: move, from: acc, to: jar.id, date: today, bookID: g.bookID,
                                                            note: "把「\(g.name)」存的钱挪进它自己的存钱罐", author: author))
                left = left - move
            }
            records.append(try work.setGoalAccount(g.id, accountID: jar.id, author: author))
        }
        self = work
        return records
    }
}
