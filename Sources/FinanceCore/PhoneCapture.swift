import Foundation

// 手机随手记（2026-11-23 ming：「今天花了10欧,就是一句话」「拍照,比方说 小票」「对这条记录 写入小票或者发票」）：
// - 待记录：手机上说一句 / 拍一张小票，先放进「待记录」，不用填表；回到电脑跟 AI 说「同步今天的」，AI 读出来入账、去重。
// - 小票 / 发票：每笔账可以挂几张图片或 PDF，文件放在账本旁边的「附件」文件夹，跟账本一起走 iCloud。
// - 报销：每笔账可以标「待提交 / 已提交 / 已到账」，报销清单按状态汇总，能导出给公司。
// app、fin、MCP 都只调这里。每次写入记改动记录，能撤销。

// MARK: - 待记录

/// 手机上随手记下、还没入账的一句话或一张小票。
public struct Capture: Identifiable, Hashable, Codable, Sendable {
    public enum Kind: String, Codable, Sendable {
        case text, photo
        public init(from decoder: Decoder) throws {
            self = Kind(rawValue: (try? decoder.singleValueContainer().decode(String.self)) ?? "") ?? .text
        }
    }
    public enum Status: String, Codable, Sendable {
        /// 还没入账
        case pending
        /// 已经入账（或认出是已有的那笔）
        case done
        /// 不记了
        case dismissed
        public init(from decoder: Decoder) throws {
            self = Status(rawValue: (try? decoder.singleValueContainer().decode(String.self)) ?? "") ?? .pending
        }
    }

    public var id: UUID
    public var kind: Kind
    /// 说的那句话；拍小票时是自己补的一句（可以空）。
    public var text: String
    /// 小票照片：附件文件夹里的文件名。
    public var photo: String?
    /// 手机本机先认出来的金额、日期、商户（规则 / 苹果自带文字识别，不联网），只是参考。
    public var guess: CaptureGuess?
    /// 小票上认出来的文字（给电脑上的 AI 参考，照片看不清时也能用）。
    public var recognizedText: String?
    public var createdAt: Date
    /// 在哪台设备上记的：「iPhone」「Mac」。
    public var device: String
    public var status: Status
    /// 入账后对应的流水。
    public var transactionIDs: [UUID]?
    public var resolvedAt: Date?
    public var resolvedBy: String?
    /// 不记的原因，或入账时的说明。
    public var note: String?

    public init(id: UUID = UUID(), kind: Kind, text: String, photo: String? = nil, guess: CaptureGuess? = nil,
                recognizedText: String? = nil, createdAt: Date = Date(), device: String, status: Status = .pending) {
        self.id = id; self.kind = kind; self.text = text; self.photo = photo; self.guess = guess
        self.recognizedText = recognizedText; self.createdAt = createdAt; self.device = device; self.status = status
    }

    /// 记下的那一天（本机时区）。
    public var day: LocalDate {
        let c = Calendar.current.dateComponents([.year, .month, .day], from: createdAt)
        return LocalDate(year: c.year ?? 2026, month: c.month ?? 1, day: c.day ?? 1)
    }

    /// 列表里显示的一句话。
    public var title: String {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if !t.isEmpty { return t }
        if let m = guess?.merchant { return "小票 · \(m)" }
        return "一张小票"
    }
}

/// 手机先猜的：金额（负数 = 花出去）、日期、商户。猜不出来就空着，不硬填。
public struct CaptureGuess: Hashable, Codable, Sendable {
    public var amount: Money?
    public var date: LocalDate?
    public var merchant: String?

    public init(amount: Money? = nil, date: LocalDate? = nil, merchant: String? = nil) {
        self.amount = amount; self.date = date; self.merchant = merchant
    }

    public var isEmpty: Bool { amount == nil && date == nil && merchant == nil }

    // MARK: 一句话

