#if os(iOS)
import AVFoundation
import FinanceCore
import SwiftUI

// 说一句：苹果自带的语音识别，字边说边出，停顿一会儿就算说完。
// 第一次用时一次性要麦克风和语音识别两个权限。只在手机上识别成字，不录音存文件。

/// 语音识别用 Mac 和 iPhone 共用的那一份（LedgerUI/Voice/SpeechDictation）。这里只放 iPhone 的按钮和相机。
enum P3Permissions {
    /// 相机：第一次点相机时问（麦克风、语音识别在第一次说话时由共用的识别去问）。
    static func camera() async -> Bool { await AVCaptureDevice.requestAccess(for: .video) }
    /// 设置里选的停顿：说完停多久自动发（VoiceRules 的第几个）。
    static var pauseIndex: Int { UserDefaults.standard.object(forKey: "p3.voicePause") as? Int ?? VoiceRules.defaultIndex }
    static var autoSend: Bool { VoiceRules.pause(pauseIndex) != nil }
    /// 设置里选的听写语言（VoiceRules.languages 的第几个，和 Mac 同一张表）。
    static var languageIndex: Int { UserDefaults.standard.object(forKey: "p3.voiceLanguage") as? Int ?? VoiceRules.defaultLanguageIndex }
    /// 开始听之前：按设置定好停多久、听哪种话。
    @MainActor static func prepare(_ voice: SpeechDictation) {
        voice.pause = VoiceRules.pause(pauseIndex).map { Duration.seconds($0) }
        voice.localeID = VoiceRules.localeID(languageIndex)
    }
}

/// 麦克风按钮：点一下开始说，再点一下（或停顿）就说完。说的时候按钮变红、轻轻跳。
struct P3MicButton: View {
    let voice: SpeechDictation
    var size: CGFloat = 40
    var live: (String) -> Void = { _ in }
    let done: (String) -> Void
    var body: some View {
        Button {
            P3Permissions.prepare(voice)
            voice.toggle(live: live, done: done)
        } label: {
            Image(systemName: voice.listening ? "waveform" : "mic")
                .font(.system(size: size * 0.48, weight: .semibold))
                .symbolEffect(.variableColor.iterative, isActive: voice.listening)
                .foregroundStyle(voice.listening ? .white : P3.ink)
                .frame(width: size, height: size)
                .background(Circle().fill(voice.listening ? P3.red : .clear))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(voice.listening ? "说完了" : "说一句")
        .sensoryFeedback(.start, trigger: voice.listening)
    }
}

/// 直接打开相机拍一张（模拟器没有相机时改成从相册选）。
struct P3Camera: UIViewControllerRepresentable {
    let done: (UIImage?) -> Void
    func makeUIViewController(context: Context) -> UIImagePickerController {
        let p = UIImagePickerController()
        p.sourceType = UIImagePickerController.isSourceTypeAvailable(.camera) ? .camera : .photoLibrary
        p.delegate = context.coordinator
        return p
    }
    func updateUIViewController(_ vc: UIImagePickerController, context: Context) {}
    func makeCoordinator() -> Coordinator { Coordinator(done: done) }
    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let done: (UIImage?) -> Void
        init(done: @escaping (UIImage?) -> Void) { self.done = done }
        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            done(info[.originalImage] as? UIImage)
        }
        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) { done(nil) }
    }
}
#endif
