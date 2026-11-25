import FinanceCore
import ImageIO
import PhotosUI
import QuickLook
import SwiftUI
import UniformTypeIdentifiers
#if canImport(Vision)
import Vision
#endif
#if os(iOS)
import UIKit
#else
import AppKit
#endif

// 手机随手记、小票发票、报销的界面（2026-11-23 ming：「今天花了10欧,就是一句话」「拍照,比方说 小票」「写入小票或者发票」）。
// 规则都在 FinanceCore/PhoneCapture.swift；这里只管怎么点。位置照原型「放进现有 app」：
// 「＋记一笔」顶上说一句 / 拍小票；总览最上面「待记录」卡；每笔账的详情里挂小票发票、标报销；
// iPhone「计划」第四格、Mac 侧栏「欠款与分期」下面是「报销」。

// MARK: - 模型上的几个动作

extension LedgerModel {
    /// 这台设备叫什么（待记录上写「iPhone 记的」）。
    var deviceName: String {
        #if os(iOS)
        "iPhone"
        #else
        "Mac"
        #endif
    }

    /// 手机接着 iCloud 文件夹（改动先写成小纸条，等电脑收）。
    var isPhoneLinked: Bool { store is PhoneSyncStore }

    var attachmentsFolder: URL? { LedgerFiles.attachmentsFolder(of: store) }

    func attachmentURL(_ file: String) -> URL? { attachmentsFolder?.appendingPathComponent(file) }

    /// 说一句 / 拍一张小票：放进待记录。照片先缩小存进附件文件夹，本机认出来的文字和金额日期一起记下。
    func addCapture(text: String, photo: Data? = nil, recognized: String? = nil) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty || photo != nil else { return }
        var file: String?
        if let photo {
            guard let folder = attachmentsFolder else {
                toast = Toast(text: tr("示例数据里不能存照片"), changeID: nil, isError: true); return
            }
            do { file = try LedgerFiles.saveAttachment(ImageShrink.jpeg(photo) ?? photo, into: folder) }
            catch { toast = Toast(text: error.localizedDescription, changeID: nil, isError: true); return }
        }
        var guess = trimmed.isEmpty ? CaptureGuess() : CaptureGuess.parse(sentence: trimmed)
        if let recognized {
            let r = CaptureGuess.parse(receipt: recognized)
            guess = CaptureGuess(amount: guess.amount ?? r.amount, date: guess.date ?? r.date, merchant: guess.merchant ?? r.merchant)
        }
        let capture = Capture(kind: photo == nil ? .text : .photo, text: trimmed, photo: file,
                              guess: guess.isEmpty ? nil : guess, recognizedText: recognized, device: deviceName)
        do {
            try edit(quiet: true) { $0.addCapture(capture, author: author) }
            let where_ = isPhoneLinked ? tr("记进待记录了，电脑打开时夏夏补进账本") : tr("记进待记录了")
            toast = Toast(text: where_, changeID: ledger.changes.last?.id)
        } catch {
            toast = Toast(text: error.localizedDescription, changeID: nil, isError: true)
        }
    }

    /// 「同步今天的」：Mac 上连好了 AI 就直接在夏夏对话栏里发出去；没连好就复制给用户自己的 AI。
    func syncPhoneNotes() {
        let text = "同步今天的：把手机上记的待记录（phone_notes）入账。和已有流水去重，拿不准的先问我。"
        #if os(macOS)
        if chatReady { chat.send(text, model: self); return }
        #endif
        handOffToAI(text, page: "总览")
    }

    /// 给一笔账挂一张小票 / 发票。
    func attach(data: Data? = nil, file url: URL? = nil, kind: Attachment.Kind, to transactionID: UUID) {
        guard let folder = attachmentsFolder else {
            toast = Toast(text: tr("示例数据里不能存附件"), changeID: nil, isError: true); return
        }
        do {
            let name: String
            var original: String?
            if let url {
                let ok = url.startAccessingSecurityScopedResource()
                defer { if ok { url.stopAccessingSecurityScopedResource() } }
                name = try LedgerFiles.importAttachment(from: url, into: folder)
                original = url.lastPathComponent
            } else if let data {
                name = try LedgerFiles.saveAttachment(ImageShrink.jpeg(data) ?? data, into: folder)
            } else { return }
            let a = Attachment(kind: kind, file: name, name: original, addedBy: author)
            try edit { try $0.attach(a, to: transactionID, author: author) }
        } catch {
            toast = Toast(text: error.localizedDescription, changeID: nil, isError: true)
        }
    }
}

// MARK: - 图片：缩小、认字