    /// 从一句话里粗略认出金额和日期：「今天午饭 10 欧」「昨天打车花了12,50」「收到工资 1800」。
    /// 只认写得很清楚的；拿不准就空着，最后由电脑上的 AI 定。
    public static func parse(sentence: String, today: LocalDate = .today) -> CaptureGuess {
        var g = CaptureGuess()
        let s = sentence.replacingOccurrences(of: "，", with: " ").replacingOccurrences(of: "。", with: " ")
        // 日期：今天 / 昨天 / 前天；「11月20日」「11-20」「20/11」
        if s.contains("前天") { g.date = today.adding(days: -2) }
        else if s.contains("昨天") || s.lowercased().contains("ayer") || s.lowercased().contains("yesterday") { g.date = today.adding(days: -1) }
        else if s.contains("今天") || s.lowercased().contains("hoy") || s.lowercased().contains("today") { g.date = today }
        if g.date == nil, let d = monthDay(in: s, today: today) { g.date = d }
        // 金额：数字后面跟着「欧 / € / 块 / 元 / eur」或前面有「花了 / 付了 / 收到」的，取第一个。
        if let amount = amountNear(s) {
            let income = ["收到", "收入", "工资", "进账", "退款", "报销到账", "cobr", "ingres", "received", "salary", "refund"]
                .contains { s.lowercased().contains($0) }
            g.amount = income ? amount : -amount
        }
        return g
    }

    private static func amountNear(_ s: String) -> Money? {
        let units = ["欧元", "欧", "€", "eur", "euros", "euro", "块钱", "块", "元", "e "]
        let verbs = ["花了", "花", "付了", "付", "收到", "用了", "交了", "买了", "共", "一共", "总共", "pagué", "paid", "spent"]
        let pattern = #"[0-9]+(?:[.,][0-9]{1,2})?"#
        guard let re = try? NSRegularExpression(pattern: pattern) else { return nil }
        let ns = s as NSString
        let matches = re.matches(in: s, range: NSRange(location: 0, length: ns.length))
        var fallback: Money?
        for m in matches {
            let num = ns.substring(with: m.range)
            let after = ns.substring(from: m.range.location + m.range.length).lowercased().trimmingCharacters(in: .init(charactersIn: " "))
            let before = ns.substring(to: m.range.location).lowercased().trimmingCharacters(in: .whitespaces)
            // 「11月20日」「20号」这种是日期，不是钱
            if after.hasPrefix("月") || after.hasPrefix("日") || after.hasPrefix("号") || after.hasPrefix("点") || after.hasPrefix("/") || after.hasPrefix("-") { continue }
            if before.hasSuffix("月") || before.hasSuffix("/") || before.hasSuffix("-") { continue }
            guard let money = Money(parsing: num), money.cents > 0 else { continue }
            if units.contains(where: { after.hasPrefix($0.trimmingCharacters(in: .whitespaces)) }) || before.hasSuffix("€")
                || verbs.contains(where: { before.hasSuffix($0) }) {
                return money
            }
            if fallback == nil && matches.count == 1 { fallback = money }
        }
        return fallback
    }

