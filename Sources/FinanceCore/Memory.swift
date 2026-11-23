import Foundation

/// 夏夏的记忆：让 app 和连上的 AI 越用越懂用户的财务。跟着账本走（同一个文件、一起同步），不放到别处。
///
/// 照 Notion 记忆的做法分层（2026-11-23 ming 定）：
/// - **我的规矩**（rule）：高频、确定的约定，比如「转给妈妈的钱不算支出」「我说收益是指店里赚的」。条数少，AI 每次都读全文。
/// - **记得的事**（topic）：一件事一条，标题写话题不写结论（「工资」，不是「工资 1.380 €」）。AI 每次只看目录，聊到了才把那条读出来。
/// - **做事经验**（lesson）：上次怎么做的、踩过什么坑，标题是任务名（「导入对账单」「对账」）。AI 做那类事之前先读。
/// - 经历不单独存：挂在每一行后面（当时出了什么事 story、用户原话 quote），当这条为什么这么记的证据。
///
/// 规矩：先搜再记，同一件事只留一条；能从流水算出来的数字不记（现算，见 Regulars）；卡号、密码不记；
/// 「删掉」能撤销，「忘掉」连改动记录里的痕迹一起抹掉。不用向量：条数少，目录直接给 AI 看，再加关键词搜索。
public struct Memory: Identifiable, Hashable, Codable, Sendable {
    public enum Kind: String, Codable, Sendable, CaseIterable {
        case rule, topic, lesson

        public var label: String {
            switch self {
            case .rule: "我的规矩"
            case .topic: "记得的事"
            case .lesson: "做事经验"
            }
        }

        /// 读到不认识的（更新版本加的）当成「记得的事」，不让整本账打不开。
        public init(from decoder: Decoder) throws {
            self = Kind(rawValue: (try? decoder.singleValueContainer().decode(String.self)) ?? "") ?? .topic
        }
    }

    /// 这一行是怎么来的。
    public enum Source: String, Codable, Sendable, CaseIterable {
        /// 用户在对话里亲口说的。
        case said
        /// 用户纠正了 AI（或改了 AI 记的东西）。
        case corrected
        /// AI 从流水里看出来、问过用户、用户说对。
        case confirmed
        /// AI 自己看出来的，还没问过用户（做事经验可以直接这样记）。
        case observed
        /// 用户自己在 app 里写的。
        case written

        public var label: String {
            switch self {
            case .said: "你说的"
            case .corrected: "你纠正的"
            case .confirmed: "夏夏看出来的，你确认过"
            case .observed: "夏夏看出来的"
            case .written: "你自己写的"
            }
        }

        public init(from decoder: Decoder) throws {
            self = Source(rawValue: (try? decoder.singleValueContainer().decode(String.self)) ?? "") ?? .said
        }
    }

    /// 话题下面的一行。
    public struct Note: Identifiable, Hashable, Codable, Sendable {
        public var id: UUID
        /// 记住的那句话，一句说清，单独看也看得懂。
        public var text: String
        public var source: Source
        /// 用户的原话（有就留着，分清「原话」和「AI 的理解」）。
        public var quote: String?
        /// 当时出了什么事（踩的坑、怎么解决的）。
        public var story: String?
        /// 哪天说的 / 发生的。
        public var date: LocalDate
        /// 谁记下的：「你」的名字、Claude、Codex……
        public var author: String
        public var createdAt: Date
        /// 改过的话，最后一次是谁、什么时候。
        public var editedBy: String?
        public var editedAt: Date?
        /// 到这天该回头看一眼还对不对（「明年 3 月退健身房」就填 3 月底）。过了这天，每月整理时会列出来。
        public var reviewOn: LocalDate?

        public init(id: UUID = UUID(), text: String, source: Source = .said, quote: String? = nil, story: String? = nil,
                    date: LocalDate = .today, author: String, createdAt: Date = Date(), reviewOn: LocalDate? = nil) {
            self.id = id; self.text = text; self.source = source; self.quote = quote; self.story = story
            self.date = date; self.author = author; self.createdAt = createdAt; self.reviewOn = reviewOn
        }

        enum CodingKeys: String, CodingKey { case id, text, source, quote, story, date, author, createdAt, editedBy, editedAt, reviewOn }

