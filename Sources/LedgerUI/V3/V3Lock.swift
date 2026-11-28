#if os(macOS)
import AppKit
import FinanceCore
import LocalAuthentication
import SwiftUI

// 上锁：打开 app 时要解锁。解锁用系统的验证（指纹，或者这台 Mac 的登录密码），app 自己不存、不碰任何密码。
// 该不该锁的判断在核心（FinanceCore/AppLock.swift）；锁着的时候窗口里只画锁屏，后面的内容根本不画。

/// 做验证的人。app 里是系统；测试里用假的。
protocol V3Authenticator: Sendable {
    /// 这台 Mac 能不能验证（没设登录密码就不能）。
    func available() -> Bool
    func authenticate(reason: String) async -> Bool
}

struct V3SystemAuthenticator: V3Authenticator {
    func available() -> Bool { LAContext().canEvaluatePolicy(.deviceOwnerAuthentication, error: nil) }
    func authenticate(reason: String) async -> Bool {
        let ctx = LAContext()
        guard ctx.canEvaluatePolicy(.deviceOwnerAuthentication, error: nil) else { return false }
        return (try? await ctx.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason)) ?? false
    }
}

/// 测试、离屏出图用：想让它过就过。
struct V3FakeAuthenticator: V3Authenticator {
    var ok = true
    func available() -> Bool { true }
    func authenticate(reason: String) async -> Bool { ok }
}

extension V3State {
    private static let enabledKey = "xiaxia.v3.lock.enabled", graceKey = "xiaxia.v3.lock.grace"
    private static var testing: Bool { NSClassFromString("XCTestCase") != nil }

    static func defaultAuthenticator() -> V3Authenticator { testing ? V3FakeAuthenticator() : V3SystemAuthenticator() }

    /// 启动时读回上次的设置（开关不是秘密，放偏好设置里）。`-XiaxiaV3NoLock` 这次启动不锁（万一系统验证弹不出来，留一条路）。
    static func savedLockPolicy() -> AppLockPolicy {
        guard !testing, !ProcessInfo.processInfo.arguments.contains("-XiaxiaV3NoLock") else { return AppLockPolicy() }
        let d = UserDefaults.standard
        return AppLockPolicy(enabled: d.bool(forKey: enabledKey), grace: d.object(forKey: graceKey) == nil ? 300 : d.double(forKey: graceKey))
    }

    private func saveLockPolicy() {
        guard !Self.testing else { return }
        UserDefaults.standard.set(lockPolicy.enabled, forKey: Self.enabledKey)
        UserDefaults.standard.set(lockPolicy.grace, forKey: Self.graceKey)
    }

    /// 有件事发生了（启动、睡醒、从后台回来）：照规则决定锁不锁。
    func lockIfNeeded(_ event: AppLockPolicy.Event) {
        guard lockPolicy.locks(on: event), !locked else { return }
        // 锁上：小窗、聊天、消息卡都收起来，后面什么都不留
        locked = true
        showAdd = false; sheet = nil; chatOpen = false; sayCardID = nil; toast = nil; moment = nil
    }

    /// 点「解锁」：过了才打开；没过或取消就停在锁屏，什么都不说。
    func unlock() async {
        guard locked, !unlocking else { return }
        unlocking = true
        let ok = await authenticator.authenticate(reason: "解锁夏夏账本")
        unlocking = false
        if ok { withAnimation(.easeOut(duration: 0.2)) { locked = false } }
    }

    /// 设置里开关「打开 app 时要解锁」：开和关都要先验证一次。返回改成了没有。
    @discardableResult
    func setLock(enabled: Bool) async -> Bool {
        guard enabled != lockPolicy.enabled else { return true }
        guard authenticator.available() else { fail("这台 Mac 还没设登录密码，上不了锁"); return false }
        guard await authenticator.authenticate(reason: enabled ? "打开夏夏账本的锁" : "关掉夏夏账本的锁") else { return false }
        lockPolicy.enabled = enabled
        saveLockPolicy()
        say(enabled ? "好，以后打开要解锁" : "好，不用解锁了")
        return true
    }

    func setLock(grace: TimeInterval) {
        lockPolicy = AppLockPolicy(enabled: lockPolicy.enabled, grace: grace)
        saveLockPolicy()
    }

    /// 立即上锁（⌘L）。没开锁的功能就不动。
    func lockNow() {
        guard lockPolicy.enabled else { say("还没开上锁：设置 → 隐私与语言"); return }
        lockIfNeeded(.wake)
    }

    func appWentAway() { awaySince = Date() }
    func appCameBack() {
        guard let since = awaySince else { return }
        awaySince = nil
        lockIfNeeded(.returned(after: Date().timeIntervalSince(since)))
    }
}

/// 锁屏：只有图标、一句话、一个按钮。后面的内容不画。
struct V3LockScreen: View {
    @Environment(V3State.self) private var state
    var body: some View {
        VStack(spacing: 16) {
            V3.image("head-calm").resizable().scaledToFit().frame(width: 72, height: 64)
                .frame(width: 96, height: 96)
                .background(RoundedRectangle(cornerRadius: 26, style: .continuous).fill(.white).overlay(RoundedRectangle(cornerRadius: 26, style: .continuous).strokeBorder(V3.ink, lineWidth: 2.5)))
                .overlay(alignment: .bottomTrailing) {
                    Image(systemName: "lock.fill").font(.system(size: 13, weight: .bold)).foregroundStyle(.white).frame(width: 28, height: 28)
                        .background(Circle().fill(V3.navy).overlay(Circle().strokeBorder(.white, lineWidth: 2))).offset(x: 6, y: 6)
                }
            Text("夏夏账本已上锁").font(V3.font(24, .heavy)).foregroundStyle(V3.ink)
            Button(state.unlocking ? "正在验证…" : "解锁") { Task { await state.unlock() } }
                .buttonStyle(.v3(.primary, .big)).keyboardShortcut(.defaultAction).disabled(state.unlocking)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(V3.bg)
        .accessibilityElement(children: .contain)
    }
}

/// 听系统的动静：app 去了后台、回来了、Mac 睡醒了、屏幕解锁了。
struct V3LockWatcher: ViewModifier {
    @Environment(V3State.self) private var state
    func body(content: Content) -> some View {
        content
            .onReceive(NotificationCenter.default.publisher(for: NSApplication.didResignActiveNotification)) { _ in state.appWentAway() }
            .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in state.appCameBack() }
            .onReceive(NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.willSleepNotification)) { _ in state.lockIfNeeded(.wake) }
            .onReceive(NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.screensDidSleepNotification)) { _ in state.lockIfNeeded(.wake) }
            .onReceive(NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.sessionDidResignActiveNotification)) { _ in state.lockIfNeeded(.wake) }
            .onReceive(DistributedNotificationCenter.default().publisher(for: Notification.Name("com.apple.screenIsLocked"))) { _ in state.lockIfNeeded(.wake) }
    }
}
#endif
