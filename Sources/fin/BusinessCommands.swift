import ArgumentParser
import FinanceCore
import Foundation

struct BusinessCommand: ParsableCommand {
    static let configuration = CommandConfiguration(commandName: "business", abstract: "查看、打开或关闭生意模式。")
    @Argument var action: String = "status"
    @Option var book: String?
    @OptionGroup var w: WriteOptions
    func run() throws {
        var ledger = try loadLedger()
        switch action {
        case "status":
            if w.json { try Output.json(ledger.business ?? BusinessSettings()) }
            else { print(ledger.business?.enabled == true ? "生意模式已打开 · \(ledger.businessBook?.name ?? "")" : "生意模式已关闭") }
        case "on":
            switch try ledger.enableBusinessMode(choose: book, author: w.who) {
            case .enabled(let change): try finish(ledger, change, w)
            case .needsChoice(let books): throw ValidationError("请用 --book 选择：" + books.map(\.id).joined(separator: "、"))
            }
        case "off":
            let change = ledger.disableBusinessMode(author: w.who)
            try finish(ledger, change, w)
        default: throw ValidationError("可用 status、on、off")
        }
    }
}
struct ProfitCommand: ParsableCommand {
    static let configuration = CommandConfiguration(commandName: "profit", abstract: "查询生意月利润。")
    @Option var month: String
    @Flag var json = false
    func run() throws {
        guard let ym = YearMonth(month) else { throw ValidationError("月份写成 YYYY-MM") }
        let result = try loadLedger().businessReport(month: ym, today: .today)
        if json { try Output.json(result) } else { print("收入 \(result.income.formatted) · 成本 \(result.cost.formatted) · 利润 \(result.profit.formatted)") }
    }
}
struct CapitalCommand: ParsableCommand {
    static let configuration = CommandConfiguration(commandName: "capital", abstract: "查看回本进度，或用 set --total 设置本钱。")
    @Argument var action: String?
    @Option var total: String?
    @Option var openedOn: String?
    @Option var recoveredBefore: String?
    @OptionGroup var w: WriteOptions
    func run() throws {
        var ledger = try loadLedger()
        if action == nil {
            let p = ledger.capitalProgress(today: .today)
            if w.json { try Output.json(p) } else { print(p.map { "已回本 \($0.recovered.formatted) · 还差 \($0.remaining.formatted)" } ?? "尚未设置本钱") }
            return
        }
        guard action == "set", let total else { throw ValidationError("设置本钱用 capital set --total 金额") }
        var capital = ledger.business?.capital ?? Capital(total: .zero)
        capital.total = try parseMoney(total)
        if let openedOn { capital.openedOn = try parseDate(openedOn) }
        if let recoveredBefore { capital.recoveredBefore = try parseMoney(recoveredBefore) }
        let change = try ledger.setCapital(capital, author: w.who)
        try finish(ledger, change, w)
    }
}
