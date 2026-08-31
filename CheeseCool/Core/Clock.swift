import Foundation

public protocol MonotonicClock: Sendable {
    var now: TimeInterval { get }
}

public struct SystemMonotonicClock: MonotonicClock, Sendable {
    public init() {}
    public var now: TimeInterval { ProcessInfo.processInfo.systemUptime }
}

public enum ClockError: Error, Equatable {
    case cannotMoveBackwards
}

public final class ManualClock: MonotonicClock, @unchecked Sendable {
    private let lock = NSLock()
    private var currentTime: TimeInterval

    public init(now: TimeInterval = 0) {
        self.currentTime = now
    }

    public var now: TimeInterval {
        lock.lock()
        defer { lock.unlock() }
        return currentTime
    }

    @discardableResult
    public func advance(by seconds: TimeInterval) throws -> TimeInterval {
        guard seconds >= 0, seconds.isFinite else { throw ClockError.cannotMoveBackwards }
        lock.lock()
        defer { lock.unlock() }
        currentTime += seconds
        return currentTime
    }
}
