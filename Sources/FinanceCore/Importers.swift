import Foundation

/// 对账单导入：把银行导出的文件读成流水。只负责「读」，写进账本走 `Ledger.importTransactions`（会去重、记改动记录）。
public struct ImportResult: Sendable {
    public var transactions: [Transaction]
    /// 没读进来的行和原因（比如外币、未完成的交易），给 AI 在对话里跟 ming 说清楚。
    public var skipped: [String]
}

public enum ImportError: Error, LocalizedError, Equatable {
    case empty
    case missingColumn(String)
    case badRow(Int, String)

    public var errorDescription: String? {
        switch self {
        case .empty: "文件是空的"
        case .missingColumn(let c): "找不到「\(c)」这一列，可能不是这种格式的对账单"
        case .badRow(let n, let why): "第 \(n) 行读不懂：\(why)"
        }
    }
}

public enum CSV {
    /// 读 CSV：支持引号、引号里的逗号和换行。分隔符自动判断（逗号、分号、制表符）。
    public static func parse(_ text: String, delimiter: Character? = nil) -> [[String]] {
        let body = text.hasPrefix("\u{FEFF}") ? String(text.dropFirst()) : text
        let firstLine = body.prefix { $0 != "\n" && $0 != "\r" }
        let candidates: [Character] = [",", ";", "\t"]
        let sep = delimiter ?? candidates.max { a, b in
            firstLine.filter { $0 == a }.count < firstLine.filter { $0 == b }.count
        } ?? ","
        var rows: [[String]] = []
        var row: [String] = []
        var field = ""
        var inQuotes = false
        var it = body.makeIterator()
        var pending: Character? = nil
        while let c = pending ?? it.next() {
            pending = nil
            if inQuotes {
                if c == "\"" {
                    if let n = it.next() {
                        if n == "\"" { field.append("\"") } else { inQuotes = false; pending = n }
                    } else { inQuotes = false }
                } else { field.append(c) }
            } else if c == "\"" {
                inQuotes = true
            } else if c == sep {
                row.append(field); field = ""
            } else if c == "\n" || c == "\r" || c == "\r\n" {
                row.append(field); field = ""
                if row.contains(where: { !$0.isEmpty }) { rows.append(row) }
                row = []
            } else {
                field.append(c)
            }
        }
        row.append(field)
        if row.contains(where: { !$0.isEmpty }) { rows.append(row) }
        return rows.map { $0.map { $0.trimmingCharacters(in: .whitespaces) } }
    }
}

/// 日期：支持 2026-11-03、2026-11-03 14:22:10、03/11/2026、03-11-2026、03.11.2026（日在前，西班牙习惯）。
public func parseStatementDate(_ raw: String) -> LocalDate? {
    let s = raw.trimmingCharacters(in: .whitespaces)
    if s.count >= 10, let d = LocalDate(String(s.prefix(10))) { return d }
    let parts = s.prefix(10).split(whereSeparator: { $0 == "/" || $0 == "-" || $0 == "." }).compactMap { Int($0) }
    guard parts.count == 3 else { return nil }
    let (day, month, yearRaw) = (parts[0], parts[1], parts[2])
    let year = yearRaw < 100 ? 2000 + yearRaw : yearRaw
    guard (1...12).contains(month), (1...31).contains(day) else { return nil }
    return LocalDate(year: year, month: month, day: day)
}

public enum Importers {
    /// Revolut 导出的 CSV：Type, Product, Started Date, Completed Date, Description, Amount, Fee, Currency, State, Balance。
    /// 只读已完成（COMPLETED）的欧元交易；手续费算进金额里。
    public static func revolutCSV(_ text: String, accountID: String, source: String) throws -> ImportResult {
        let rows = CSV.parse(text, delimiter: ",")
        guard let header = rows.first else { throw ImportError.empty }
        func col(_ name: String) throws -> Int {
            guard let i = header.firstIndex(where: { $0.caseInsensitiveCompare(name) == .orderedSame }) else {
                throw ImportError.missingColumn(name)
            }
            return i
        }
        let cDate = try col("Completed Date"), cStart = try col("Started Date"), cDesc = try col("Description")
        let cAmount = try col("Amount"), cFee = header.firstIndex(of: "Fee"), cCur = header.firstIndex(of: "Currency")
        let cState = header.firstIndex(of: "State"), cType = header.firstIndex(of: "Type")
        var txs: [Transaction] = [], skipped: [String] = []
        for (n, r) in rows.dropFirst().enumerated() {
            let line = n + 2
            func at(_ i: Int?) -> String { i.flatMap { $0 < r.count ? r[$0] : nil } ?? "" }
            let state = at(cState).uppercased()
            if !state.isEmpty && state != "COMPLETED" { skipped.append("第 \(line) 行 \(at(cDesc))：状态 \(state)，没完成"); continue }
            let currency = at(cCur).uppercased()
            if !currency.isEmpty && currency != "EUR" { skipped.append("第 \(line) 行 \(at(cDesc))：外币 \(currency)"); continue }
            guard let date = parseStatementDate(at(cDate).isEmpty ? at(cStart) : at(cDate)) else {
                throw ImportError.badRow(line, "日期「\(at(cDate))」")
            }
            guard let amount = Money(parsing: at(cAmount)) else { throw ImportError.badRow(line, "金额「\(at(cAmount))」") }
            let fee = Money(parsing: at(cFee)) ?? .zero
            let type = at(cType).uppercased()
            txs.append(Transaction(date: date, amount: amount - fee.magnitude, description: at(cDesc), accountID: accountID,
                                   category: type == "TOPUP" ? "充值" : nil, source: source,
                                   // 充值是自己别的卡转进 Revolut 的钱，不是收入。
                                   flow: type == "TOPUP" ? .move : nil))
        }
        return ImportResult(transactions: txs, skipped: skipped)
    }

