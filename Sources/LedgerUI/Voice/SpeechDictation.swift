import AVFoundation
import FinanceCore
import Speech
import SwiftUI

// 说一句：苹果自带的语音识别，字边说边出，停顿一会儿就算说完。Mac 和 iPhone 共用这一份识别。
// 只在本机把声音识别成字（能本机识别就只在本机），不录音、不存文件。
// 第一次用时一次性要麦克风和语音识别两个权限；被拒了就用不了，按钮会说去哪打开。

@MainActor @Observable
public final class SpeechDictation {
    public var text = ""
    public var listening = false
    public var error: String?
    /// 权限被拒了，或者这个 app 没写用麦克风的说明（那样一问系统就会把 app 关掉，所以干脆不问）。
    public var blocked = false
    /// 停多久算说完、自动交出去；nil 是不自动，等再点一下。
    public var pause: Duration? = .seconds(VoiceRules.defaultPause)
    public var localeID = "zh-CN"

    @ObservationIgnored private var engine = AVAudioEngine()
    @ObservationIgnored private var request: SFSpeechAudioBufferRecognitionRequest?
    @ObservationIgnored private var task: SFSpeechRecognitionTask?
    @ObservationIgnored private var silence: Task<Void, Never>?
    @ObservationIgnored private var onText: ((String) -> Void)?
    @ObservationIgnored private var onDone: ((String) -> Void)?

    public init() {}

    /// 被拒以后告诉人去哪打开。
    public static var whereToAllow: String {
        #if os(macOS)
        "去「系统设置 → 隐私与安全性」里，把「麦克风」和「语音识别」对夏夏账本打开"
        #else
        "去「设置 → 隐私与安全性」里，把「麦克风」和「语音识别」对夏夏账本打开"
        #endif
    }

    /// 这个 app 有没有写好两条用途说明。没写就不能问系统要权限。
    public static var canAsk: Bool {
        let info = Bundle.main.infoDictionary ?? [:]
        return info["NSMicrophoneUsageDescription"] != nil && info["NSSpeechRecognitionUsageDescription"] != nil && NSClassFromString("XCTestCase") == nil
    }

    /// 点一下开始，再点一下停。`live` 每出几个字叫一次；`done` 在说完（停顿够了，或者再点一下）时叫一次。
    public func toggle(live: @escaping (String) -> Void = { _ in }, done: @escaping (String) -> Void) {
        if listening { finish() } else { Task { await start(live: live, done: done) } }
    }

    public func start(live: @escaping (String) -> Void = { _ in }, done: @escaping (String) -> Void) async {
        error = nil
        guard Self.canAsk else { blocked = true; error = "这个版本还不能用麦克风"; return }
        guard await Self.askPermissions() else { blocked = true; error = Self.whereToAllow; return }
        blocked = false
        guard let recognizer = SFSpeechRecognizer(locale: Locale(identifier: localeID)), recognizer.isAvailable else { error = "现在用不了语音识别，等一下再试"; return }
        onText = live; onDone = done
        text = ""
        do {
            #if os(iOS)
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.record, mode: .measurement, options: .duckOthers)
            try session.setActive(true, options: .notifyOthersOnDeactivation)
            #endif
            let req = SFSpeechAudioBufferRecognitionRequest()
            req.shouldReportPartialResults = true
            // 优先只在本机识别
            if recognizer.supportsOnDeviceRecognition { req.requiresOnDeviceRecognition = true }
            request = req
            let input = engine.inputNode
            let format = input.outputFormat(forBus: 0)
            input.removeTap(onBus: 0)
            input.installTap(onBus: 0, bufferSize: 1024, format: format) { buf, _ in req.append(buf) }
            engine.prepare()
            try engine.start()
            listening = true
            task = recognizer.recognitionTask(with: req) { [weak self] result, err in
                Task { @MainActor in
                    guard let self else { return }
                    if let result {
                        self.text = result.bestTranscription.formattedString
                        self.onText?(self.text)
                        self.armSilence()
                        if result.isFinal { self.finish() }
                    } else if err != nil, self.listening {
                        self.finish()
                    }
                }
            }
            armSilence(first: true)
        } catch {
            self.error = "麦克风没打开，再试一次"
            stopAudio()
        }
    }

    /// 一直没出声 5 秒就停；出了字以后，停顿够了算说完（设成「不自动发」就一直等到再点一下）。
    private func armSilence(first: Bool = false) {
        silence?.cancel()
        guard let wait = first ? Duration.seconds(5) : pause else { return }
        silence = Task { [weak self] in
            try? await Task.sleep(for: wait)
            guard !Task.isCancelled else { return }
            self?.finish()
        }
    }

    public func finish() {
        guard listening else { return }
        silence?.cancel()
        stopAudio()
        let said = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let done = onDone
        onDone = nil; onText = nil
        if said.isEmpty { error = "没听到声音，再点一下麦克风说" } else { done?(said) }
    }

    private func stopAudio() {
        listening = false
        engine.stop()
        engine.inputNode.removeTap(onBus: 0)
        request?.endAudio()
        task?.cancel()
        request = nil; task = nil
        #if os(iOS)
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        #endif
    }

    /// 语音识别和麦克风两个权限一次问完。返回两个都给了没有。
    public static func askPermissions() async -> Bool {
        let speech: Bool = await withCheckedContinuation { c in
            SFSpeechRecognizer.requestAuthorization { c.resume(returning: $0 == .authorized) }
        }
        guard speech else { return false }
        return await AVCaptureDevice.requestAccess(for: .audio)
    }
}