enum ImageShrink {
    /// 照片缩到长边 2000 像素、存成 JPEG（小票看得清，文件一两百 KB，iCloud 传得快）。
    static func jpeg(_ data: Data, maxPixel: Int = 2000) -> Data? {
        guard let src = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let opts: [CFString: Any] = [kCGImageSourceCreateThumbnailFromImageAlways: true,
                                     kCGImageSourceCreateThumbnailWithTransform: true,
                                     kCGImageSourceThumbnailMaxPixelSize: maxPixel]
        guard let img = CGImageSourceCreateThumbnailAtIndex(src, 0, opts as CFDictionary) else { return nil }
        let out = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(out, UTType.jpeg.identifier as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(dest, img, [kCGImageDestinationLossyCompressionQuality: 0.75] as CFDictionary)
        return CGImageDestinationFinalize(dest) ? out as Data : nil
    }
}

enum ReceiptReader {
    /// 苹果自带文字识别（本机，不联网）：把小票上的字读出来。读不出来返回 nil。
    static func text(from data: Data) async -> String? {
        #if canImport(Vision)
        return await Task.detached(priority: .userInitiated) { () -> String? in
            guard let src = CGImageSourceCreateWithData(data as CFData, nil),
                  let img = CGImageSourceCreateImageAtIndex(src, 0, nil) else { return nil }
            let request = VNRecognizeTextRequest()
            request.recognitionLevel = .accurate
            request.recognitionLanguages = ["es-ES", "en-US", "zh-Hans"]
            request.usesLanguageCorrection = false
            try? VNImageRequestHandler(cgImage: img, options: [:]).perform([request])
            let lines = (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }
            return lines.isEmpty ? nil : lines.joined(separator: "\n")
        }.value
        #else
        return nil
        #endif
    }
}

// MARK: - 「＋记一笔」顶上：说一句 / 拍小票

/// 记一笔最上面的一条：说一句话（键盘上的麦克风也能用）或者拍一张小票，先放进待记录，不用填表。
struct CaptureBar: View {
    @Environment(LedgerModel.self) var model
    @Environment(\.dismiss) var dismiss
    @State private var text = ""
    @State private var pickedPhoto: PhotosPickerItem?
    @State private var showCamera = false
    @State private var showFiles = false
    @State private var reading = false
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(tr("说一句或拍小票，夏夏帮你记"), systemImage: "sparkles")
                .font(.subheadline.weight(.semibold)).foregroundStyle(Color.ai)
            HStack(spacing: 8) {
                photoButton
                HStack(spacing: 6) {
                    TextField(tr("比如「午饭 10 欧」"), text: $text)
                        .textFieldStyle(.plain)
                        .focused($focused)
                        .submitLabel(.send)
                        .onSubmit(send)
                        .accessibilityIdentifier("captureText")
                    Button(action: send) {
                        Image(systemName: "arrow.up.circle.fill").font(.title2)
                            .foregroundStyle(text.trimmingCharacters(in: .whitespaces).isEmpty ? Color.fg3 : Color.brand)
                    }
                    .buttonStyle(.plain)
                    .disabled(text.trimmingCharacters(in: .whitespaces).isEmpty)
                    .accessibilityLabel(tr("记进待记录"))
                    .keyboardShortcut(.return, modifiers: .command)
                }
                .padding(.leading, 12).padding(.trailing, 6).padding(.vertical, 7)
                .background(Color.cardBackground, in: Capsule())
            }
            if reading {
                HStack(spacing: 6) { ProgressView().controlSize(.small); Text(tr("正在认小票上的字…")) }
                    .font(.caption).foregroundStyle(Color.fg2)
            } else {
                Text(model.isPhoneLinked ? tr("存进待记录，跟着 iCloud 到电脑上，回到电脑跟夏夏说「同步今天的」就补进账本。")
                                         : tr("存进待记录，之后让夏夏补进账本，或者自己点开记上。"))
                    .font(.caption).foregroundStyle(Color.fg2).fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(12)
        .background(Color.aiSoft, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .onChange(of: pickedPhoto) { _, item in
            guard let item else { return }
            Task {
                if let data = try? await item.loadTransferable(type: Data.self) { await save(photo: data) }
                pickedPhoto = nil
            }
        }
        #if os(iOS)
        .fullScreenCover(isPresented: $showCamera) {
            CameraPicker { data in Task { await save(photo: data) } }.ignoresSafeArea()
        }
        #endif
        .fileImporter(isPresented: $showFiles, allowedContentTypes: [.image]) { result in
            guard case .success(let url) = result else { return }
            let ok = url.startAccessingSecurityScopedResource()
            defer { if ok { url.stopAccessingSecurityScopedResource() } }
            if let data = try? Data(contentsOf: url) { Task { await save(photo: data) } }
        }
    }

    @ViewBuilder private var photoButton: some View {
        Menu {
            #if os(iOS)
            if UIImagePickerController.isSourceTypeAvailable(.camera) {
                Button { showCamera = true } label: { Label(tr("拍小票"), systemImage: "camera") }
            }
            #endif
            PhotosPicker(selection: $pickedPhoto, matching: .images) { Label(tr("从照片里选"), systemImage: "photo") }
            #if os(macOS)
            Button { showFiles = true } label: { Label(tr("选一个图片文件…"), systemImage: "folder") }
            #endif
        } label: {
            Image(systemName: "camera").font(.title3).foregroundStyle(Color.brand)
                .frame(width: 44, height: 44)
                .background(Color.cardBackground, in: Circle())
        }
        .menuStyle(.button).buttonStyle(.plain).menuIndicator(.hidden).fixedSize()
        .accessibilityLabel(tr("拍小票"))
        .accessibilityIdentifier("captureCamera")
    }

    private func send() {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return }
        model.addCapture(text: t)
        text = ""
        dismiss()
    }

