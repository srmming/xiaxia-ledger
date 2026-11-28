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

    /// 听写按哪种语言认。默认中文；选了别的，说的话就按那种语言认（店名、数字的读法会跟着变）。
    public static let languages: [(title: String, localeID: String)] = [("中文", "zh-CN"), ("西班牙语", "es-ES"), ("英语", "en-US")]
    public static let defaultLanguageIndex = 0
    public static func languageTitle(_ i: Int) -> String { languages.indices.contains(i) ? languages[i].title : languages[defaultLanguageIndex].title }
    /// 交给系统语音识别的语言代码；序号不对就回到中文。
    public static func localeID(_ i: Int) -> String { languages.indices.contains(i) ? languages[i].localeID : languages[defaultLanguageIndex].localeID }
}