    private static func monthDay(in s: String, today: LocalDate) -> LocalDate? {
        let patterns = [#"([0-9]{1,2})月([0-9]{1,2})[日号]?"#]
        for p in patterns {
            guard let re = try? NSRegularExpression(pattern: p),
                  let m = re.firstMatch(in: s, range: NSRange(location: 0, length: (s as NSString).length)) else { continue }
            let ns = s as NSString
            guard let month = Int(ns.substring(with: m.range(at: 1))), let day = Int(ns.substring(with: m.range(at: 2))),
                  (1...12).contains(month), (1...31).contains(day) else { continue }
            var year = today.year
            if LocalDate(year: year, month: month, day: day) > today { year -= 1 }
            return LocalDate(year: year, month: month, day: day)
        }
        return nil
    }

    // MARK: 小票文字

    /// 从小票上认出来的文字里找总金额和日期。手机用苹果自带文字识别（Vision）拿到文字，再交给这里。
    /// 总金额：优先找「TOTAL / IMPORTE / A PAGAR / 合计 / 总计 / 实付」那一行的数；没有就不猜（小票上数字太多，硬猜容易错）。
    /// 日期：dd/mm/yyyy、dd-mm-yy、yyyy-mm-dd，取第一个像日期的。商户：第一行像名字的字。
    public static func parse(receipt text: String, today: LocalDate = .today) -> CaptureGuess {
        var g = CaptureGuess()
        let lines = text.split(whereSeparator: \.isNewline).map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        let totalWords = ["total a pagar", "a pagar", "importe total", "total", "importe", "合计", "总计", "实付", "应付", "amount due", "total eur", "suma"]
        let skipWords = ["subtotal", "sub total", "base imponible", "iva", "tax", "cambio", "change", "entregado", "efectivo", "descuento"]
        let amountRe = try? NSRegularExpression(pattern: #"[0-9]{1,5}(?:[.,][0-9]{3})*[.,][0-9]{2}"#)
        func amounts(_ line: String) -> [Money] {
            guard let re = amountRe else { return [] }
            let ns = line as NSString
            return re.matches(in: line, range: NSRange(location: 0, length: ns.length)).compactMap { Money(parsing: ns.substring(with: $0.range)) }
        }
        outer: for word in totalWords {
            for (i, line) in lines.enumerated() {
                let low = line.lowercased()
                guard low.contains(word), !skipWords.contains(where: { low.contains($0) }) else { continue }
                // 金额可能在同一行，也可能在下一行
                if let m = amounts(line).last ?? (i + 1 < lines.count ? amounts(lines[i + 1]).first : nil), m.cents > 0 {
                    g.amount = -m
                    break outer
                }
            }
        }
        if let re = try? NSRegularExpression(pattern: #"\b([0-9]{4})[-/.]([0-9]{1,2})[-/.]([0-9]{1,2})\b|\b([0-9]{1,2})[-/.]([0-9]{1,2})[-/.]([0-9]{2,4})\b"#) {
            for line in lines {
                let ns = line as NSString
                guard let m = re.firstMatch(in: line, range: NSRange(location: 0, length: ns.length)) else { continue }
                func part(_ i: Int) -> Int? { m.range(at: i).location == NSNotFound ? nil : Int(ns.substring(with: m.range(at: i))) }
                var d: LocalDate?
                if let y = part(1), let mo = part(2), let da = part(3) { d = LocalDate(year: y, month: mo, day: da) }
                else if let da = part(4), let mo = part(5), var y = part(6) {
                    if y < 100 { y += 2000 }
                    d = LocalDate(year: y, month: mo, day: da)    // 西班牙小票：日/月/年
                }
                if let d, (1...12).contains(d.month), (1...31).contains(d.day), d <= today.adding(days: 1), d.year >= today.year - 3 {
                    g.date = d
                    break
                }
            }
        }
        if let first = lines.first(where: { l in
            let letters = l.filter(\.isLetter).count
            return letters >= 3 && letters * 2 >= l.count && amounts(l).isEmpty
                && !["ticket", "factura", "simplificada", "nif", "cif", "tel", "www", "fecha"].contains { l.lowercased().hasPrefix($0) }
        }) {
            g.merchant = String(first.prefix(40))
        }
        return g
    }
}

// MARK: - 小票 / 发票 和 报销

/// 挂在一笔账上的一张小票、发票或别的凭证。文件在账本旁边的「附件」文件夹里。
public struct Attachment: Identifiable, Hashable, Codable, Sendable {
    public enum Kind: String, Codable, Sendable, CaseIterable {
        case receipt, invoice, other
        public init(from decoder: Decoder) throws {
            self = Kind(rawValue: (try? decoder.singleValueContainer().decode(String.self)) ?? "") ?? .other
        }
        public var label: String {
            switch self { case .receipt: "小票"; case .invoice: "发票"; case .other: "凭证" }
        }
    }
    public var id: UUID
    public var kind: Kind
    /// 附件文件夹里的文件名（如 5F3A….jpg）。
    public var file: String
    /// 原来的名字（「发票-11月.pdf」），显示用。
    public var name: String?
    public var addedAt: Date
    public var addedBy: String

    public init(id: UUID = UUID(), kind: Kind, file: String, name: String? = nil, addedAt: Date = Date(), addedBy: String) {
        self.id = id; self.kind = kind; self.file = file; self.name = name; self.addedAt = addedAt; self.addedBy = addedBy
    }

    public var isPDF: Bool { file.lowercased().hasSuffix(".pdf") }
}

/// 报销到哪一步了。
public enum ReimburseStatus: String, Codable, Sendable, CaseIterable {
    /// 不报销（默认）
    case none
    /// 要报销，还没交
    case toSubmit
    /// 交上去了，等钱
    case submitted
    /// 钱到账了
    case paid

    public init(from decoder: Decoder) throws {
        self = ReimburseStatus(rawValue: (try? decoder.singleValueContainer().decode(String.self)) ?? "") ?? .none
    }

    public var label: String {
        switch self { case .none: "不报销"; case .toSubmit: "待提交"; case .submitted: "已提交"; case .paid: "已到账" }
    }
}

/// 一笔账的「纸面材料」：挂的小票 / 发票，和报销状态。按流水 id 单独存一张表（旧版本 app 不认识这张表，会原样留着）。
public struct Paperwork: Identifiable, Hashable, Codable, Sendable {
    /// 就是那笔流水的 id。
    public var id: UUID
    public var attachments: [Attachment]
    public var reimburse: ReimburseStatus
    /// 找谁报销（公司名 / 「Miora」/ 朋友名字）。
    public var reimburseTo: String?
    public var submittedOn: LocalDate?
    public var paidOn: LocalDate?
    /// 报销到账的那笔收入（标「已到账」时可以关联上）。
    public var paidTransactionID: UUID?
    public var note: String?

    public init(id: UUID, attachments: [Attachment] = [], reimburse: ReimburseStatus = .none) {
        self.id = id; self.attachments = attachments; self.reimburse = reimburse
    }

    enum CodingKeys: String, CodingKey { case id, attachments, reimburse, reimburseTo, submittedOn, paidOn, paidTransactionID, note }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        attachments = (try? c.decodeIfPresent([Attachment].self, forKey: .attachments)) ?? []
        reimburse = (try? c.decodeIfPresent(ReimburseStatus.self, forKey: .reimburse)) ?? ReimburseStatus.none
        reimburseTo = try c.decodeIfPresent(String.self, forKey: .reimburseTo)
        submittedOn = try? c.decodeIfPresent(LocalDate.self, forKey: .submittedOn)
        paidOn = try? c.decodeIfPresent(LocalDate.self, forKey: .paidOn)
        paidTransactionID = try? c.decodeIfPresent(UUID.self, forKey: .paidTransactionID)
        note = try c.decodeIfPresent(String.self, forKey: .note)
    }

    public var isEmpty: Bool {
        attachments.isEmpty && reimburse == .none && reimburseTo == nil && note == nil && paidTransactionID == nil
    }
}

/// 报销清单里的一行。
public struct ReimbursementItem: Identifiable, Hashable, Sendable {
    public var id: UUID { transaction.id }
    public let transaction: Transaction
    public let paperwork: Paperwork
}

/// 报销清单按状态的合计。
public struct ReimbursementSummary: Equatable, Sendable {
    public var toSubmit: Money = .zero
    public var submitted: Money = .zero
    public var paid: Money = .zero
    public var counts: [ReimburseStatus: Int] = [:]
    /// 还没拿回来的钱（待提交 + 已提交）。
    public var outstanding: Money { toSubmit + submitted }
}

public enum CaptureError: Error, LocalizedError, Equatable {
    case unknownCapture
    case alreadyHandled
    case unknownTransaction
    case unknownAttachment
    case fileMissing(String)