    @MainActor private func save(photo data: Data) async {
        reading = true
        let recognized = await ReceiptReader.text(from: data)
        reading = false
        model.addCapture(text: text, photo: data, recognized: recognized)
        text = ""
        dismiss()
    }
}

#if os(iOS)
/// 系统相机：拍一张就回来。
struct CameraPicker: UIViewControllerRepresentable {
    var onPhoto: (Data) -> Void
    @Environment(\.dismiss) var dismiss

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let c = UIImagePickerController()
        c.sourceType = .camera
        c.delegate = context.coordinator
        return c
    }
    func updateUIViewController(_ c: UIImagePickerController, context: Context) {}
    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: CameraPicker
        init(_ p: CameraPicker) { parent = p }
        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            if let img = info[.originalImage] as? UIImage, let data = img.jpegData(compressionQuality: 0.85) { parent.onPhoto(data) }
            parent.dismiss()
        }
        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) { parent.dismiss() }
    }
}
#endif

// MARK: - 总览最上面：待记录

/// 「待记录 · N 句」：手机上随手记、还没入账的。总览要一屏看完（ming），所以只占一行：头像 + 几句预览 + 按钮，
/// 点「看看」弹出整张清单，点一条自己记上。Mac 上多一个「同步今天的」（交给夏夏）。
struct PendingCapturesCard: View {
    @Environment(LedgerModel.self) var model
    @State private var showList = false
    @State private var hidden = false

    var body: some View {
        let list = model.ledger.pendingCaptures
        if !list.isEmpty && !hidden {
            HStack(alignment: .center, spacing: 10) {
                XiaxiaAvatar(size: 34)
                VStack(alignment: .leading, spacing: 1) {
                    Text(tr("待记录 · \(list.count) 句")).font(.headline)
                    Text(preview(list)).font(.caption).foregroundStyle(Color.fg2).lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
                .onTapGesture { showList = true }
                #if os(macOS)
                Button(tr("看看")) { showList = true }.buttonStyle(.soft)
                Button { model.syncPhoneNotes() } label: { Label(tr("同步今天的"), systemImage: "sparkles") }
                    .buttonStyle(.borderedProminent).tint(Color.aiSolid)
                    .accessibilityIdentifier("syncPhoneNotes")
                Button { withAnimation(.snappy) { hidden = true } } label: { Image(systemName: "xmark") }
                    .buttonStyle(.borderless).foregroundStyle(Color.fg3).help(tr("先不管"))
                #else
                Button(tr("看看")) { showList = true }.buttonStyle(.soft)
                #endif
            }
            .aiCard()
            .accessibilityIdentifier("pendingCaptures")
            .sheet(isPresented: $showList) {
                NavigationStack { PendingCapturesList() }.environment(model)
                    #if os(macOS)
                    .frame(minWidth: 480, minHeight: 520)
                    #endif
            }
        }
    }

    private func preview(_ list: [Capture]) -> String {
        list.suffix(3).reversed().map { "「\($0.title)」" }.joined(separator: " ")
    }
}

/// 待记录整张清单：上面一句说明，下面一条条，点开自己记上。
struct PendingCapturesList: View {
    @Environment(LedgerModel.self) var model
    @Environment(\.dismiss) var dismiss

    var body: some View {
        let list = model.ledger.pendingCaptures
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                Text(subtitle).font(.callout).foregroundStyle(Color.fg2).fixedSize(horizontal: false, vertical: true)
                    .padding(.bottom, 4)
                ForEach(list.reversed()) { c in
                    NavigationLink { CaptureDetail(capture: c) } label: { CaptureRow(capture: c) }.buttonStyle(.plain)
                }
                if list.isEmpty {
                    Label(tr("都记好了"), systemImage: "checkmark.circle.fill").foregroundStyle(Color.income).padding(.top, 8)
                }
                #if os(macOS)
                if !list.isEmpty {
                    Button { dismiss(); model.syncPhoneNotes() } label: { Label(tr("同步今天的"), systemImage: "sparkles") }
                        .buttonStyle(.borderedProminent).tint(Color.aiSolid).padding(.top, 6)
                }
                #endif
            }
            .padding(16)
        }
        .background(Color.pageBackground)
        .navigationTitle(tr("待记录"))
        .toolbar { ToolbarItem(placement: .cancellationAction) { Button(tr("完成")) { dismiss() } } }
    }

    private var subtitle: String {
        #if os(macOS)
        return tr("你不在电脑旁时随口记的。点「同步今天的」，夏夏分好类、挑对账户补进账本；也可以点一条自己记上。")
        #else
        return model.isPhoneLinked ? tr("已存 iCloud，电脑打开时夏夏补进账本。也可以点一条自己记上。")
                                   : tr("点一条自己记上，或者让夏夏帮你补进账本。")
        #endif
    }
}

struct CaptureRow: View {
    @Environment(LedgerModel.self) var model
    let capture: Capture

