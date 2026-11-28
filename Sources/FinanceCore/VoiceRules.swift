import Foundation

/// 语音输入：说完停多久自动发出去。
public enum VoiceRules {
    /// 可选的停顿（秒）；nil 是不自动发，等再点一下麦克风。
    public static let pauses: [Double?] = [1, 1.5, 2, nil]
    public static let defaultPause = 1.5
    public static let defaultIndex = 1
    public static func title(_ i: Int) -> String {
        guard pauses.indices.contains(i), let p = pauses[i] else { return "不自动发" }
        return p == p.rounded() ? "\(Int(p)) 秒" : "\(String(p).replacingOccurrences(of: ".", with: ",")) 秒"
    }
    public static func pause(_ i: Int) -> Double? { pauses.indices.contains(i) ? pauses[i] : defaultPause }
}