    public var errorDescription: String? {
        switch self {
        case .unknownCapture: "找不到这条待记录"
        case .alreadyHandled: "这条待记录已经处理过了"
        case .unknownTransaction: "找不到这笔流水"
        case .unknownAttachment: "找不到这张附件"
        case .fileMissing(let p): "找不到文件：\(p)"
        }
    }
}

extension Ledger {
    // MARK: 待记录

    public var pendingCaptures: [Capture] {
        captures.filter { $0.status == .pending }.sorted { $0.createdAt < $1.createdAt }
    }

    /// 记下一句话或一张小票（还没入账）。
    @discardableResult
    public mutating func addCapture(_ capture: Capture, author: String) -> ChangeRecord {
        var snap = PlanSnapshot(); snap.addedCaptureIDs = [capture.id]
        captures.append(capture)
        return recordPlan(.capture, "待记录：\(capture.title)", before: snap, author: author)
    }

    /// 把一条待记录入账：记一笔新的流水；是小票的话照片挂到这笔账上当凭证。
    @discardableResult
    public mutating func resolveCapture(_ id: UUID, as tx: Transaction, author: String) throws -> ChangeRecord {
        guard let i = captures.firstIndex(where: { $0.id == id }) else { throw CaptureError.unknownCapture }
        guard captures[i].status == .pending else { throw CaptureError.alreadyHandled }
        try requireAccount(tx.accountID)
        if let b = tx.bookID { try requireBook(b) }
        var snap = PlanSnapshot(); snap.captures = [captures[i]]
        if let p = paperwork.first(where: { $0.id == tx.id }) { snap.paperwork = [p] } else { snap.addedPaperworkIDs = [tx.id] }
        var tx = tx
        if tx.fx == nil { tx.fx = fxNote(accountID: tx.accountID, date: tx.date) }
        if tx.source == nil { tx.source = "\(captures[i].device) 待记录" }
        transactions.append(tx)
        if let photo = captures[i].photo { appendAttachment(Attachment(kind: .receipt, file: photo, addedBy: author), to: tx.id) }
        captures[i].status = .done
        captures[i].transactionIDs = [tx.id]
        captures[i].resolvedAt = Date(); captures[i].resolvedBy = author
        var change = ChangeRecord(kind: .capture, summary: "待记录入账：\(captures[i].title) → \(formatted(tx)) \(tx.description)",
                                  transactionIDs: [tx.id], author: author)
        change.before = snap
        changes.append(change)
        return change
    }