    var body: some View {
        HStack(spacing: 10) {
            if let p = capture.photo, let url = model.attachmentURL(p) {
                AttachmentThumb(url: url, size: 34)
            } else {
                Image(systemName: "text.bubble").foregroundStyle(Color.ai).frame(width: 34, height: 34)
            }
            VStack(alignment: .leading, spacing: 1) {
                Text("「\(capture.title)」").lineLimit(1)
                Text("\(capture.device) · \(capture.createdAt.formatted(date: .abbreviated, time: .shortened))")
                    .font(.caption2).foregroundStyle(Color.fg2)
            }
            Spacer(minLength: 8)
            if let a = capture.guess?.amount {
                Text(a.magnitude.formatted).font(.kitAmount)
            }
            Image(systemName: "chevron.right").font(.caption).foregroundStyle(Color.fg3)
        }
        .font(.callout)
        .padding(.horizontal, 10).padding(.vertical, 7)
        .background(Color.cardBackground.opacity(0.7), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .contentShape(Rectangle())
    }
}

/// 点开一条待记录：看照片和认出来的字，自己记上（或者对上已有的那笔），或者不记了。
struct CaptureDetail: View {
    @Environment(LedgerModel.self) var model
    @Environment(\.dismiss) var dismiss
    let capture: Capture

    @State private var amountText = ""
    @State private var name = ""
    @State private var accountID = ""
    @State private var bookID = ""
    @State private var category: String?
    @State private var date = Date()
    @State private var income = false
    @State private var preview: URL?
    @State private var error: String?

