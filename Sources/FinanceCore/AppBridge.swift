import Foundation

/// app 和外面的 AI（经 fin / MCP）之间递小纸条，都放在 Application Support/XiaxiaLedger 里：
/// - now.json：app 现在停在哪一页、哪个月、哪个账本、选中了哪一笔。AI 用 current_view 读，
///   用户说「这笔是什么」时不用复制粘贴，AI 自己知道是哪一笔。
/// - open.json：AI 用 open_in_app 写，app 看到就跳到那一页、那个月，圈出那几笔。
/// 只有页面位置和那一笔的摘要，不放别的账本内容。
public enum AppBridge {
    /// 纸条放在哪：XIAXIA_BRIDGE_DIR 指定了就用它；用 XIAXIA_LEDGER_PATH 换了账本，就放在那个账本旁边（测试账本和真账本分开）；
    /// 否则放 Application Support/XiaxiaLedger。
    public static var folder: URL {
        let env = ProcessInfo.processInfo.environment
        if let d = env["XIAXIA_BRIDGE_DIR"], !d.isEmpty {
            return URL(fileURLWithPath: (d as NSString).expandingTildeInPath)
        }
        if let p = env["XIAXIA_LEDGER_PATH"], !p.isEmpty {
            return URL(fileURLWithPath: (p as NSString).expandingTildeInPath).deletingLastPathComponent()
        }
        return LedgerStores.appSupportFolder
    }

    static var viewURL: URL { folder.appendingPathComponent("now.json") }
    static var openURL: URL { folder.appendingPathComponent("open.json") }

    /// 页面的英文名（给 AI 用）和 app 里的中文名。
    public static let pages: [(key: String, name: String)] = [
        ("overview", "总览"), ("spending", "花销"), ("trends", "趋势"), ("wealth", "家底"), ("plans", "目标"),
        ("subscriptions", "订阅"), ("debts", "欠款与分期"), ("insights", "夏夏建议"), ("changes", "改动记录"), ("transactions", "流水"), ("settings", "设置"),
    ]

    /// 「overview」「总览」都认，返回中文名；认不出返回 nil。
    public static func pageName(_ text: String) -> String? {
        let t = text.trimmingCharacters(in: .whitespaces).lowercased()
        // 「计划」是「目标」以前的名字（2026-11-23 改的），旧的说法也认。
        if t == "计划" { return "目标" }
        return pages.first { $0.key == t || $0.name == t }?.name
    }

    public struct SelectedTransaction: Codable, Hashable, Sendable {
        public var id: UUID
        public var date: String
        public var amount: String
        public var description: String
        public var category: String?
        public var account: String
        public var book: String?
        public init(id: UUID, date: String, amount: String, description: String, category: String?, account: String, book: String?) {
            self.id = id; self.date = date; self.amount = amount; self.description = description
            self.category = category; self.account = account; self.book = book
        }
    }

    /// app 现在停在哪。
    public struct View: Codable, Hashable, Sendable {
        public var page: String
        public var month: String?
        public var bookID: String?
        public var bookName: String
        public var selected: SelectedTransaction?
        public var updatedAt: Date
        public init(page: String, month: String?, bookID: String?, bookName: String, selected: SelectedTransaction?, updatedAt: Date = Date()) {
            self.page = page; self.month = month; self.bookID = bookID; self.bookName = bookName
            self.selected = selected; self.updatedAt = updatedAt
        }

        /// 给 AI 读的一段话。
        public func describe(now: Date = Date()) -> String {
            var lines = ["用户正在看夏夏账本的「\(page)」页" + (month.map { "，\($0)" } ?? "") + "，\(bookName)。"]
            if let s = selected {
                lines.append("选中的那一笔：\(s.date) \(s.description) \(s.amount)，分类 \(s.category ?? "未分类")，账户 \(s.account)"
                             + (s.book.map { "，账本 \($0)" } ?? "") + "（id \(s.id.uuidString)）。")
            }
            let minutes = Int(now.timeIntervalSince(updatedAt) / 60)
            if minutes >= 30 { lines.append("注意：这是 \(minutes) 分钟前的样子，app 可能已经关了或换了页面。") }
            return lines.joined(separator: "\n")
        }
    }

    /// AI 想让 app 跳过去的地方。
    public struct OpenRequest: Codable, Hashable, Sendable {
        public var id: UUID
        public var page: String
        public var month: String?
        public var bookID: String?
        public var transactionIDs: [UUID]
        public var category: String?
        public var note: String?
        public var author: String
        public var createdAt: Date
        public init(id: UUID = UUID(), page: String, month: String? = nil, bookID: String? = nil, transactionIDs: [UUID] = [],
                    category: String? = nil, note: String? = nil, author: String, createdAt: Date = Date()) {
            self.id = id; self.page = page; self.month = month; self.bookID = bookID; self.transactionIDs = transactionIDs
            self.category = category; self.note = note; self.author = author; self.createdAt = createdAt
        }
    }

    static func encoder() -> JSONEncoder {
        let e = JSONEncoder(); e.dateEncodingStrategy = .iso8601; e.outputFormatting = [.prettyPrinted, .sortedKeys]; return e
    }
    static func decoder() -> JSONDecoder { let d = JSONDecoder(); d.dateDecodingStrategy = .iso8601; return d }

    static func write<T: Encodable>(_ value: T, to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try encoder().encode(value).write(to: url, options: .atomic)
    }

    public static func writeView(_ view: View) { try? write(view, to: viewURL) }

    public static func readView() -> View? {
        guard let data = try? Data(contentsOf: viewURL) else { return nil }
        return try? decoder().decode(View.self, from: data)
    }

    public static func requestOpen(_ request: OpenRequest) throws { try write(request, to: openURL) }

    /// app 取走一张跳转纸条（取走就删掉）。太旧的（超过 10 分钟）不跳，免得打开 app 时突然乱跳。
    public static func takeOpenRequest(now: Date = Date()) -> OpenRequest? {
        guard let data = try? Data(contentsOf: openURL) else { return nil }
        try? FileManager.default.removeItem(at: openURL)
        guard let r = try? decoder().decode(OpenRequest.self, from: data), now.timeIntervalSince(r.createdAt) < 600 else { return nil }
        return r
    }

    /// 有没有待取的跳转纸条（app 每两秒看一眼，只看文件在不在）。
    public static var hasOpenRequest: Bool { FileManager.default.fileExists(atPath: openURL.path) }
}
