import Foundation

/// 从一句话里认出「哪天」：今天、昨天、前天、上周五、周三、12 号。只认今天和以前的日子。
public enum QuickDate {
    private static let weekdays: [Character: Int] = ["日": 1, "天": 1, "一": 2, "二": 3, "三": 4, "四": 5, "五": 6, "六": 7]

    /// 返回（几天前，去掉日期那几个字以后剩下的话）。话里没提哪天就是 nil。
    public static func extract(_ text: String, today: Date, calendar: Calendar = Calendar(identifier: .gregorian)) -> (daysAgo: Int, rest: String)? {
        for (word, n) in [("大前天", 3), ("前天", 2), ("昨天", 1), ("昨晚", 1), ("今天", 0), ("刚才", 0), ("刚刚", 0)] where text.contains(word) {
            return (n, text.replacingOccurrences(of: word, with: ""))
        }
        // 周五 / 星期五：最近的那一个（这周还没到就算上一个）。上周五：上一个自然周里的那天（周一算一周的头）。
        if let m = text.firstMatch(of: #/(上上|上)?(周|星期|礼拜)([一二三四五六日天])/#), let target = weekdays[m.output.3.first ?? " "] {
            let now = calendar.component(.weekday, from: today)
            let sinceMonday = (now + 5) % 7, targetFromMonday = (target + 5) % 7
            var back: Int
            switch m.output.1 {
            case "上": back = sinceMonday + 7 - targetFromMonday
            case "上上": back = sinceMonday + 14 - targetFromMonday
            default: back = (now - target + 7) % 7
            }
            if back < 0 { back = 0 }
            return (back, text.replacingCharacters(in: m.range, with: ""))
        }
        // 12 号 / 12 日：这个月的那天；还没到就算上个月的
        if let m = text.firstMatch(of: #/(\d{1,2})\s*(号|日)/#), let day = Int(m.output.1), (1...31).contains(day) {
            let nowDay = calendar.component(.day, from: today)
            var back = nowDay - day
            if back < 0, let prev = calendar.date(byAdding: .month, value: -1, to: today), let range = calendar.range(of: .day, in: .month, for: prev) {
                back = nowDay + range.count - day
            }
            guard back >= 0 else { return nil }
            return (back, text.replacingCharacters(in: m.range, with: ""))
        }
        return nil
    }

    /// 「今天」「昨天」「11 月 12 日」。
    public static func label(daysAgo: Int, today: Date, calendar: Calendar = Calendar(identifier: .gregorian)) -> String {
        if daysAgo <= 0 { return "今天" }
        if daysAgo == 1 { return "昨天" }
        guard let d = calendar.date(byAdding: .day, value: -daysAgo, to: today) else { return "\(daysAgo) 天前" }
        return "\(calendar.component(.month, from: d)) 月 \(calendar.component(.day, from: d)) 日"
    }
}