        public init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            id = try c.decode(UUID.self, forKey: .id)
            text = try c.decodeIfPresent(String.self, forKey: .text) ?? ""
            source = try c.decodeIfPresent(Source.self, forKey: .source) ?? .said
            quote = try c.decodeIfPresent(String.self, forKey: .quote)
            story = try c.decodeIfPresent(String.self, forKey: .story)
            createdAt = try c.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date()
            date = try c.decodeIfPresent(LocalDate.self, forKey: .date) ?? .today
            author = try c.decodeIfPresent(String.self, forKey: .author) ?? "AI"
            editedBy = try c.decodeIfPresent(String.self, forKey: .editedBy)
            editedAt = try c.decodeIfPresent(Date.self, forKey: .editedAt)
            reviewOn = try c.decodeIfPresent(LocalDate.self, forKey: .reviewOn)
        }
    }

    public var id: UUID
    public var kind: Kind
    /// 话题：这件事叫什么。同一个话题只有一条。
    public var title: String
    public var notes: [Note]
    /// 跟哪些东西有关，聊到它们时自动带出来。写成「种类:名字」：category:工资、account:caixa、book:shop、
    /// merchant:绿篮超市、subscription:健身房、goal:应急金、person:阿杰。
    public var links: [String]
    public var createdAt: Date
    public var updatedAt: Date
    /// 重要：每月整理时不列出来。（规矩本来就不列。）
    public var pinned: Bool
    /// 上次整理时用户说「留着」的时间。
    public var reviewedAt: Date?
    /// AI 上次把这条读出来用的时间。
    public var usedAt: Date?

    public init(id: UUID = UUID(), kind: Kind, title: String, notes: [Note] = [], links: [String] = [],
                createdAt: Date = Date(), updatedAt: Date? = nil, pinned: Bool = false) {
        self.id = id; self.kind = kind; self.title = title; self.notes = notes; self.links = links
        self.createdAt = createdAt; self.updatedAt = updatedAt ?? createdAt; self.pinned = pinned
    }

    enum CodingKeys: String, CodingKey { case id, kind, title, notes, links, createdAt, updatedAt, pinned, reviewedAt, usedAt }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        kind = try c.decodeIfPresent(Kind.self, forKey: .kind) ?? .topic
        title = try c.decodeIfPresent(String.self, forKey: .title) ?? ""
        notes = try c.decodeIfPresent([Note].self, forKey: .notes) ?? []
        links = try c.decodeIfPresent([String].self, forKey: .links) ?? []
        createdAt = try c.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date()
        updatedAt = try c.decodeIfPresent(Date.self, forKey: .updatedAt) ?? createdAt
        pinned = try c.decodeIfPresent(Bool.self, forKey: .pinned) ?? false
        reviewedAt = try c.decodeIfPresent(Date.self, forKey: .reviewedAt)
        usedAt = try c.decodeIfPresent(Date.self, forKey: .usedAt)
    }

    /// 最后一次「还活着」的时间：改过、用过、或整理时说过留着，取最近的。
    public var lastTouched: Date { max(updatedAt, max(reviewedAt ?? updatedAt, usedAt ?? updatedAt)) }

    /// 最近动过这条的人。
    public var lastAuthor: String {
        notes.max { ($0.editedAt ?? $0.createdAt) < ($1.editedAt ?? $1.createdAt) }.map { $0.editedBy ?? $0.author } ?? ""
    }

    /// 能挂的种类。
    public static let linkKinds = ["category", "account", "book", "merchant", "subscription", "goal", "person"]
    public static let linkKindLabels = ["category": "分类", "account": "账户", "book": "账本", "merchant": "商户",
                                        "subscription": "订阅", "goal": "目标", "person": "人"]

    /// 「category:工资」→（分类，工资）。给界面显示成小标签。
    public static func linkParts(_ link: String) -> (kind: String, name: String) {
        let parts = link.split(separator: ":", maxSplits: 1).map(String.init)
        guard parts.count == 2 else { return ("", link) }
        return (parts[0], parts[1])
    }

    public static let maxTitle = 30
    public static let maxText = 300
    /// 规矩最多这么多行：每次聊天都要读全文，多了就没人读完。
    public static let maxRuleLines = 20
    /// 一个话题最多这么多行：再多就该并成一两句了。
    public static let maxLines = 8
    /// 这么多天没动过、没用上，整理时列出来。
    public static let staleDays = 180
    /// 多久整理一次。
    public static let tidyEveryDays = 30
}

public enum MemoryError: Error, LocalizedError, Equatable {
    case emptyTitle
    case emptyText
    case tooLong(String, Int)
    case looksSecret
    case unknownMemory(String)
    case unknownNote(String)
    case duplicate(String)
    /// 有相近的话题：是同一件事就加在它下面，确实是新话题再说明。带上相近的那几条（id 前 8 位 + 标题）。
    case similarExists([String])
    case tooManyRules
    case tooManyLines(String)
    case badLink(String)
    case nothingToChange

    public var errorDescription: String? {
        switch self {
        case .emptyTitle: "要写这件事叫什么（话题），比如「工资」「转给妈妈的钱」。"
        case .emptyText: "要写记住什么。"
        case .tooLong(let what, let n): "\(what)太长了，最多 \(n) 个字。一句话说清就行，细节分成几行记。"
        case .looksSecret: "看起来像卡号、银行账号或密码。记忆里不存这些。"
        case .unknownMemory(let k): "找不到这条记忆：\(k)"
        case .unknownNote(let k): "这条记忆里找不到这一行：\(k)"
        case .duplicate(let t): "「\(t)」里已经记过这句了。"
        case .similarExists(let list):
            "已经有相近的话题：\(list.joined(separator: "、"))。是同一件事就加在那条下面（topic 填它的 id）；确实是另一件事，加 new_topic=true 再记。"
        case .tooManyRules:
            "规矩已经有 \(Memory.maxRuleLines) 行了。规矩是每次都要读的，要少而准：把不常用的挪到「记得的事」，或者先删掉过时的。"
        case .tooManyLines(let t):
            "「\(t)」下面已经有 \(Memory.maxLines) 行了。先把旧的并成一两句（update_memory 改、forget_memory 删），再记新的。"
        case .badLink(let l):
            "挂的东西看不懂：\(l)。写成「种类:名字」，种类只能是 \(Memory.linkKinds.joined(separator: " / "))，账户和账本要用 context 里的 id。"
        case .nothingToChange: "和现在一样，没有要改的。"
        }
    }
}

/// 搜出来的一条：记忆本身 + 对上了多少。
public struct MemoryHit: Codable, Sendable {
    public var memory: Memory
    public var score: Int

    public init(memory: Memory, score: Int) { self.memory = memory; self.score = score }
}

/// 每月整理时列出来的一项。
public struct MemoryTidyItem: Identifiable, Hashable, Codable, Sendable {
    public enum Reason: String, Codable, Sendable {
        /// 记的时候定的回头看日期过了。
        case expired
        /// 半年没动过、没用上。
        case stale
        /// 挂的账户、账本、订阅、目标已经没了。
        case orphan
        /// 行数太多，该并一并（只提醒）。
        case crowded
    }