    /// 这条待记录就是已有的那笔（比如银行流水已经导进来了）：不再新记，标成已处理；小票照片挂到那笔账上。
    @discardableResult
    public mutating func linkCapture(_ id: UUID, to transactionID: UUID, author: String) throws -> ChangeRecord {
        guard let i = captures.firstIndex(where: { $0.id == id }) else { throw CaptureError.unknownCapture }
        guard captures[i].status == .pending else { throw CaptureError.alreadyHandled }
        guard let tx = transactions.first(where: { $0.id == transactionID }) else { throw CaptureError.unknownTransaction }
        var snap = PlanSnapshot(); snap.captures = [captures[i]]
        if let p = paperwork.first(where: { $0.id == transactionID }) { snap.paperwork = [p] } else { snap.addedPaperworkIDs = [transactionID] }
        if let photo = captures[i].photo { appendAttachment(Attachment(kind: .receipt, file: photo, addedBy: author), to: transactionID) }
        captures[i].status = .done
        captures[i].transactionIDs = [transactionID]
        captures[i].resolvedAt = Date(); captures[i].resolvedBy = author
        return recordPlan(.capture, "待记录对上已有的：\(captures[i].title) = \(tx.date) \(formatted(tx)) \(tx.description)", before: snap, author: author)
    }

    /// 不记了（重复的、记错的）。
    @discardableResult
    public mutating func dismissCapture(_ id: UUID, reason: String? = nil, author: String) throws -> ChangeRecord {
        guard let i = captures.firstIndex(where: { $0.id == id }) else { throw CaptureError.unknownCapture }
        guard captures[i].status == .pending else { throw CaptureError.alreadyHandled }
        var snap = PlanSnapshot(); snap.captures = [captures[i]]
        captures[i].status = .dismissed
        captures[i].note = reason
        captures[i].resolvedAt = Date(); captures[i].resolvedBy = author
        return recordPlan(.capture, "待记录不记了：\(captures[i].title)\(reason.map { "（\($0)）" } ?? "")", before: snap, author: author)
    }

    /// 和这条待记录可能是同一笔的已有流水：金额一样、日期前后 3 天内。给 AI 去重用。
    public func possibleMatches(for capture: Capture, days: Int = 3) -> [Transaction] {
        guard let amount = capture.guess?.amount else { return [] }
        let center = capture.guess?.date ?? capture.day
        let lo = center.adding(days: -days), hi = center.adding(days: days)
        let linked = Set(captures.compactMap(\.transactionIDs).flatMap { $0 })
        return transactions.filter { $0.amount == amount && $0.date >= lo && $0.date <= hi && !linked.contains($0.id) }
            .sorted { $0.date < $1.date }
    }

    // MARK: 小票 / 发票

    public func paperwork(for transactionID: UUID) -> Paperwork? { paperwork.first { $0.id == transactionID } }

    mutating func appendAttachment(_ a: Attachment, to transactionID: UUID) {
        if let k = paperwork.firstIndex(where: { $0.id == transactionID }) {
            guard !paperwork[k].attachments.contains(where: { $0.file == a.file }) else { return }
            paperwork[k].attachments.append(a)
        } else {
            paperwork.append(Paperwork(id: transactionID, attachments: [a]))
        }
    }