    var body: some View {
        Form {
            Section {
                if let p = capture.photo, let url = model.attachmentURL(p) {
                    Button { preview = url } label: {
                        AttachmentThumb(url: url, size: 180).frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(tr("看小票大图"))
                }
                if !capture.text.isEmpty { Text("「\(capture.text)」").font(.title3) }
                Text("\(capture.device) · \(capture.createdAt.formatted(date: .long, time: .shortened))")
                    .font(.caption).foregroundStyle(Color.fg2)
                if let r = capture.recognizedText, !r.isEmpty {
                    DisclosureGroup(tr("小票上认出来的字")) {
                        Text(r).font(.system(.caption, design: .monospaced)).textSelection(.enabled)
                    }
                }
            }
            Section(tr("记成这一笔")) {
                Picker(tr("方向"), selection: $income) {
                    Text(tr("支出")).tag(false)
                    Text(tr("收入")).tag(true)
                }
                .pickerStyle(.segmented)
                TextField(tr("金额"), text: $amountText)
                    #if os(iOS)
                    .keyboardType(.decimalPad)
                    #endif
                TextField(tr("名称"), text: $name)
                Picker(tr("分类"), selection: $category) {
                    Text(tr("未分类")).tag(String?.none)
                    ForEach(model.categories(bookID: bookID, income: income, limit: 30), id: \.self) { Text($0).tag(String?.some($0)) }
                }
                Picker(tr("账户"), selection: $accountID) {
                    ForEach(model.visibleAccounts) { Text($0.name).tag($0.id) }
                }
                if model.ledger.books.count > 1 {
                    Picker(tr("账本"), selection: $bookID) {
                        ForEach(model.ledger.books) { Text($0.name).tag($0.id) }
                    }
                }
                DatePicker(tr("日期"), selection: $date, displayedComponents: .date)
            }
            let dupes = model.ledger.possibleMatches(for: capture)
            if !dupes.isEmpty {
                Section(tr("可能已经记过了")) {
                    ForEach(dupes) { t in
                        Button {
                            act { try $0.linkCapture(capture.id, to: t.id, author: model.author) }
                        } label: {
                            HStack {
                                VStack(alignment: .leading) {
                                    Text(Merchant.display(t.description))
                                    Text(t.date.friendly).font(.caption).foregroundStyle(Color.fg2)
                                }
                                Spacer()
                                Text(t.amount.formatted).monospacedDigit()
                                Text(tr("就是这笔")).font(.caption).foregroundStyle(Color.brand)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            if let error { Text(error).foregroundStyle(Color.alert).font(.callout) }
            Section {
                Button(role: .destructive) {
                    act { try $0.dismissCapture(capture.id, author: model.author) }
                } label: { Label(tr("不记了"), systemImage: "trash") }
            }
        }
        .formStyle(.grouped)
        .navigationTitle(tr("待记录"))
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button(tr("取消")) { dismiss() } }
            ToolbarItem(placement: .confirmationAction) {
                Button(tr("记上")) { save() }.disabled(Money.evaluate(amountText) == nil || accountID.isEmpty)
                    .accessibilityIdentifier("captureSave")
            }
        }
        .quickLookPreview($preview)
        .onAppear(perform: setup)
    }

    private func setup() {
        if let a = capture.guess?.amount {
            amountText = a.magnitude.decimalString.replacingOccurrences(of: ".", with: ",")
            income = a.isIncome
        }
        name = capture.guess?.merchant ?? capture.text
        accountID = model.visibleAccounts.first?.id ?? ""
        bookID = model.selectedBookID ?? model.ledger.books.first?.id ?? ""
        if let d = capture.guess?.date ?? Optional(capture.day),
           let real = Calendar.current.date(from: DateComponents(year: d.year, month: d.month, day: d.day)) { date = real }
    }

    private func save() {
        guard let m = Money.evaluate(amountText)?.magnitude, m.cents > 0 else { error = tr("金额看不懂"); return }
        let c = Calendar.current.dateComponents([.year, .month, .day], from: date)
        let day = LocalDate(year: c.year ?? 2026, month: c.month ?? 1, day: c.day ?? 1)
        let tx = FinanceCore.Transaction(date: day, amount: income ? m : -m,
                                         description: name.isEmpty ? capture.title : name,
                                         accountID: accountID, bookID: bookID.isEmpty ? nil : bookID, category: category)
        act { try $0.resolveCapture(capture.id, as: tx, author: model.author) }
    }

    private func act(_ body: (inout Ledger) throws -> ChangeRecord) {
        do { try model.edit(body); dismiss() }
        catch { self.error = error.localizedDescription }
    }
}

// MARK: - 附件缩略图

struct AttachmentThumb: View {
    let url: URL
    var size: CGFloat = 64

    var body: some View {
        Group {
            if url.pathExtension.lowercased() == "pdf" {
                ZStack {
                    RoundedRectangle(cornerRadius: 6).fill(Color.alert)
                    Text("PDF").font(.system(size: size * 0.22, weight: .bold)).foregroundStyle(.white)
                }
                .frame(width: size * 0.75, height: size)
            } else if let img = Self.load(url, max: size * 3) {
                img.resizable().scaledToFill()
                    .frame(width: size * (size > 100 ? 1.4 : 1), height: size)
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            } else {
                // 还没从 iCloud 下载下来
                ZStack {
                    RoundedRectangle(cornerRadius: 6).fill(Color.sunken)
                    Image(systemName: "icloud.and.arrow.down").foregroundStyle(Color.fg2)
                }
                .frame(width: size, height: size)
                .onAppear { try? FileManager.default.startDownloadingUbiquitousItem(at: url) }
            }
        }
    }

    static func load(_ url: URL, max: CGFloat) -> Image? {
        guard let src = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        let opts: [CFString: Any] = [kCGImageSourceCreateThumbnailFromImageAlways: true,
                                     kCGImageSourceCreateThumbnailWithTransform: true,
                                     kCGImageSourceThumbnailMaxPixelSize: Int(max)]
        guard let cg = CGImageSourceCreateThumbnailAtIndex(src, 0, opts as CFDictionary) else { return nil }
        return Image(decorative: cg, scale: 1)
    }
}

// MARK: - 每笔账：小票发票 + 报销

/// 流水详情里的两块：挂的小票 / 发票（点开看大图，长按 / 右键拿掉），和报销状态。
struct PaperworkSection: View {
    @Environment(LedgerModel.self) var model
    let tx: FinanceCore.Transaction
    @State private var preview: URL?
    @State private var pickedPhoto: PhotosPickerItem?
    @State private var importKind: Attachment.Kind?
    @State private var showCamera = false
    @State private var to = ""

    var body: some View {
        let p = model.ledger.paperwork(for: tx.id)
        let files = p?.attachments ?? []
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(files.isEmpty ? tr("小票和发票") : tr("小票和发票 · \(files.count) 张")).font(.subheadline.weight(.semibold))
                    Spacer()
                    if model.isPhoneLinked || model.attachmentsFolder?.path.contains("Mobile Documents") == true {
                        Label(tr("跟着这笔账同步"), systemImage: "icloud").font(.caption).foregroundStyle(Color.fg2)
                    }
                }
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(files) { a in
                            if let url = model.attachmentURL(a.file) {
                                Button { preview = url } label: {
                                    VStack(spacing: 4) {
                                        AttachmentThumb(url: url, size: 64)
                                        Text(a.kind.label).font(.caption2).foregroundStyle(Color.fg2)
                                    }
                                }
                                .buttonStyle(.plain)
                                .contextMenu {
                                    Button(role: .destructive) {
                                        model.perform { try $0.detach(a.id, from: tx.id, author: model.author) }
                                    } label: { Label(tr("从这笔账上拿掉"), systemImage: "trash") }
                                }
                                .accessibilityLabel(a.name ?? a.kind.label)
                            }
                        }
                        addTile(tr("上传发票"), symbol: "plus") { importKind = .invoice }
                        photoTile
                    }
                }
            }
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(tr("报销")).font(.subheadline.weight(.semibold))
                    Spacer()
                    if let st = p?.reimburse, st != .none { ReimburseTag(status: st) }
                }
                Picker(tr("报销到哪一步"), selection: Binding(get: { p?.reimburse ?? .none }, set: { set($0) })) {
                    ForEach(ReimburseStatus.allCases, id: \.self) { Text(trKey($0.label)).tag($0) }
                }
                .pickerStyle(.segmented).labelsHidden()
                .accessibilityIdentifier("reimburseStatus")
                if let p, p.reimburse != .none {
                    HStack {
                        Text(tr("找谁报")).foregroundStyle(Color.fg2)
                        TextField(tr("公司、店名、朋友"), text: $to)
                            .multilineTextAlignment(.trailing)
                            .onSubmit { saveTo() }
                    }
                    if p.reimburse == .toSubmit && !p.attachments.contains(where: { $0.kind == .invoice }) {
                        Text(tr("还没挂发票：补上再交会顺利一点。")).font(.caption).foregroundStyle(Color.warn)
                    }
                }
            }
        }
        .font(.callout)
        .onAppear { to = p?.reimburseTo ?? "" }
        .quickLookPreview($preview)
        .fileImporter(isPresented: Binding(get: { importKind != nil }, set: { if !$0 { importKind = nil } }),
                      allowedContentTypes: [.pdf, .image]) { result in
            if case .success(let url) = result { model.attach(file: url, kind: importKind ?? .invoice, to: tx.id) }
            importKind = nil
        }
        .onChange(of: pickedPhoto) { _, item in
            guard let item else { return }
            Task {
                if let data = try? await item.loadTransferable(type: Data.self) { model.attach(data: data, kind: .receipt, to: tx.id) }
                pickedPhoto = nil
            }
        }
        #if os(iOS)
        .fullScreenCover(isPresented: $showCamera) {
            CameraPicker { data in model.attach(data: data, kind: .receipt, to: tx.id) }.ignoresSafeArea()
        }
        #endif
    }

    @ViewBuilder private var photoTile: some View {
        #if os(iOS)
        Menu {
            if UIImagePickerController.isSourceTypeAvailable(.camera) {
                Button { showCamera = true } label: { Label(tr("拍小票"), systemImage: "camera") }
            }
            PhotosPicker(selection: $pickedPhoto, matching: .images) { Label(tr("从照片里选"), systemImage: "photo") }
        } label: { tileLabel(tr("拍小票"), symbol: "camera") }
        #else
        addTile(tr("加小票"), symbol: "doc.viewfinder") { importKind = .receipt }
        #endif
    }

    private func addTile(_ title: String, symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) { tileLabel(title, symbol: symbol) }.buttonStyle(.plain)
    }

    private func tileLabel(_ title: String, symbol: String) -> some View {
        VStack(spacing: 6) {
            Image(systemName: symbol).font(.title3)
            Text(title).font(.caption)
        }
        .foregroundStyle(Color.brand)
        .frame(width: 72, height: 80)
        .background(RoundedRectangle(cornerRadius: 10).strokeBorder(Color.brand.opacity(0.4), style: StrokeStyle(lineWidth: 1, dash: [4])))
    }

    private func set(_ status: ReimburseStatus) {
        model.perform { try $0.setReimbursement([tx.id], status: status, to: to.isEmpty ? nil : to, author: model.author) }
    }

    private func saveTo() {
        guard let p = model.ledger.paperwork(for: tx.id), (p.reimburseTo ?? "") != to else { return }
        model.perform { try $0.setReimbursement([tx.id], status: p.reimburse, to: to, author: model.author) }
    }
}