    public var memoryID: UUID
    /// 只清其中一行时填；nil = 整条。
    public var noteID: UUID?
    public var title: String
    public var text: String
    public var reason: Reason
    /// 给人看的原因。
    public var why: String

    public init(memoryID: UUID, noteID: UUID? = nil, title: String, text: String, reason: Reason, why: String) {
        self.memoryID = memoryID; self.noteID = noteID; self.title = title; self.text = text; self.reason = reason; self.why = why
    }

    public var id: String { memoryID.uuidString + (noteID?.uuidString ?? "") }
    /// 能不能一键清掉（行数太多的要让夏夏并，不能直接清）。
    public var removable: Bool { reason != .crowded }
}

extension Ledger {
    // MARK: 读

    /// 某一类记忆，最近动过的在前。
    public func memories(kind: Memory.Kind? = nil) -> [Memory] {
        memories.filter { kind == nil || $0.kind == kind }.sorted { $0.updatedAt > $1.updatedAt }
    }

    /// 规矩一共有多少行。
    public var ruleLineCount: Int { memories.filter { $0.kind == .rule }.reduce(0) { $0 + $1.notes.count } }

    /// 一共记得多少件事（按行数）。
    public var memoryLineCount: Int { memories.reduce(0) { $0 + $1.notes.count } }

    /// 按 id（前几位也行）或标题找一条。
    public func findMemory(_ key: String) -> Memory? {
        let k = key.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !k.isEmpty else { return nil }
        if let hit = memories.first(where: { $0.id.uuidString.lowercased() == k }) { return hit }
        let titleKey = MemorySearch.key(key)
        if let hit = memories.first(where: { MemorySearch.key($0.title) == titleKey }) { return hit }
        guard k.count >= 4 else { return nil }
        let hits = memories.filter { $0.id.uuidString.lowercased().hasPrefix(k) }
        return hits.count == 1 ? hits[0] : nil
    }

    /// 在一条记忆里按 id（前几位也行）找一行；只有一行时不填也行。
    public func findNote(_ key: String?, in memory: Memory) -> Memory.Note? {
        guard let key = key?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(), !key.isEmpty else {
            return memory.notes.count == 1 ? memory.notes[0] : nil
        }
        if let hit = memory.notes.first(where: { $0.id.uuidString.lowercased() == key }) { return hit }
        let hits = memory.notes.filter { $0.id.uuidString.lowercased().hasPrefix(key) }
        return hits.count == 1 ? hits[0] : nil
    }

    /// 标题相近的话题（同名、互相包含，或大半个字一样）。
    public func similarMemories(to title: String) -> [Memory] {
        let k = MemorySearch.key(title)
        guard !k.isEmpty else { return [] }
        let grams = MemorySearch.tokens(title)
        return memories.filter { m in
            let other = MemorySearch.key(m.title)
            if other == k { return true }
            if other.count >= 2, k.count >= 2, other.contains(k) || k.contains(other) { return true }
            let og = MemorySearch.tokens(m.title)
            guard !grams.isEmpty, !og.isEmpty else { return false }
            let common = grams.intersection(og).count
            return Double(common) / Double(min(grams.count, og.count)) >= 0.6 && common >= 2
        }
    }

    /// 搜记忆：按关键词对标题、挂的东西、每一行打分。不用向量，条数少，这样就够准，也说得清为什么搜到。
    public func searchMemories(_ query: String, kind: Memory.Kind? = nil, limit: Int = 8) -> [MemoryHit] {
        let q = MemorySearch.key(query)
        let qt = MemorySearch.tokens(query)
        guard !q.isEmpty else { return [] }
        var hits: [MemoryHit] = []
        for m in memories where kind == nil || m.kind == kind {
            var score = 0
            let title = MemorySearch.key(m.title)
            if title == q { score += 12 } else if title.contains(q) || (title.count >= 2 && q.contains(title)) { score += 8 }
            score += 3 * qt.intersection(MemorySearch.tokens(m.title)).count
            for l in m.links {
                let name = MemorySearch.key(Memory.linkParts(l).name)
                if !name.isEmpty, name == q || q.contains(name) || name.contains(q) { score += 6 }
                score += 2 * qt.intersection(MemorySearch.tokens(name)).count
            }
            for n in m.notes {
                let body = MemorySearch.key([n.text, n.quote ?? "", n.story ?? ""].joined(separator: " "))
                if body.contains(q) { score += 4 }
                score += qt.intersection(MemorySearch.tokens(body)).count
            }
            if score > 0 { hits.append(MemoryHit(memory: m, score: score)) }
        }
        return Array(hits.sorted { $0.score == $1.score ? $0.memory.updatedAt > $1.memory.updatedAt : $0.score > $1.score }.prefix(limit))
    }

    /// 挂在某样东西上的记忆（category:工资、account:caixa……），名字不分大小写。
    public func memories(linkedTo link: String) -> [Memory] {
        let (kind, name) = Memory.linkParts(link)
        let key = MemorySearch.key(name)
        return memories().filter { m in
            m.links.contains { l in
                let p = Memory.linkParts(l)
                return p.kind == kind && MemorySearch.key(p.name) == key
            }
        }
    }

    // MARK: 写