    /// 给一笔账挂一张小票 / 发票。文件要先放进附件文件夹（LedgerFiles.importAttachment）。
    @discardableResult
    public mutating func attach(_ a: Attachment, to transactionID: UUID, author: String) throws -> ChangeRecord {
        guard let tx = transactions.first(where: { $0.id == transactionID }) else { throw CaptureError.unknownTransaction }
        var snap = PlanSnapshot()
        if let p = paperwork.first(where: { $0.id == transactionID }) { snap.paperwork = [p] } else { snap.addedPaperworkIDs = [transactionID] }
        appendAttachment(a, to: transactionID)
        return recordPlan(.paperwork, "挂\(a.kind.label)：\(tx.date) \(formatted(tx)) \(tx.description)", before: snap, author: author)
    }

    /// 从一笔账上拿掉一张附件（文件本身留在附件文件夹，撤销时还能挂回来）。
    @discardableResult
    public mutating func detach(_ attachmentID: UUID, from transactionID: UUID, author: String) throws -> ChangeRecord {
        guard let k = paperwork.firstIndex(where: { $0.id == transactionID }),
              let a = paperwork[k].attachments.first(where: { $0.id == attachmentID }) else { throw CaptureError.unknownAttachment }
        var snap = PlanSnapshot(); snap.paperwork = [paperwork[k]]
        paperwork[k].attachments.removeAll { $0.id == attachmentID }
        let tx = transactions.first { $0.id == transactionID }
        return recordPlan(.paperwork, "拿掉\(a.kind.label)：\(tx.map { "\($0.date) \($0.description)" } ?? "")", before: snap, author: author)
    }

    // MARK: 报销

    /// 改报销状态。to：找谁报销（不传就不改）；paidTransactionID：报销到账的那笔收入。
    @discardableResult
    public mutating func setReimbursement(_ ids: [UUID], status: ReimburseStatus, to: String? = nil, on date: LocalDate = .today,
                                          paidTransactionID: UUID? = nil, author: String) throws -> ChangeRecord {
        let txs = ids.compactMap { id in transactions.first { $0.id == id } }
        guard !txs.isEmpty, txs.count == ids.count else { throw CaptureError.unknownTransaction }
        var snap = PlanSnapshot()
        snap.paperwork = paperwork.filter { ids.contains($0.id) }
        snap.addedPaperworkIDs = ids.filter { id in !paperwork.contains { $0.id == id } }
        for id in ids {
            let k: Int
            if let found = paperwork.firstIndex(where: { $0.id == id }) { k = found }
            else { paperwork.append(Paperwork(id: id)); k = paperwork.count - 1 }
            paperwork[k].reimburse = status
            if let to { paperwork[k].reimburseTo = to.isEmpty ? nil : to }
            switch status {
            case .none: paperwork[k].submittedOn = nil; paperwork[k].paidOn = nil; paperwork[k].paidTransactionID = nil
            case .toSubmit: paperwork[k].submittedOn = nil; paperwork[k].paidOn = nil
            case .submitted: paperwork[k].submittedOn = paperwork[k].submittedOn ?? date; paperwork[k].paidOn = nil
            case .paid:
                paperwork[k].submittedOn = paperwork[k].submittedOn ?? date
                paperwork[k].paidOn = date
                if let paidTransactionID { paperwork[k].paidTransactionID = paidTransactionID }
            }
        }
        let total = txs.reduce(Money.zero) { $0 + $1.amount.magnitude }
        let what = txs.count == 1 ? "\(txs[0].description)" : "\(txs.count) 笔"
        return recordPlan(.paperwork, "报销「\(status.label)」：\(what) \(total.formatted)\(to.map { $0.isEmpty ? "" : " · 找\($0)" } ?? "")",
                          before: snap, author: author)
    }