    /// 通用 CSV：指定日期、金额、说明三列（列名或从 1 开始的列号）。
    /// 银行把收支分成两列时，用 debit / credit 代替 amount（支出列取负）。
    public struct ColumnMap: Sendable {
        public var date: String
        public var amount: String?
        public var debit: String?
        public var credit: String?
        public var description: String
        public var skipRows: Int
        /// 可选：分类、账本、性质三列。从别的记账工具（如 Notion 表格）搬过来时用，
        /// 性质写 debt / saving / opening（或「往来」「储蓄」「期初」），空着就是普通收支。
        public var category: String?
        public var book: String?
        public var flow: String?
        public init(date: String, amount: String? = nil, debit: String? = nil, credit: String? = nil,
                    description: String, skipRows: Int = 0,
                    category: String? = nil, book: String? = nil, flow: String? = nil) {
            self.date = date; self.amount = amount; self.debit = debit; self.credit = credit
            self.description = description; self.skipRows = skipRows
            self.category = category; self.book = book; self.flow = flow
        }
    }

    public static func genericCSV(_ text: String, map: ColumnMap, accountID: String, source: String) throws -> ImportResult {
        let rows = Array(CSV.parse(text).dropFirst(map.skipRows))
        guard let header = rows.first else { throw ImportError.empty }
        func col(_ key: String?) throws -> Int? {
            guard let key else { return nil }
            if let n = Int(key), n >= 1 { return n - 1 }
            guard let i = header.firstIndex(where: { Dedup.normalize($0) == Dedup.normalize(key) }) else {
                throw ImportError.missingColumn(key)
            }
            return i
        }
        let cDate = try col(map.date)!, cDesc = try col(map.description)!
        let cAmount = try col(map.amount), cDebit = try col(map.debit), cCredit = try col(map.credit)
        guard cAmount != nil || cDebit != nil || cCredit != nil else { throw ImportError.missingColumn("金额") }
        let cCategory = try col(map.category), cBook = try col(map.book), cFlow = try col(map.flow)
        var txs: [Transaction] = [], skipped: [String] = []
        for (n, r) in rows.dropFirst().enumerated() {
            let line = n + 2 + map.skipRows
            func at(_ i: Int?) -> String { i.flatMap { $0 < r.count ? r[$0] : nil } ?? "" }
            guard let date = parseStatementDate(at(cDate)) else {
                skipped.append("第 \(line) 行：日期「\(at(cDate))」读不懂，可能是合计行"); continue
            }
            var amount: Money?
            if cAmount != nil { amount = Money(parsing: at(cAmount)) }
            else {
                let d = Money(parsing: at(cDebit)), c = Money(parsing: at(cCredit))
                if let d, d.cents != 0 { amount = -d.magnitude } else if let c { amount = c.magnitude }
            }
            guard let amount else { throw ImportError.badRow(line, "金额读不出来") }
            var flow: Transaction.Flow?
            if cFlow != nil {
                switch at(cFlow).trimmingCharacters(in: .whitespaces).lowercased() {
                case "": flow = nil
                case "debt", "往来", "借款往来": flow = .debt
                case "saving", "储蓄": flow = .saving
                case "opening", "期初", "开账": flow = .opening
                case let other:
                    guard let f = Transaction.Flow(rawValue: other) else {
                        throw ImportError.badRow(line, "性质「\(other)」看不懂，只能是 debt / saving / opening 或空着")
                    }
                    flow = f
                }
            }
            func optional(_ i: Int?) -> String? {
                let v = at(i).trimmingCharacters(in: .whitespaces)
                return v.isEmpty ? nil : v
            }
            txs.append(Transaction(date: date, amount: amount, description: at(cDesc), accountID: accountID,
                                   bookID: optional(cBook), category: optional(cCategory), source: source, flow: flow))
        }
        return ImportResult(transactions: txs, skipped: skipped)
    }
}
