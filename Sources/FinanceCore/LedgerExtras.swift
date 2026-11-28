import Foundation

// 新界面要用、正式账本以前没有的几样写法：分类的图标和删除、「这家店算哪一类」、删一次估的货值。
// 都记一条带作者的改动，能撤销。老账本没有这些字段，读出来就是没设过。

extension Ledger {
    // MARK: 分类的图标（emoji）

    /// 用户给分类挑的图标：分类名 → emoji。
    public var categoryEmojis: [String: String] {
        var m: [String: String] = [:]
        for c in profile.categories { if let e = c.emoji { m[c.name] = e } }
        return m
    }

    /// 给一个分类换图标（emoji）。传 nil = 改回按名字自动配。已有流水、但不是自己加的分类也行。
    @discardableResult
    public mutating func setCategoryEmoji(_ name: String, emoji: String?, author: String) throws -> ChangeRecord {
        let n = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !n.isEmpty else { throw ManageError.emptyName }
        let e = emoji?.trimmingCharacters(in: .whitespacesAndNewlines)
        let clean = e?.isEmpty == false ? e : nil
        guard categoryEmojis[n] != clean else { throw ManageError.nothingToChange }
        let old = profile
        if let i = profile.categories.firstIndex(where: { $0.name == n }) {
            profile.categories[i].emoji = clean
        } else {
            let income = transactions.first { $0.category == n }.map { $0.amount.isIncome } ?? false
            var c = CustomCategory(name: n, income: income)
            c.emoji = clean
            profile.categories.append(c)
        }
        return appendProfileChange(clean.map { "分类「\(n)」的图标换成 \($0)" } ?? "分类「\(n)」的图标改回自动配", before: old, author: author)
    }

    // MARK: 删分类

    /// 删掉一个分类。它下面的流水挪到 `moveTo`（nil = 变回还没分）。一条改动，撤销时流水和分类一起回来。
    @discardableResult
    public mutating func removeCategory(_ name: String, moveTo: String?, author: String) throws -> ChangeRecord {
        let ids = transactions.filter { $0.category == name }.map(\.id)
        let custom = profile.categories.contains { $0.name == name }
        let ruled = (profile.placeCategories ?? [:]).contains { $0.value == name }
        guard !ids.isEmpty || custom || ruled else { throw ManageError.nothingToChange }
        let target = moveTo?.trimmingCharacters(in: .whitespacesAndNewlines)
        let to = target?.isEmpty == false ? target : nil
        guard to != name else { throw ManageError.nothingToChange }
        let oldProfile = profile
        profile.categories.removeAll { $0.name == name }
        // 「这家店都算这一类」的记法跟着走：挪到别的分类就改成那个，变回还没分就不记了
        if var rules = profile.placeCategories {
            for (place, c) in rules where c == name { rules[place] = to }
            profile.placeCategories = rules.isEmpty ? nil : rules
        }
        let where_ = to.map { "挪到「\($0)」" } ?? "变回还没分"
        if ids.isEmpty { return appendProfileChange("删了分类「\(name)」", before: oldProfile, author: author) }
        var change = modify(ids, kind: .categorize, summary: "删了分类「\(name)」，\(ids.count) 笔\(where_)", author: author) { $0.category = to }
        var snapshot = PlanSnapshot()
        snapshot.profile = oldProfile
        change.saveBefore(snapshot, in: self)
        changes[changes.count - 1] = change
        return change
    }

    // MARK: 这家店算哪一类

    /// 记店名用的钥匙：不分大小写，去掉门店号、日期这些带数字的词。
    public static func placeKey(_ place: String) -> String {
        // 先认出店名（银行流水里「COMPRA TARJ. SUPER LUMI 4821」这种，店名是 Super Lumi）
        let k = Dedup.normalize(Merchant.display(place))
        let loose = Suggester.looseKey(k)
        return loose.isEmpty ? k : loose
    }

    /// 用户定过的：这家店以后都算哪一类。没定过是 nil。
    public func placeCategory(for place: String) -> String? {
        let k = Self.placeKey(place)
        guard !k.isEmpty else { return nil }
        return profile.placeCategories?[k]
    }

    /// 记下「这家店以后都算这一类」。category 传 nil = 忘掉这条。
    @discardableResult
    public mutating func setPlaceCategory(_ place: String, category: String?, author: String) throws -> ChangeRecord {
        let k = Self.placeKey(place)
        guard !k.isEmpty else { throw ManageError.emptyName }
        let c = category?.trimmingCharacters(in: .whitespacesAndNewlines)
        let clean = c?.isEmpty == false ? c : nil
        guard profile.placeCategories?[k] != clean else { throw ManageError.nothingToChange }
        let old = profile
        var rules = profile.placeCategories ?? [:]
        rules[k] = clean
        profile.placeCategories = rules.isEmpty ? nil : rules
        // 定了就不用再问了
        if clean != nil { profile.placeSkipped?.removeAll { $0 == k }; if profile.placeSkipped?.isEmpty == true { profile.placeSkipped = nil } }
        let shown = Merchant.display(place)
        return appendProfileChange(clean.map { "「\(shown)」以后都算「\($0)」" } ?? "不再记「\(shown)」算哪一类", before: old, author: author)
    }