    /// 报销清单：标了报销的流水，可按状态筛。新的在前。
    public func reimbursements(_ status: ReimburseStatus? = nil) -> [ReimbursementItem] {
        let byID = Dictionary(transactions.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        return paperwork.filter { $0.reimburse != .none && (status == nil || $0.reimburse == status) }
            .compactMap { p in byID[p.id].map { ReimbursementItem(transaction: $0, paperwork: p) } }
            .sorted { $0.transaction.date > $1.transaction.date }
    }

    public var reimbursementSummary: ReimbursementSummary {
        var s = ReimbursementSummary()
        for item in reimbursements() {
            let m = item.transaction.amount.magnitude
            switch item.paperwork.reimburse {
            case .toSubmit: s.toSubmit = s.toSubmit + m
            case .submitted: s.submitted = s.submitted + m
            case .paid: s.paid = s.paid + m
            case .none: break
            }
            s.counts[item.paperwork.reimburse, default: 0] += 1
        }
        return s
    }

    /// 报销清单导出成 CSV（Excel 能直接打开）：日期、名称、金额、找谁、状态、附件文件名。
    public func reimbursementCSV(_ items: [ReimbursementItem]) -> String {
        func q(_ s: String) -> String { "\"" + s.replacingOccurrences(of: "\"", with: "\"\"") + "\"" }
        var rows = ["日期,名称,金额,找谁报销,状态,提交日期,到账日期,附件"]
        for item in items {
            let t = item.transaction, p = item.paperwork
            rows.append([t.date.description, q(t.description), t.amount.magnitude.decimalString, q(p.reimburseTo ?? ""),
                         p.reimburse.label, p.submittedOn?.description ?? "", p.paidOn?.description ?? "",
                         q(p.attachments.map { $0.name ?? $0.file }.joined(separator: "; "))].joined(separator: ","))
        }
        let total = items.reduce(Money.zero) { $0 + $1.transaction.amount.magnitude }
        rows.append(",合计,\(total.decimalString),,,,,")
        return rows.joined(separator: "\n") + "\n"
    }

    /// 记一条带「之前的样子」的改动。
    mutating func recordPlan(_ kind: ChangeRecord.Kind, _ summary: String, before: PlanSnapshot, author: String) -> ChangeRecord {
        var change = ChangeRecord(kind: kind, summary: summary, transactionIDs: [], author: author)
        change.before = before
        changes.append(change)
        return change
    }
}

// MARK: - 附件文件夹

/// 小票、发票、待记录照片放在账本旁边的「附件」文件夹里，跟着账本一起走 iCloud。
public enum LedgerFiles {
    public static let attachmentsFolderName = "附件"

    /// 账本文件所在的文件夹（内存账本返回 nil）。
    public static func folder(of store: any LedgerStore) -> URL? {
        if let s = store as? PhoneSyncStore { return s.folder }
        if let s = store as? InboxApplyingStore { return folder(of: s.primary) }
        #if canImport(SQLite3)
        if let s = store as? MigratingStore { return s.primary.url.deletingLastPathComponent() }
        if let s = store as? SQLiteLedgerStore { return s.url.deletingLastPathComponent() }
        #endif
        if let s = store as? JSONFileLedgerStore { return s.url.deletingLastPathComponent() }
        return nil
    }

    public static func attachmentsFolder(of store: any LedgerStore) -> URL? {
        folder(of: store)?.appendingPathComponent(attachmentsFolderName, isDirectory: true)
    }

    /// 附件的完整路径。
    public static func url(of file: String, store: any LedgerStore) -> URL? {
        attachmentsFolder(of: store)?.appendingPathComponent(file)
    }

    /// 把一个文件复制进附件文件夹，返回新文件名（uuid + 原扩展名）。原文件不动。
    public static func importAttachment(from source: URL, into folder: URL) throws -> String {
        guard FileManager.default.fileExists(atPath: source.path) else { throw CaptureError.fileMissing(source.path) }
        let ext = source.pathExtension.isEmpty ? "jpg" : source.pathExtension.lowercased()
        let name = "\(UUID().uuidString).\(ext)"
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try coordinatedCopy(from: source, to: folder.appendingPathComponent(name))
        return name
    }

    /// 把一张图片（手机拍的）存进附件文件夹，返回文件名。
    public static func saveAttachment(_ data: Data, ext: String = "jpg", into folder: URL) throws -> String {
        let name = "\(UUID().uuidString).\(ext)"
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try coordinatedWrite(data, to: folder.appendingPathComponent(name))
        return name
    }

    static func coordinatedCopy(from: URL, to: URL) throws {
        #if canImport(Darwin)
        var err: NSError?, inner: Error?
        NSFileCoordinator().coordinate(writingItemAt: to, options: .forReplacing, error: &err) { url in
            do { try FileManager.default.copyItem(at: from, to: url) } catch { inner = error }
        }
        if let e = err ?? inner { throw e }
        #else
        try FileManager.default.copyItem(at: from, to: to)
        #endif
    }