    /// 记一条。先搜再记：`into` 指定了就加在那条下面；没指定但有同名话题，也加在它下面；
    /// 有相近的话题而没说 `allowNew`，就报出来让调用方选（同一件事只留一条）。记进改动记录，能撤销。
    @discardableResult
    public mutating func remember(kind: Memory.Kind, title: String, text: String, source: Memory.Source = .said,
                                  quote: String? = nil, story: String? = nil, date: LocalDate = .today,
                                  reviewOn: LocalDate? = nil, links: [String] = [], into memoryID: UUID? = nil,
                                  allowNew: Bool = false, author: String) throws -> ChangeRecord {
        let body = try Self.cleanText(text)
        let q = try Self.cleanOptional(quote, what: "原话")
        let st = try Self.cleanOptional(story, what: "经过")
        let cleanLinks = try checkedLinks(links)
        let note = Memory.Note(text: body, source: source, quote: q, story: st, date: date, author: author, reviewOn: reviewOn)

        var target: Int?
        if let memoryID {
            guard let i = memories.firstIndex(where: { $0.id == memoryID }) else { throw MemoryError.unknownMemory(memoryID.uuidString) }
            target = i
        } else {
            let t = try Self.cleanTitle(title)
            let key = MemorySearch.key(t)
            target = key.isEmpty ? nil : memories.firstIndex { MemorySearch.key($0.title) == key }
            if target == nil, !allowNew {
                let similar = similarMemories(to: t)
                if !similar.isEmpty {
                    throw MemoryError.similarExists(similar.map { "\($0.id.uuidString.prefix(8).lowercased())「\($0.title)」" })
                }
            }
        }

        if let i = target {
            let bodyKey = MemorySearch.key(body)
            if memories[i].notes.contains(where: { MemorySearch.key($0.text) == bodyKey }) { throw MemoryError.duplicate(memories[i].title) }
            if memories[i].kind == .rule, ruleLineCount >= Memory.maxRuleLines { throw MemoryError.tooManyRules }
            if memories[i].notes.count >= Memory.maxLines { throw MemoryError.tooManyLines(memories[i].title) }
            var snapshot = PlanSnapshot()
            snapshot.memories = [memories[i]]
            memories[i].notes.append(note)
            for l in cleanLinks where !memories[i].links.contains(l) { memories[i].links.append(l) }
            memories[i].updatedAt = note.createdAt
            return appendMemoryChange("记忆：在「\(memories[i].title)」下面又记了一行", before: snapshot, author: author)
        }

        if kind == .rule, ruleLineCount >= Memory.maxRuleLines { throw MemoryError.tooManyRules }
        let memory = Memory(kind: kind, title: try Self.cleanTitle(title), notes: [note], links: cleanLinks, createdAt: note.createdAt)
        memories.append(memory)
        var snapshot = PlanSnapshot()
        snapshot.addedMemoryIDs = [memory.id]
        return appendMemoryChange("记忆：记住了「\(memory.title)」（\(kind.label)）", before: snapshot, author: author)
    }

    /// 改一行（说法变了就改，不留两条打架）。只填要改的。
    @discardableResult
    public mutating func updateMemoryNote(_ memoryID: UUID, noteID: UUID, text: String? = nil, source: Memory.Source? = nil,
                                          quote: String?? = nil, story: String?? = nil, reviewOn: LocalDate?? = nil,
                                          author: String) throws -> ChangeRecord {
        guard let i = memories.firstIndex(where: { $0.id == memoryID }) else { throw MemoryError.unknownMemory(memoryID.uuidString) }
        guard let k = memories[i].notes.firstIndex(where: { $0.id == noteID }) else { throw MemoryError.unknownNote(noteID.uuidString) }
        let old = memories[i]
        var note = old.notes[k]
        if let text { note.text = try Self.cleanText(text) }
        if let source { note.source = source }
        if let quote { note.quote = try Self.cleanOptional(quote, what: "原话") }
        if let story { note.story = try Self.cleanOptional(story, what: "经过") }
        if let reviewOn { note.reviewOn = reviewOn }
        guard note != old.notes[k] else { throw MemoryError.nothingToChange }
        note.editedBy = author
        note.editedAt = Date()
        memories[i].notes[k] = note
        memories[i].updatedAt = Date()
        var snapshot = PlanSnapshot()
        snapshot.memories = [old]
        return appendMemoryChange("记忆：改了「\(old.title)」里的一行", before: snapshot, author: author)
    }

    /// 改话题名、挪到另一类（规矩 ↔ 记得的事 ↔ 做事经验）、换挂的东西。只填要改的。
    @discardableResult
    public mutating func editMemory(_ id: UUID, title: String? = nil, kind: Memory.Kind? = nil, links: [String]? = nil,
                                    pinned: Bool? = nil, author: String) throws -> ChangeRecord {
        guard let i = memories.firstIndex(where: { $0.id == id }) else { throw MemoryError.unknownMemory(id.uuidString) }
        let old = memories[i]
        var said: [String] = []
        if let title {
            let t = try Self.cleanTitle(title)
            if t != old.title {
                let key = MemorySearch.key(t)
                if let other = memories.first(where: { $0.id != id && MemorySearch.key($0.title) == key }) {
                    throw MemoryError.similarExists(["\(other.id.uuidString.prefix(8).lowercased())「\(other.title)」"])
                }
                memories[i].title = t
                said.append("改名为「\(t)」")
            }
        }
        if let kind, kind != old.kind {
            if kind == .rule, ruleLineCount + old.notes.count > Memory.maxRuleLines { throw MemoryError.tooManyRules }
            memories[i].kind = kind
            said.append("挪到「\(kind.label)」")
        }
        if let links {
            let clean = try checkedLinks(links)
            if clean != old.links { memories[i].links = clean; said.append("换了挂的东西") }
        }
        if let pinned, pinned != old.pinned {
            memories[i].pinned = pinned
            said.append(pinned ? "标成重要" : "不再标重要")
        }
        guard !said.isEmpty else { throw MemoryError.nothingToChange }
        memories[i].updatedAt = Date()
        var snapshot = PlanSnapshot()
        snapshot.memories = [old]
        return appendMemoryChange("记忆：「\(old.title)」\(said.joined(separator: "，"))", before: snapshot, author: author)
    }