    /// 用户说「不是」：这家店不再问算不算那一类。
    @discardableResult
    public mutating func skipPlaceQuestion(_ place: String, author: String) throws -> ChangeRecord {
        let k = Self.placeKey(place)
        guard !k.isEmpty else { throw ManageError.emptyName }
        guard !(profile.placeSkipped ?? []).contains(k) else { throw ManageError.nothingToChange }
        let old = profile
        profile.placeSkipped = (profile.placeSkipped ?? []) + [k]
        return appendProfileChange("「\(Merchant.display(place))」算哪一类，先不问了", before: old, author: author)
    }

    /// 要问用户的那一句：一笔还没分类的支出，同一家店以前分过类，问「算不算那一类」。一次只问一笔（最近的）。没有可问的返回 nil。
    public struct PlaceQuestion: Equatable, Sendable {
        public var transactionID: UUID
        public var place: String
        public var amount: Money
        public var category: String
    }
    public func placeQuestion(today: LocalDate) -> PlaceQuestion? {
        let skipped = Set(profile.placeSkipped ?? [])
        let biz = Set(books.filter(\.isBusiness).map(\.id))
        let open = transactions.filter { t in
            t.flow == nil && !t.isTransfer && !t.amount.isIncome && t.date <= today
                && (t.category == nil || t.category == "还没分" || t.category == "未分类")
                && !(t.bookID.map(biz.contains) ?? false)
        }.sorted { $0.date > $1.date }
        guard !open.isEmpty else { return nil }
        let known = Suggester(transactions.filter { $0.category != nil && $0.category != "还没分" && $0.category != "未分类" })
        for t in open {
            let k = Self.placeKey(t.description)
            guard !k.isEmpty, !skipped.contains(k) else { continue }
            guard let c = profile.placeCategories?[k] ?? known.guess(t.description).category else { continue }
            return PlaceQuestion(transactionID: t.id, place: Merchant.display(t.description), amount: baseAmount(t).magnitude, category: c)
        }
        return nil
    }

    // MARK: 估的货值

    /// 删掉某一天估的货值。只删那个估的数，流水不动。能撤销。
    @discardableResult
    public mutating func removeStockEstimate(on date: LocalDate, author: String) throws -> ChangeRecord {
        guard var settings = business, businessBook != nil else { throw BusinessError(message: "请先打开生意模式") }
        guard let old = (settings.stockEstimates ?? []).first(where: { $0.date == date }) else { throw ManageError.nothingToChange }
        let rest = (settings.stockEstimates ?? []).filter { $0.date != date }
        settings.stockEstimates = rest.isEmpty ? nil : rest
        return changeBusinessSettings(settings, summary: "删了 \(date.month) 月 \(date.day) 日估的货值 \(old.value.formatted)", author: author)
    }
}

extension TrialBook {
    /// 删掉一个分类。它下面的流水挪到 `moveTo`（默认「还没分」）。「还没分」本身删不掉。
    public mutating func removeCategory(_ name: String, moveTo: String = "还没分") throws {
        guard name != "还没分" else { throw TrialError("「还没分」删不掉，没分类的流水要有个地方放") }
        guard let i = categories.firstIndex(where: { $0.name == name }) else { throw TrialError("没找到「\(name)」这个分类") }
        guard moveTo != name, let target = categories.first(where: { $0.name == moveTo }) else { throw TrialError("选一个别的分类来放这些流水") }
        categories.remove(at: i)
        for k in entries.indices where entries[k].name == name { entries[k].name = target.name; entries[k].emoji = target.emoji }
        for (place, rule) in placeRules where rule.count == 2 && rule[1] == name { placeRules[place] = target.name == "还没分" ? nil : [target.emoji, target.name] }
    }

    /// 删掉店里的一笔欠款（记错了的）。
    public mutating func removeShopDebt(_ id: UUID) throws {
        guard let i = shopDebts.firstIndex(where: { $0.id == id }) else { throw TrialError("这笔欠款已经不在了") }
        shopDebts.remove(at: i)
    }

    /// 删掉一次估的货值。
    public mutating func removeStockEstimate(_ id: UUID) throws {
        guard let i = stockEstimates.firstIndex(where: { $0.id == id }) else { throw TrialError("这次估的已经不在了") }
        stockEstimates.remove(at: i)
    }

    /// 店里的分期还一期：从店里的账户出一期的钱，还剩的少这么多；最后一期还完就是还清了。
    public mutating func payShopInstallment(_ id: UUID, from account: String? = nil) throws {
        guard let i = shopDebts.firstIndex(where: { $0.id == id }) else { throw TrialError("这笔分期已经不在了") }
        guard !shopDebts[i].off, shopDebts[i].amount > .zero else { throw TrialError("这笔已经还清了") }
        guard let per = shopDebts[i].perPayment, per > .zero else { throw TrialError("「\(shopDebts[i].name)」不是一期一期还的") }
        let pay = min(per, shopDebts[i].amount)
        let a = try shopPayAccountIndex(account)
        guard accounts[a].balance >= pay else { throw TrialError("\(accounts[a].name)里只有 \(accounts[a].balance.formatted)") }
        accounts[a].balance = accounts[a].balance - pay
        shopDebts[i].amount = shopDebts[i].amount - pay
        if shopDebts[i].amount == .zero { shopDebts[i].off = true; shopDebts[i].note = "刚还清" }
    }
}