    static func coordinatedWrite(_ data: Data, to: URL) throws {
        #if canImport(Darwin)
        var err: NSError?, inner: Error?
        NSFileCoordinator().coordinate(writingItemAt: to, options: .forReplacing, error: &err) { url in
            do { try data.write(to: url, options: .atomic) } catch { inner = error }
        }
        if let e = err ?? inner { throw e }
        #else
        try data.write(to: to, options: .atomic)
        #endif
    }
}

extension Ledger {
    /// 按 id 前几位找待记录。
    public func findCapture(_ key: String) throws -> Capture {
        let k = key.lowercased()
        let hits = captures.filter { $0.id.uuidString.lowercased().hasPrefix(k) }
        guard hits.count == 1 else { throw CaptureError.unknownCapture }
        return hits[0]
    }
}

/// 给 AI 看的一条待记录（fin phone / MCP phone_notes）。
public struct CaptureBrief: Codable, Sendable {
    public var id: String
    public var kind: String
    public var text: String
    public var recordedAt: String
    public var device: String
    public var guessAmount: String?
    public var guessDate: String?
    public var guessMerchant: String?
    public var recognizedText: String?
    /// 小票照片的完整路径（能看图的 AI 直接打开看）。
    public var photoPath: String?
    /// 金额一样、日期相近的已有流水：可能已经记过（比如银行流水导进来了），先问用户或用 link。
    public var possibleDuplicates: [String]

    public init(_ c: Capture, ledger: Ledger, attachmentsFolder: URL?) {
        id = String(c.id.uuidString.prefix(8)).lowercased()
        kind = c.kind == .photo ? "小票照片" : "一句话"
        text = c.text
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd HH:mm"; f.locale = Locale(identifier: "en_US_POSIX")
        recordedAt = f.string(from: c.createdAt)
        device = c.device
        guessAmount = c.guess?.amount?.formatted
        guessDate = c.guess?.date?.description
        guessMerchant = c.guess?.merchant
        recognizedText = c.recognizedText
        photoPath = c.photo.flatMap { p in attachmentsFolder?.appendingPathComponent(p).path }
        possibleDuplicates = ledger.possibleMatches(for: c).map {
            "\($0.id.uuidString.prefix(8).lowercased()) \($0.date) \($0.amount.formatted) \($0.description)"
        }
    }
}

extension LedgerFiles {
    /// 导出报销清单：在 base 下建「报销清单-日期」文件夹，放报销清单.csv（Excel 能开）和每张凭证的副本。
    /// 返回文件夹和里面的文件（第一个是 CSV）。app 的「导出报销单」和 fin / MCP 都用这个。
    public static func exportReimbursements(_ items: [ReimbursementItem], ledger: Ledger, attachments: URL?,
                                            into base: URL, now: Date = Date()) throws -> (folder: URL, files: [URL]) {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"; f.locale = Locale(identifier: "en_US_POSIX")
        var dir = base.appendingPathComponent("报销清单-\(f.string(from: now))")
        var n = 2
        while FileManager.default.fileExists(atPath: dir.path) {
            dir = base.appendingPathComponent("报销清单-\(f.string(from: now))-\(n)"); n += 1
        }
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let csv = dir.appendingPathComponent("报销清单.csv")
        // 开头加 BOM，Excel 才认得中文。
        try Data(("\u{FEFF}" + ledger.reimbursementCSV(items)).utf8).write(to: csv)
        var files = [csv]
        if let attachments {
            for i in items {
                for (k, a) in i.paperwork.attachments.enumerated() {
                    let ext = (a.file as NSString).pathExtension
                    let name = "\(i.transaction.date)-\(i.transaction.description.prefix(20))-\(a.kind.label)\(k + 1).\(ext)"
                        .replacingOccurrences(of: "/", with: "-").replacingOccurrences(of: ":", with: "-")
                    let target = dir.appendingPathComponent(name)
                    if (try? FileManager.default.copyItem(at: attachments.appendingPathComponent(a.file), to: target)) != nil { files.append(target) }
                }
            }
        }
        return (dir, files)
    }
}