struct ReimburseTag: View {
    let status: ReimburseStatus
    var body: some View {
        Text(trKey(status.label)).font(.caption.weight(.semibold))
            .padding(.horizontal, 8).padding(.vertical, 3)
            .foregroundStyle(color)
            .background(color.opacity(0.14), in: Capsule())
    }
    var color: Color {
        switch status {
        case .toSubmit: .warn
        case .submitted: .ai
        case .paid: .income
        case .none: .fg2
        }
    }
}

// MARK: - 报销清单

/// 报销：还有多少钱要收回来？三块大数字（待提交 / 已提交 / 已到账），下面按状态分组的清单，右上角导出报销单。
struct ReimbursementPage: View {
    @Environment(LedgerModel.self) var model
    var embedded = false
    @State private var exported: [URL] = []
    @State private var exportedFolder: URL?

    var body: some View {
        let s = model.ledger.reimbursementSummary
        let all = model.ledger.reimbursements()
        let content = VStack(alignment: .leading, spacing: Kit.gap) {
            if all.isEmpty {
                KitEmptyState(symbol: "doc.text", title: tr("还没有要报销的账"),
                              message: tr("出差、帮公司垫的钱：点开那笔账，在「报销」里选「待提交」，挂上小票和发票。这里会算好还有多少钱要收回来，一键导出给公司。"),
                              prompt: "帮我把这个月出差的几笔标成要报销", page: "报销")
                    .kitCard()
            } else {
                hero(s)
                ForEach([ReimburseStatus.toSubmit, .submitted, .paid], id: \.self) { st in
                    let items = all.filter { $0.paperwork.reimburse == st }
                    if !items.isEmpty { group(st, items) }
                }
            }
        }
        Group {
            if embedded { content } else { content.kitPage() }
        }
        .toolbar {
            #if os(macOS)
            if !embedded {
                ToolbarItem(placement: .primaryAction) { exportButton(all) }
            }
            #endif
        }
    }

