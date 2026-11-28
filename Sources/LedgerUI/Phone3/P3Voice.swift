#if os(iOS)
import AVFoundation
import Speech
import os
private let vlog = Logger(subsystem: "xiaxia", category: "P3Voice")
import SwiftUI

// 说一句：苹果自带的语音识别，字边说边出，停顿一会儿就算说完。
// 第一次用时一次性要麦克风和语音识别两个权限。只在手机上识别成字，不录音存文件。

@MainActor @Observable
final class P3Voice {
    var text = ""
    var listening = false
    var error: String?

    /// 停多久算说完。
    var pause: Duration = .seconds(1.6)
    @ObservationIgnored private var engine = AVAudioEngine()
    @ObservationIgnored private var request: SFSpeechAudioBufferRecognitionRequest?
    @ObservationIgnored private var task: SFSpeechRecognitionTask?
    @ObservationIgnored private var silence: Task<Void, Never>?
    @ObservationIgnored private var onDone: ((String) -> Void)?
    private let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "zh-CN"))

    /// 说完（停顿或再点一下）时把整句交给 `done`。
    func toggle(done: @escaping (String) -> Void) {
        if listening { finish() } else { Task { await start(done: done) } }
    }

    func start(done: @escaping (String) -> Void) async {
        error = nil
        vlog.notice("P3Voice start")
        guard await Self.askPermissions() else {
            error = "要先在「设置 → 隐私」里允许夏夏账本用麦克风和语音识别"
            return
        }
        vlog.notice("P3Voice perms ok, available=\(self.recognizer?.isAvailable ?? false)")
        guard let recognizer, recognizer.isAvailable else { error = "现在用不了语音识别，等一下再试"; return }
        onDone = done
        text = ""
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.record, mode: .measurement, options: .duckOthers)
            try session.setActive(true, options: .notifyOthersOnDeactivation)
            let req = SFSpeechAudioBufferRecognitionRequest()
            req.shouldReportPartialResults = true
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
                        self.armSilence()
                        if result.isFinal { self.finish() }
                    } else if err != nil, self.listening {
                        self.finish()
                    }
                }
            }
            armSilence(first: true)
        } catch {
            vlog.error("P3Voice audio error \(error.localizedDescription)")
            self.error = "麦克风没打开，再试一次"
            stopAudio()
        }
    }

    private func armSilence(first: Bool = false) {
        silence?.cancel()
        let wait = first ? Duration.seconds(5) : pause
        silence = Task { [weak self] in
            try? await Task.sleep(for: wait)
            guard !Task.isCancelled else { return }
            self?.finish()
        }
    }

    func finish() {
        vlog.notice("P3Voice finish listening=\(self.listening) text=\(self.text)")
        guard listening else { return }
        silence?.cancel()
        stopAudio()
        let said = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let done = onDone
        onDone = nil
        if said.isEmpty { error = nil; error = "没听到声音，再点一下麦克风说" } else { done?(said) }
    }

    private func stopAudio() {
        listening = false
        engine.stop()
        engine.inputNode.removeTap(onBus: 0)
        request?.endAudio()
        task?.cancel()
        request = nil; task = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    /// 麦克风、语音识别、相机一次问完（第一次用其中哪个都一样）。返回说话要的两个给了没有。
    static func askPermissions() async -> Bool {
        _ = await AVCaptureDevice.requestAccess(for: .video)
        let speech: Bool = await withCheckedContinuation { c in
            SFSpeechRecognizer.requestAuthorization { c.resume(returning: $0 == .authorized) }
        }
        guard speech else { return false }
        return await AVAudioApplication.requestRecordPermission()
    }
}

/// 麦克风按钮：点一下开始说，再点一下（或停顿）就说完。说的时候按钮变红、轻轻跳。
struct P3MicButton: View {
    let voice: P3Voice
    var size: CGFloat = 40
    let done: (String) -> Void
    var body: some View {
        Button { voice.toggle(done: done) } label: {
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
