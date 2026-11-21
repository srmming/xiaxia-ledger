import Foundation

/// 拿到一个对账单文件，先自己看出是哪种格式、哪一列是什么，省得 ming 手填列名。
public enum ImportGuess {
    public enum Format: Equatable, Sendable { case revolut, generic }

    public struct Detected: Equatable, Sendable {
        public var format: Format
        /// 表头在第几行之后（前面是银行抬头、空行）。
        public var skipRows: Int
        public var header: [String]
        public var date: String?
        public var description: String?
        public var amount: String?
        public var debit: String?
        public var credit: String?

        /// 三样（日期、说明、金额）都认出来了，可以直接预览。
        public var isComplete: Bool {
            format == .revolut || (date != nil && description != nil && (amount != nil || debit != nil || credit != nil))
        }
    }

    static let dateWords = ["fecha", "fecha operacion", "fecha valor", "f valor", "date", "completed date", "日期", "data"]
    static let descWords = ["concepto", "descripcion", "movimiento", "description", "detalle", "说明", "摘要", "mas datos", "concepte"]
    static let amountWords = ["importe", "amount", "cantidad", "金额", "import", "importe eur"]
    static let debitWords = ["cargo", "cargos", "debe", "debit", "支出", "gastos"]
    static let creditWords = ["abono", "abonos", "haber", "credit", "收入", "ingresos"]

    static func find(_ header: [String], _ words: [String]) -> String? {
        let norm = header.map { Dedup.normalize($0) }
        for w in words { if let i = norm.firstIndex(of: w) { return header[i] } }
        for w in words { if let i = norm.firstIndex(where: { $0.hasPrefix(w) }) { return header[i] } }
        return nil
    }

    public static func detect(_ text: String) -> Detected {
        let rows = CSV.parse(text)
        // Revolut：表头里有 Started Date / Completed Date。
        if let first = rows.first, first.contains(where: { $0.caseInsensitiveCompare("Completed Date") == .orderedSame }),
           first.contains(where: { $0.caseInsensitiveCompare("Amount") == .orderedSame }) {
            return Detected(format: .revolut, skipRows: 0, header: first)
        }
        // 其他银行：前 20 行里找第一行同时有「日期」和「金额 / 支出 / 收入」样子的列名。
        for (n, row) in rows.prefix(20).enumerated() {
            let date = find(row, dateWords)
            let amount = find(row, amountWords), debit = find(row, debitWords), credit = find(row, creditWords)
            if date != nil, amount != nil || debit != nil || credit != nil {
                return Detected(format: .generic, skipRows: n, header: row.filter { !$0.isEmpty }, date: date,
                                description: find(row, descWords), amount: amount,
                                debit: amount == nil ? debit : nil, credit: amount == nil ? credit : nil)
            }
        }
        return Detected(format: .generic, skipRows: 0, header: (rows.first ?? []).filter { !$0.isEmpty })
    }

    /// 按文件名和内容猜是哪个账户的对账单。
    public static func account(fileName: String, text: String, accounts: [Account]) -> String? {
        let name = Dedup.normalize(fileName)
        for a in accounts {
            let keys = [a.name, a.institution ?? "", a.id].map { Dedup.normalize($0) }.filter { $0.count >= 3 }
            if keys.contains(where: { name.contains($0) }) { return a.id }
        }
        return nil
    }
}