    /// 删掉一整条，或只删其中一行（最后一行删了，整条就没了）。能撤销。
    @discardableResult
    public mutating func removeMemory(_ id: UUID, noteID: UUID? = nil, author: String) throws -> ChangeRecord {
        guard let i = memories.firstIndex(where: { $0.id == id }) else { throw MemoryError.unknownMemory(id.uuidString) }
        let old = memories[i]
        var snapshot = PlanSnapshot()
        snapshot.memories = [old]
        if let noteID, old.notes.count > 1 {
            guard let k = old.notes.firstIndex(where: { $0.id == noteID }) else { throw MemoryError.unknownNote(noteID.uuidString) }
            memories[i].notes.remove(at: k)
            memories[i].updatedAt = Date()
            return appendMemoryChange("记忆：删了「\(old.title)」里的一行", before: snapshot, author: author)
        }
        if let noteID, !old.notes.contains(where: { $0.id == noteID }) { throw MemoryError.unknownNote(noteID.uuidString) }
        memories.remove(at: i)
        return appendMemoryChange("记忆：删了「\(old.title)」", before: snapshot, author: author)
    }

    /// 彻底忘掉：删掉这条（或其中一行），并把改动记录里留着的旧样子、提到它的说明一起抹掉。不能撤销，找不回来。
    /// 改动记录里只留一句「忘掉了一条记忆」，不写是什么。
    @discardableResult
    public mutating func forgetMemory(_ id: UUID, noteID: UUID? = nil, author: String) throws -> ChangeRecord {
        guard let i = memories.firstIndex(where: { $0.id == id }) else { throw MemoryError.unknownMemory(id.uuidString) }
        let old = memories[i]
        let wholeEntry: Bool
        if let noteID, old.notes.count > 1 {
            guard let k = old.notes.firstIndex(where: { $0.id == noteID }) else { throw MemoryError.unknownNote(noteID.uuidString) }
            memories[i].notes.remove(at: k)
            memories[i].updatedAt = Date()
            wholeEntry = false
        } else {
            if let noteID, !old.notes.contains(where: { $0.id == noteID }) { throw MemoryError.unknownNote(noteID.uuidString) }
            memories.remove(at: i)
            wholeEntry = true
        }
        // 改动记录里存着的旧样子：整条忘掉就拿走，只忘一行就把那一行从每份旧样子里拿走。
        var titles: Set<String> = [old.title]
        for c in changes.indices {
            guard var before = changes[c].before else { continue }
            let touched = (before.memories ?? []).contains { $0.id == id } || (before.addedMemoryIDs ?? []).contains(id)
            guard touched else { continue }
            for m in before.memories ?? [] where m.id == id { titles.insert(m.title) }
            if wholeEntry {
                before.memories = before.memories?.filter { $0.id != id }
                before.addedMemoryIDs = before.addedMemoryIDs?.filter { $0 != id }
            } else if let noteID {
                before.memories = before.memories?.map { m in
                    guard m.id == id else { return m }
                    var copy = m
                    copy.notes.removeAll { $0.id == noteID }
                    return copy
                }
            }
            if before.memories?.isEmpty ?? true { before.memories = nil }
            if before.addedMemoryIDs?.isEmpty ?? true { before.addedMemoryIDs = nil }
            // 这条改动只动过记忆，现在没东西可放回去了：不再能撤销。
            changes[c].before = (before == PlanSnapshot()) ? nil : before
        }
        if wholeEntry {
            for c in changes.indices {
                let summary = changes[c].summary
                guard summary.contains("记忆："), titles.contains(where: { summary.contains("「\($0)」") }) else { continue }
                changes[c].summary = (summary.hasPrefix("撤销：") ? "撤销：" : "") + "记忆：（已经忘掉的一条）"
            }
        }
        let change = ChangeRecord(kind: .edit, summary: "记忆：忘掉了一条（不留内容，找不回来）", transactionIDs: [], author: author)
        changes.append(change)
        return change
    }

    // MARK: 每月整理

