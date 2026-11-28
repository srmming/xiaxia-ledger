import Foundation

/// 上锁：什么时候该把 app 锁上。只管判断，不碰密码（解锁交给系统：指纹或这台 Mac 的登录密码）。
public struct AppLockPolicy: Equatable, Sendable {
    /// 打开 app 时要不要解锁。
    public var enabled: Bool
    /// 离开多久后再锁（秒）：0 = 立刻。
    public var grace: TimeInterval

    public static let graceChoices: [(title: String, seconds: TimeInterval)] = [("立刻", 0), ("1 分钟", 60), ("5 分钟", 300), ("15 分钟", 900)]

    public init(enabled: Bool = false, grace: TimeInterval = 300) {
        self.enabled = enabled
        self.grace = Self.graceChoices.contains { $0.seconds == grace } ? grace : 300
    }

    public enum Event: Equatable, Sendable {
        /// app 刚启动。
        case launch
        /// Mac 睡眠或锁屏以后回来。
        case wake
        /// app 从后台回到前面，离开了这么久。
        case returned(after: TimeInterval)
    }

    /// 这件事发生时要不要锁上。
    public func locks(on event: Event) -> Bool {
        guard enabled else { return false }
        switch event {
        case .launch, .wake: return true
        case .returned(let away): return away >= grace
        }
    }
}
