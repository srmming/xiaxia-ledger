#if os(macOS)
import AppKit

/// 截图用：启动参数带 -XiaxiaSnapshot <文件.png>，几秒后把 app 自己的窗口画成图片存下来，然后退出。
/// 是 app 画自己的窗口，不用「屏幕录制」权限，GitHub 的 Mac 机器上也能截（screencapture 在那里只有黑屏）。
/// 弹着窗口（比如「连上你的 AI」）时另存一张 <文件>-sheet.png。
enum WindowSnapshot {
    static func schedule(to path: String, after seconds: Double = 6) {
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds) {
            let url = URL(fileURLWithPath: path)
            let windows = NSApp.windows
            guard let window = windows.first(where: { $0.isVisible && $0.canBecomeMain }) ?? windows.first(where: { $0.isVisible }) else {
                FileHandle.standardError.write(Data("没有可见窗口，截不了图（共 \(windows.count) 个窗口）\n".utf8))
                exit(3)
            }
            save(window, to: url)
            if let sheet = window.attachedSheet {
                save(sheet, to: url.deletingPathExtension().appendingPathExtension("sheet").appendingPathExtension("png"))
            }
            exit(0)
        }
    }

    private static func save(_ window: NSWindow, to url: URL) {
        guard let view = window.contentView?.superview ?? window.contentView,
              let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return }
        view.cacheDisplay(in: view.bounds, to: rep)
        do { try rep.representation(using: .png, properties: [:])?.write(to: url) }
        catch { FileHandle.standardError.write(Data("截图存不下：\(error)\n".utf8)) }
    }
}
#endif