    /// 可能该清掉的：到期的、半年没动也没用上的、挂的东西已经没了的；还有行数太多该并一并的（只提醒，不能一键清）。
    /// 规矩和标了「重要」的不列。记忆不会自己删，只列出来等用户点。
    public func memoryTidyList(today: LocalDate = .today, now: Date = Date()) -> [MemoryTidyItem] {
        var out: [MemoryTidyItem] = []
        let subs = Dictionary(subscriptions.map { (MemorySearch.key($0.name), $0) }, uniquingKeysWith: { a, _ in a })
        let goalNames = Set(goals.map { MemorySearch.key($0.name) })
        for m in memories() where m.kind != .rule && !m.pinned {
            let first = m.notes.first?.text ?? ""
            // 挂的东西没了。
            var gone: String?
            for l in m.links {
                let (kind, name) = Memory.linkParts(l)
                let key = MemorySearch.key(name)
                switch kind {
                case "account": if !accounts.contains(where: { $0.id == name }) { gone = "挂的账户「\(name)」已经不在了" }
                case "book": if !books.contains(where: { $0.id == name }) { gone = "挂的账本「\(name)」已经不在了" }
                case "subscription":
                    if let s = subs[key] { if s.cancelledOn != nil { gone = "订阅「\(name)」已经停了" } }
                    else { gone = "订阅「\(name)」已经不在了" }
                case "goal": if !goalNames.contains(key) { gone = "目标「\(name)」已经不在了" }
                default: break
                }
                if gone != nil { break }
            }
            if let gone {
                out.append(MemoryTidyItem(memoryID: m.id, noteID: nil, title: m.title, text: first, reason: .orphan, why: gone))
                continue
            }
            // 到期的那几行。
            var expired = 0
            for n in m.notes {
                if let r = n.reviewOn, r < today {
                    expired += 1
                    out.append(MemoryTidyItem(memoryID: m.id, noteID: m.notes.count > 1 ? n.id : nil, title: m.title, text: n.text,
                                              reason: .expired, why: "记的时候说 \(r.month) 月 \(r.day) 日回头看，已经过了"))
                }
            }
            if expired > 0 { continue }
            // 半年没动、没用上。
            let idle = Int(now.timeIntervalSince(m.lastTouched) / 86_400)
            if idle >= Memory.staleDays {
                out.append(MemoryTidyItem(memoryID: m.id, noteID: nil, title: m.title, text: first, reason: .stale,
                                          why: "\(idle / 30) 个月没动过，也没用上"))
                continue
            }
            // 行数太多：提醒并一并。
            if m.notes.count >= Memory.maxLines - 1 {
                out.append(MemoryTidyItem(memoryID: m.id, noteID: nil, title: m.title, text: first, reason: .crowded,
                                          why: "已经有 \(m.notes.count) 行了，让夏夏并成一两句"))
            }
        }
        return out
    }

    /// 该不该提醒整理了：距上次整理（没整理过就从最早那条记忆算）满一个月，而且有东西可清。
    public func memoryTidyDue(today: LocalDate = .today, now: Date = Date()) -> Bool {
        guard let since = profile.memoryTidiedAt ?? memories.map(\.createdAt).min() else { return false }
        guard now.timeIntervalSince(since) >= Double(Memory.tidyEveryDays) * 86_400 else { return false }
        return !memoryTidyList(today: today, now: now).isEmpty
    }

    /// 整理：把列出来的清掉（一条改动，能一次撤销），并记下「整理过了」。行数太多的那种不在这里清。
    @discardableResult
    public mutating func tidyMemories(remove items: [MemoryTidyItem], author: String, now: Date = Date()) throws -> ChangeRecord {
        var snapshot = PlanSnapshot()
        snapshot.profile = profile
        var before: [Memory] = []
        var removed = 0
        for item in items where item.reason != .crowded {
            guard let i = memories.firstIndex(where: { $0.id == item.memoryID }) else { continue }
            if !before.contains(where: { $0.id == item.memoryID }) { before.append(memories[i]) }
            if let noteID = item.noteID, memories[i].notes.count > 1 {
                let n = memories[i].notes.count
                memories[i].notes.removeAll { $0.id == noteID }
                removed += n - memories[i].notes.count
                memories[i].updatedAt = now
            } else {
                removed += memories[i].notes.count
                memories.remove(at: i)
            }
        }
        profile.memoryTidiedAt = now
        snapshot.memories = before.isEmpty ? nil : before
        return appendMemoryChange(removed == 0 ? "记忆：整理了一次，没有要清的" : "记忆：整理了一次，清掉 \(removed) 行", before: snapshot, author: author)
    }

    /// 整理时说「留着」：这条半年内不再列出来；到期的回头看日期也拿掉。
    @discardableResult
    public mutating func keepMemory(_ id: UUID, author: String, now: Date = Date()) throws -> ChangeRecord {
        guard let i = memories.firstIndex(where: { $0.id == id }) else { throw MemoryError.unknownMemory(id.uuidString) }
        var snapshot = PlanSnapshot()
        snapshot.memories = [memories[i]]
        memories[i].reviewedAt = now
        let today = LocalDate.today
        for k in memories[i].notes.indices {
            if let r = memories[i].notes[k].reviewOn, r < today { memories[i].notes[k].reviewOn = nil }
        }
        return appendMemoryChange("记忆：「\(memories[i].title)」留着", before: snapshot, author: author)
    }

    /// AI 把这几条读出来用了：记一下时间（不进改动记录）。一天内读过的不重复记。返回有没有改动。
    public mutating func touchMemories(_ ids: [UUID], now: Date = Date()) -> Bool {
        var changed = false
        for k in memories.indices where ids.contains(memories[k].id) {
            if let u = memories[k].usedAt, now.timeIntervalSince(u) < 86_400 { continue }
            memories[k].usedAt = now
            changed = true
        }
        return changed
    }

    // MARK: 小工具

    mutating func appendMemoryChange(_ summary: String, before: PlanSnapshot, author: String) -> ChangeRecord {
        var change = ChangeRecord(kind: .edit, summary: summary, transactionIDs: [], author: author)
        change.before = before
        changes.append(change)
        return change
    }

    static func cleanTitle(_ title: String) throws -> String {
        let t = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { throw MemoryError.emptyTitle }
        guard t.count <= Memory.maxTitle else { throw MemoryError.tooLong("话题名", Memory.maxTitle) }
        guard !MemorySearch.looksSecret(t) else { throw MemoryError.looksSecret }
        return t
    }

    static func cleanText(_ text: String) throws -> String {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { throw MemoryError.emptyText }
        guard t.count <= Memory.maxText else { throw MemoryError.tooLong("这一行", Memory.maxText) }
        guard !MemorySearch.looksSecret(t) else { throw MemoryError.looksSecret }
        return t
    }