    private func hero(_ s: ReimbursementSummary) -> some View {
        #if os(macOS)
        HStack(spacing: Kit.gap) {
            tile(.toSubmit, s.toSubmit, tr("交给公司前先导出"))
            tile(.submitted, s.submitted, tr("到账后标「已到账」"))
            tile(.paid, s.paid, "")
        }
        #else
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(tr("还有这么多钱要收回来")).font(.subheadline).foregroundStyle(Color.fg2)
                    Text(s.outstanding.formatted).font(.system(size: 38, weight: .bold, design: .rounded)).monospacedDigit()
                }
                Spacer()
                XiaxiaAvatar(size: 56)
            }
            GeometryReader { geo in
                let total = max(1, Double((s.outstanding + s.paid).cents))
                HStack(spacing: 2) {
                    Capsule().fill(Color.warn).frame(width: geo.size.width * Double(s.toSubmit.cents) / total)
                    Capsule().fill(Color.ai).frame(width: geo.size.width * Double(s.submitted.cents) / total)
                    Capsule().fill(Color.income).frame(width: geo.size.width * Double(s.paid.cents) / total)
                }
            }
            .frame(height: 8)
            HStack(spacing: 12) {
                legend(.warn, tr("待提交")); legend(.ai, tr("已提交")); legend(.income, tr("已到账"))
            }
            exportButton(model.ledger.reimbursements())
        }
        .kitCard()
        #endif
    }

    private func legend(_ c: Color, _ t: String) -> some View {
        HStack(spacing: 4) { Circle().fill(c).frame(width: 7, height: 7); Text(t) }.font(.caption).foregroundStyle(Color.fg2)
    }

    private func tile(_ st: ReimburseStatus, _ m: Money, _ note: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 5) {
                Circle().fill(ReimburseTag(status: st).color).frame(width: 8, height: 8)
                Text(st == .submitted ? tr("已提交，等打钱") : trKey(st.label)).font(.subheadline).foregroundStyle(Color.fg2)
            }
            Text(m.formatted).font(.system(size: 30, weight: .bold, design: .rounded)).monospacedDigit()
            Text(tr("\(model.ledger.reimbursementSummary.counts[st] ?? 0) 笔") + (note.isEmpty ? "" : " · \(note)"))
                .font(.caption).foregroundStyle(Color.fg2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .kitCard()
    }

    private func group(_ st: ReimburseStatus, _ items: [ReimbursementItem]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(st == .submitted ? tr("已提交，等打钱") : trKey(st.label)).font(.subheadline.weight(.semibold))
                Spacer()
                Text(items.reduce(Money.zero) { $0 + $1.transaction.amount.magnitude }.formatted)
                    .font(.subheadline).foregroundStyle(Color.fg2).monospacedDigit()
            }
            VStack(spacing: 0) {
                ForEach(items) { item in
                    Button { model.showTransactions(TransactionFilter(ids: [item.id])) } label: { row(item) }
                        .buttonStyle(.plain)
                        .contextMenu { statusMenu(item) }
                    if item.id != items.last?.id { Divider() }
                }
            }
            .kitCard(padding: 10)
        }
    }

    private func row(_ item: ReimbursementItem) -> some View {
        let t = item.transaction, p = item.paperwork
        return HStack(spacing: 10) {
            CategoryIcon(category: t.category, size: 30)
            VStack(alignment: .leading, spacing: 2) {
                Text(Merchant.display(t.description)).lineLimit(1)
                HStack(spacing: 6) {
                    Text(t.date.friendly)
                    if let to = p.reimburseTo { Text("· \(to)").lineLimit(1) }
                    if !p.attachments.isEmpty { Label("\(p.attachments.count)", systemImage: "paperclip") }
                    if p.reimburse == .toSubmit && !p.attachments.contains(where: { $0.kind == .invoice }) {
                        Text(tr("差发票")).foregroundStyle(Color.warn)
                    }
                }
                .font(.caption).foregroundStyle(Color.fg2)
            }
            Spacer(minLength: 8)
            #if os(macOS)
            Menu { statusMenu(item) } label: { ReimburseTag(status: p.reimburse) }
                .menuStyle(.button).buttonStyle(.plain).menuIndicator(.hidden).fixedSize()
            #endif
            Text(t.amount.magnitude.formatted).font(.kitAmount)
        }
        .padding(.vertical, 8).padding(.horizontal, 6)
        .contentShape(Rectangle())
    }

    @ViewBuilder private func statusMenu(_ item: ReimbursementItem) -> some View {
        ForEach(ReimburseStatus.allCases, id: \.self) { st in
            Button(trKey(st.label)) {
                model.perform { try $0.setReimbursement([item.id], status: st, author: model.author) }
            }
            .disabled(st == item.paperwork.reimburse)
        }
    }

    /// 导出报销单：待提交的那几笔（没有就全部）做成 CSV + 凭证副本。Mac 放进「下载」并在访达里打开；iPhone 弹分享。
    @ViewBuilder private func exportButton(_ all: [ReimbursementItem]) -> some View {
        let toSubmit = all.filter { $0.paperwork.reimburse == .toSubmit }
        let items = toSubmit.isEmpty ? all : toSubmit
        #if os(macOS)
        Button {
            let base = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first ?? FileManager.default.temporaryDirectory
            do {
                let r = try LedgerFiles.exportReimbursements(items, ledger: model.ledger, attachments: model.attachmentsFolder, into: base)
                NSWorkspace.shared.activateFileViewerSelecting([r.folder])
                model.toast = LedgerModel.Toast(text: tr("报销单放进「下载」了：\(r.folder.lastPathComponent)"), changeID: nil)
            } catch {
                model.toast = LedgerModel.Toast(text: error.localizedDescription, changeID: nil, isError: true)
            }
        } label: { Label(tr("导出报销单"), systemImage: "square.and.arrow.up") }
            .buttonStyle(.borderedProminent).tint(Color.brand)
            .disabled(items.isEmpty)
        #else
        if let r = try? LedgerFiles.exportReimbursements(items, ledger: model.ledger, attachments: model.attachmentsFolder,
                                                         into: FileManager.default.temporaryDirectory.appendingPathComponent("export-\(items.count)-\(items.first?.id.uuidString.prefix(6) ?? "")")) {
            ShareLink(items: r.files) {
                Label(tr("导出报销单"), systemImage: "square.and.arrow.up").frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent).tint(Color.brand).controlSize(.large)
        }
        #endif
    }
}

