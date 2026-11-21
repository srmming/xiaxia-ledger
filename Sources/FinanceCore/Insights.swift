import Foundation

/// AI 意见：AI（Claude、Codex……）经 MCP / fin 写进账本的本月点评、提醒、建议、好消息。app 只负责显示。
/// 存在单独的 insights 表里；旧版本的 app 和 fin 不认识这张表，会原样留着，不会读坏账本。
public struct Insight: Identifiable, Hashable, Codable, Sendable {
    public enum Kind: String, Codable, Sendable, CaseIterable {
        /// 本月点评：每个月（每个账本）一条，新写的替换旧的。
        case monthlyReview = "review"
        /// 留意（黄）。
        case alert
        /// 建议（靛蓝）。
        case tip
        /// 好消息（绿）。
        case goodNews = "good"
        /// 要处理（红）：超支、信用卡快到期这种真的要动手的事。
        case action

        public var label: String {
            switch self {
            case .monthlyReview: "本月点评"
            case .alert: "留意"
            case .tip: "建议"
            case .goodNews: "好消息"
            case .action: "要处理"
            }
        }
    }

    public var id: UUID
    public var month: YearMonth
    public var bookID: String?
    public var kind: Kind
    /// 一句话结论。
    public var title: String
    /// 两三句解释。
    public var body: String
    /// 关联的东西，比如 "category:超市"、"account:caixa"，app 以后可以点进去。
    public var metric: String?
    public var author: String
    public var createdAt: Date
    public var dismissedAt: Date?

    public init(id: UUID = UUID(), month: YearMonth, bookID: String? = nil, kind: Kind, title: String, body: String,
                metric: String? = nil, author: String, createdAt: Date = Date(), dismissedAt: Date? = nil) {
        self.id = id; self.month = month; self.bookID = bookID; self.kind = kind; self.title = title; self.body = body
        self.metric = metric; self.author = author; self.createdAt = createdAt; self.dismissedAt = dismissedAt
    }

    /// 读到不认识的种类（更新版本写的）当成「建议」，不让整本账打不开。
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        month = try c.decode(YearMonth.self, forKey: .month)
        bookID = try c.decodeIfPresent(String.self, forKey: .bookID)
        kind = Kind(rawValue: (try? c.decode(String.self, forKey: .kind)) ?? "") ?? .tip
        title = try c.decode(String.self, forKey: .title)
        body = try c.decodeIfPresent(String.self, forKey: .body) ?? ""
        metric = try c.decodeIfPresent(String.self, forKey: .metric)
        author = try c.decodeIfPresent(String.self, forKey: .author) ?? "AI"
        createdAt = try c.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date()
        dismissedAt = try c.decodeIfPresent(Date.self, forKey: .dismissedAt)
    }

    enum CodingKeys: String, CodingKey { case id, month, bookID, kind, title, body, metric, author, createdAt, dismissedAt }
}

public enum InsightError: Error, LocalizedError, Equatable {
    case emptyTitle
    case unknownInsight(String)

    public var errorDescription: String? {
        switch self {
        case .emptyTitle: "意见要有一句话的标题。"
        case .unknownInsight(let id): "找不到这条意见：\(id)"
        }
    }
}

extension Ledger {
    /// 某个月的意见：没点「知道了」的在前，新的在前。bookID = nil 时给全部账本的。
    public func insights(month: YearMonth? = nil, bookID: String? = nil, includeDismissed: Bool = false) -> [Insight] {
        insights.filter { i in
            (month == nil || i.month == month) && (bookID == nil || i.bookID == nil || i.bookID == bookID)
                && (includeDismissed || i.dismissedAt == nil)
        }
        .sorted { ($0.kind == .monthlyReview ? 0 : 1, $1.createdAt) < ($1.kind == .monthlyReview ? 0 : 1, $0.createdAt) }
    }

    /// 写一条意见。本月点评每个月、每个账本只留一条：新写的替换旧的。记进改动记录，能撤销。
    @discardableResult
    public mutating func addInsight(_ insight: Insight, author: String) throws -> ChangeRecord {
        guard !insight.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw InsightError.emptyTitle }
        var replaced: [Insight] = []
        if insight.kind == .monthlyReview {
            replaced = insights.filter { $0.kind == .monthlyReview && $0.month == insight.month && $0.bookID == insight.bookID }
            insights.removeAll { $0.kind == .monthlyReview && $0.month == insight.month && $0.bookID == insight.bookID }
        }
        insights.append(insight)
        var snapshot = PlanSnapshot()
        snapshot.insights = replaced
        snapshot.addedInsightIDs = [insight.id]
        let summary = "写了\(insight.month.month) 月\(insight.kind.label)：\(insight.title)"
        var change = ChangeRecord(kind: .edit, summary: summary, transactionIDs: [], author: author)
        change.before = snapshot
        changes.append(change)
        return change
    }

    /// 点「知道了」：这条意见收起来（不删，AI 还能看到你看过了）。
    @discardableResult
    public mutating func dismissInsight(_ id: UUID, author: String) throws -> ChangeRecord {
        guard let i = insights.firstIndex(where: { $0.id == id }) else { throw InsightError.unknownInsight(id.uuidString) }
        var snapshot = PlanSnapshot()
        snapshot.insights = [insights[i]]
        insights[i].dismissedAt = Date()
        var change = ChangeRecord(kind: .edit, summary: "知道了：\(insights[i].title)", transactionIDs: [], author: author)
        change.before = snapshot
        changes.append(change)
        return change
    }

    /// 按 id 或 id 开头几位找意见。
    public func findInsight(_ key: String) -> Insight? {
        let k = key.lowercased()
        return insights.first { $0.id.uuidString.lowercased() == k } ?? {
            let hits = insights.filter { $0.id.uuidString.lowercased().hasPrefix(k) }
            return hits.count == 1 ? hits[0] : nil
        }()
    }
}