    static func cleanOptional(_ text: String?, what: String) throws -> String? {
        guard let t = text?.trimmingCharacters(in: .whitespacesAndNewlines), !t.isEmpty else { return nil }
        guard t.count <= Memory.maxText else { throw MemoryError.tooLong(what, Memory.maxText) }
        guard !MemorySearch.looksSecret(t) else { throw MemoryError.looksSecret }
        return t
    }

    /// 检查挂的东西：种类要认识，账户和账本要真有。去重、去空格。
    func checkedLinks(_ links: [String]) throws -> [String] {
        var out: [String] = []
        for raw in links {
            let l = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !l.isEmpty else { continue }
            let (kind, name) = Memory.linkParts(l)
            let n = name.trimmingCharacters(in: .whitespaces)
            guard Memory.linkKinds.contains(kind), !n.isEmpty, n.count <= 40 else { throw MemoryError.badLink(l) }
            if kind == "account", !accounts.contains(where: { $0.id == n }) { throw MemoryError.badLink(l) }
            if kind == "book", !books.contains(where: { $0.id == n }) { throw MemoryError.badLink(l) }
            let clean = "\(kind):\(n)"
            if !out.contains(clean) { out.append(clean) }
        }
        return out
    }
}

/// 记忆搜索用的文字处理。
public enum MemorySearch {
    /// 比较用的样子：小写、去重音、标点变空格。中文原样留着。
    public static func key(_ text: String) -> String {
        text.lowercased()
            .folding(options: [.diacriticInsensitive], locale: Locale(identifier: "es_ES"))
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    /// 拆成能比的小块：拉丁字母和数字按词（至少 2 个字符），中日韩文字按相邻两个字（单个字的词按一个字）。
    public static func tokens(_ text: String) -> Set<String> {
        var out = Set<String>()
        for word in key(text).split(separator: " ") {
            var latin = ""
            var han: [Character] = []
            func flush() {
                if latin.count >= 2 { out.insert(latin) }
                latin = ""
                if han.count == 1 { out.insert(String(han[0])) }
                if han.count >= 2 { for i in 0..<(han.count - 1) { out.insert(String(han[i...i + 1])) } }
                han = []
            }
            for ch in word {
                if ch.isASCII || !isHan(ch) {
                    if !han.isEmpty { flush() }
                    latin.append(ch)
                } else {
                    if !latin.isEmpty { flush() }
                    han.append(ch)
                }
            }
            flush()
        }
        return out
    }

    static func isHan(_ ch: Character) -> Bool {
        guard let v = ch.unicodeScalars.first?.value else { return false }
        return (0x3400...0x9FFF).contains(v) || (0x3040...0x30FF).contains(v) || (0xAC00...0xD7AF).contains(v) || (0xF900...0xFAFF).contains(v)
    }

    /// 像不像卡号、银行账号、密码：连着 12 位以上的数字（中间可以有空格或横线）、IBAN、或者「密码/PIN/CVV」后面跟着一串。
    public static func looksSecret(_ text: String) -> Bool {
        // 日期（2026-11-23、2026/11/23）先拿掉，免得「2026-01-01 - 2026-12-31」被当成卡号。
        let noDates = text.replacingOccurrences(of: #"\d{4}[-/.]\d{1,2}[-/.]\d{1,2}"#, with: "，", options: .regularExpression)
        var run = 0
        for ch in noDates {
            if ch.isASCII, ch.isNumber { run += 1; if run >= 12 { return true } }
            else if ch == " " || ch == "-" { continue }
            else { run = 0 }
        }
        let compact = text.uppercased().filter { $0.isLetter || $0.isNumber }
        // IBAN：两个字母 + 两位数字 + 至少 11 位字母数字，而且后面大多是数字。
        let chars = Array(compact)
        if chars.count >= 15 {
            for i in 0...(chars.count - 15) where chars[i].isASCII && chars[i].isLetter && chars[i + 1].isASCII && chars[i + 1].isLetter
                && chars[i + 2].isNumber && chars[i + 3].isNumber {
                let tail = chars[(i + 4)..<min(chars.count, i + 24)]
                if tail.count >= 11, tail.filter(\.isNumber).count >= 10 { return true }
            }
        }
        let lower = text.lowercased()
        for word in ["密码", "password", "passwd", "contraseña", "pin", "cvv", "cvc"] {
            guard let r = lower.range(of: word) else { continue }
            if word.allSatisfy(\.isASCII), word.count <= 3 {
                // 短词按整词比，免得 "pin" 撞上 "shopping"。
                let before = r.lowerBound == lower.startIndex ? nil : lower[lower.index(before: r.lowerBound)]
                let after = r.upperBound == lower.endIndex ? nil : lower[r.upperBound]
                if (before?.isLetter ?? false) && (before?.isASCII ?? false) { continue }
                if (after?.isLetter ?? false) && (after?.isASCII ?? false) { continue }
            }
            // 后面 12 个字符里有 4 位以上数字，才当成真的写了密码。
            let tail = lower[r.upperBound...].prefix(12)
            if tail.filter(\.isNumber).count >= 4 { return true }
        }
        return false
    }
}

/// 给 AI 的记忆摘要：规矩全文 + 其它记忆的目录。跟说明书（context）一起给，也放进内置夏夏每次的开场。
public struct MemoryBrief: Codable, Sendable {
    public struct Row: Codable, Sendable {
        /// id 前 8 位，用 memory 工具按它读全文。
        public var id: String
        /// topic（记得的事）/ lesson（做事经验）。
        public var kind: String
        public var title: String
        public var links: [String]
        public var lines: Int
        public var updated: String
    }

    /// 用户定的规矩，每次都照做。每行是「话题：内容」。
    public var rules: [String]
    /// 其它记忆的目录：聊到相关话题、或要做那类事之前，按 id 读出来。
    public var index: [Row]
    /// 记忆怎么用、什么时候记、什么不记。
    public var howTo: [String]
    /// 到了每月整理的时候才有：这次聊完顺便跟用户过一遍，哪些清掉、哪些留着。
    public var tidy: [String]?

    public static let howTo: [String] = [
        "rules 是用户亲口定的规矩和用词，每次都照做；和别的说法冲突时以它为准。",
        "index 是记忆目录（只有标题）。用户问到相关的话题，或你要做导入、对账、月报、分类这类事之前，先用 memory 工具把那条读出来（填 id 或 query）再回答。用到了哪条，跟用户说一声是按哪条记的，方便他纠正。",
        "什么时候记（remember）：用户亲口说的、以后还用得上的事（例外、打算、偏好、用词）直接记，source=said；用户纠正了你，或改了你记的东西，记成 source=corrected，story 写当时怎么错的；你自己从流水看出来的规律，先在对话里问用户，用户说对才记，source=confirmed。",
        "不记：能从流水直接算出来的数字（工资多少、房租多少，用 regulars 现算）、临时的事、闲聊、你的猜测、卡号和密码。",
        "先搜再记：同一件事只留一条。已经有这个话题，就加在它下面（topic 填它的 id 或同名标题）；说法变了就用 update_memory 改那一行，不要留两条打架。标题写话题不写结论：「工资」，不是「工资 1.380 €」。",
        "分三类：rule（规矩，每次必读，最多 \(Memory.maxRuleLines) 行，只放高频、确定的约定）、topic（记得的事）、lesson（做事经验：导入、对账这类事做完，有值得下次注意的坑就记，标题用任务名，如「导入对账单」）。",
        "用户说「忘掉」「别记这个」：用 forget_memory。forever=true 是彻底忘掉，连改动记录里的痕迹一起抹掉、找不回来，先跟用户确认。",
        "会过时的事记的时候带上 review_on（哪天回头看），比如「明年 3 月退健身房」填 3 月底。记忆每月整理一次：到期的、半年没用上的会列出来给用户清，所以少记、记准，一个话题最多 \(Memory.maxLines) 行。",
    ]

    public init(ledger: Ledger) {
        rules = ledger.memories(kind: .rule).flatMap { m in m.notes.map { "\(m.title)：\($0.text)" } }
        let df = DateFormatter()
        df.dateFormat = "yyyy-MM-dd"
        df.locale = Locale(identifier: "en_US_POSIX")
        index = ledger.memories().filter { $0.kind != .rule }.map { m in
            Row(id: String(m.id.uuidString.prefix(8)).lowercased(), kind: m.kind.rawValue, title: m.title, links: m.links,
                lines: m.notes.count, updated: df.string(from: m.updatedAt))
        }
        howTo = Self.howTo
        if ledger.memoryTidyDue() {
            tidy = ["该整理记忆了（一个月一次）：这次聊完，顺便把下面这些念给用户，问哪些清掉、哪些留着。清掉用 forget_memory，留着用 update_memory keep=true，行数太多的并成一两句。"]
                + ledger.memoryTidyList().map { "\($0.memoryID.uuidString.prefix(8).lowercased())「\($0.title)」\($0.text)（\($0.why)）" }
        }
    }

    /// 给内置夏夏开场用的一小段话（没有记忆时返回 nil）。
    public var promptText: String? {
        guard !rules.isEmpty || !index.isEmpty else { return nil }
        var p = ""
        if !rules.isEmpty {
            p += "用户定的规矩（每次都照做）：\n" + rules.map { "- \($0)" }.joined(separator: "\n")
        }
        if !index.isEmpty {
            if !p.isEmpty { p += "\n" }
            p += "你还记得这些事（只列了标题；聊到相关的，先用 memory 工具按 id 读出来再答）：\n"
                + index.prefix(40).map { r in
                    "- \(r.id)「\(r.title)」" + (r.kind == "lesson" ? "（做事经验）" : "") + (r.links.isEmpty ? "" : " " + r.links.joined(separator: " "))
                }.joined(separator: "\n")
        }
        if let tidy, !tidy.isEmpty {
            if !p.isEmpty { p += "\n" }
            p += tidy.prefix(9).map { "- \($0)" }.joined(separator: "\n")
        }
        return p
    }
}

extension Memory {
    /// id 前 8 位（小写），给 AI 和命令行用。
    public var shortID: String { String(id.uuidString.prefix(8)).lowercased() }

    /// 给 AI 和命令行看的全文：第一行是话题，下面每行一条，行首是这一行的 id（改、删那一行时用）。
    public func described() -> String {
        var head = "\(shortID) 【\(kind.label)】\(title)"
        if !links.isEmpty { head += "  [" + links.joined(separator: ", ") + "]" }
        if pinned { head += "（重要）" }
        var lines = [head]
        for n in notes {
            var l = "  · \(String(n.id.uuidString.prefix(6)).lowercased()) \(n.text)（\(n.source.label) · \(n.date) · \(n.author) 记下"
            if let e = n.editedBy { l += "，\(e) 改过" }
            l += "）"
            lines.append(l)
            if let q = n.quote { lines.append("      原话：「\(q)」") }
            if let s = n.story { lines.append("      经过：\(s)") }
            if let r = n.reviewOn { lines.append("      回头看：\(r)") }
        }
        return lines.joined(separator: "\n")
    }
}