// MARK: - iPhone：接上 iCloud 文件夹

#if os(iOS)
/// 设置里的「和电脑同步」：选一下 iCloud 云盘里的「夏夏账本」文件夹，手机就和电脑看同一本账。
struct PhoneSyncSettings: View {
    @Environment(LedgerModel.self) var model
    @State private var picking = false
    @State private var message: String?

    /// 正在用 app 自己的 iCloud 容器自动同步：不出「选文件夹」「断开」。
    private var isAutoSynced: Bool { (model.store as? PhoneSyncStore).map { LedgerStores.isAppContainer($0.folder) } ?? false }

    var body: some View {
        Form {
            Section {
                if let s = model.store as? PhoneSyncStore {
                    Label(tr("已经和电脑同步"), systemImage: "checkmark.icloud.fill").foregroundStyle(Color.income)
                    if LedgerStores.isAppContainer(s.folder) {
                        // 带 iCloud 权限的版本：自动用 app 自己的 iCloud 位置，不用选文件夹。
                        LabeledContent(tr("方式"), value: tr("iCloud 自动同步"))
                    } else {
                        LabeledContent(tr("文件夹"), value: "iCloud 云盘 › \(s.folder.lastPathComponent)")
                    }
                    LabeledContent(tr("还没被电脑收走的改动"), value: "\(s.waitingNotes)")
                    if s.noLedgerYet {
                        Text(tr("这个文件夹里还没有账本。先在电脑上打开一次夏夏账本，或者换一个文件夹。")).foregroundStyle(Color.warn)
                    } else if s.waitingForDownload {
                        Text(tr("账本正在从 iCloud 下载，先显示上次的。")).foregroundStyle(Color.fg2)
                    }
                } else {
                    Text(tr("现在账本只在这台 iPhone 上。接上电脑的 iCloud 文件夹后，手机和电脑看同一本账。"))
                }
            } footer: {
                Text(tr("手机上记的东西先存成一张张小纸条，放在同一个文件夹里；电脑上的夏夏账本一打开就收进账本。两边同时记也不会互相覆盖。"))
            }
            if !isAutoSynced { Section {
                Button { picking = true } label: {
                    Label(model.isPhoneLinked ? tr("换一个文件夹") : tr("选择 iCloud 云盘里的「夏夏账本」文件夹"), systemImage: "folder.badge.plus")
                }
                .accessibilityIdentifier("linkICloudFolder")
                if model.isPhoneLinked {
                    Button(role: .destructive) {
                        PhoneFolderLink.forget()
                        model.useStore(LedgerStores.appStore())
                        message = tr("断开了。手机改回用自己本机的账本。")
                    } label: { Label(tr("断开，只用手机上的账本"), systemImage: "icloud.slash") }
                }
            } footer: {
                Text(tr("怎么选：点上面的按钮 → 左上角「浏览」→ iCloud 云盘 → 点一下「夏夏账本」文件夹 → 右上角「打开」。"))
            } }
            if let message { Section { Text(message) } }
        }
        .navigationTitle(tr("和电脑同步"))
        .fileImporter(isPresented: $picking, allowedContentTypes: [.folder]) { result in
            guard case .success(let url) = result else { return }
            guard PhoneFolderLink.looksLikeLedgerFolder(url) else {
                message = tr("这个文件夹里没有账本。要选的是 iCloud 云盘里那个叫「夏夏账本」的文件夹。")
                return
            }
            do {
                try PhoneFolderLink.remember(url)
                if let folder = PhoneFolderLink.resolve() {
                    model.useStore(LedgerStores.phoneStore(folder))
                    message = tr("接上了：现在和电脑看同一本账。")
                }
            } catch {
                message = error.localizedDescription
            }
        }
    }
}
#endif
