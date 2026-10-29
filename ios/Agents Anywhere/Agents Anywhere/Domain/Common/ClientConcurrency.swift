import Foundation
#if canImport(Darwin)
import Darwin
#endif

/// Client scheduling values, not wire values. Kept independent of Swift's
/// iOS 16+ Duration so stored properties and injected sleepers are iOS 15-safe.
nonisolated struct ClientDuration: AdditiveArithmetic, Comparable, Hashable, Sendable {
    let nanoseconds: Int64
    static let zero = Self(nanoseconds: 0)

    private init(nanoseconds: Int64) { self.nanoseconds = nanoseconds }

    static func seconds(_ value: Double) -> Self {
        let scaled = (value * 1_000_000_000).rounded()
        precondition(scaled.isFinite && scaled >= Double(Int64.min) && scaled < Double(Int64.max),
                     "ClientDuration must be a finite, representable interval")
        return Self(nanoseconds: Int64(scaled))
    }
    static func seconds<T: BinaryInteger>(_ value: T) -> Self { seconds(Double(value)) }
    static func milliseconds(_ value: Double) -> Self { seconds(value / 1000) }
    static func milliseconds<T: BinaryInteger>(_ value: T) -> Self { milliseconds(Double(value)) }

    var timeInterval: TimeInterval { Double(nanoseconds) / 1_000_000_000 }
    var components: (seconds: Int64, attoseconds: Int64) {
        (nanoseconds / 1_000_000_000, (nanoseconds % 1_000_000_000) * 1_000_000_000)
    }

    static func < (lhs: Self, rhs: Self) -> Bool { lhs.nanoseconds < rhs.nanoseconds }
    static func + (lhs: Self, rhs: Self) -> Self {
        let (value, overflow) = lhs.nanoseconds.addingReportingOverflow(rhs.nanoseconds)
        precondition(!overflow, "ClientDuration overflow")
        return Self(nanoseconds: value)
    }
    static func - (lhs: Self, rhs: Self) -> Self {
        let (value, overflow) = lhs.nanoseconds.subtractingReportingOverflow(rhs.nanoseconds)
        precondition(!overflow, "ClientDuration overflow")
        return Self(nanoseconds: value)
    }
}

/// Monotonic, continuous time: wall-clock corrections do not change deadlines,
/// and Darwin's continuous clock includes device sleep, like ContinuousClock.
nonisolated struct ClientClock: Sendable {
    nonisolated struct Instant: Comparable, Hashable, Sendable {
        fileprivate let offset: TimeInterval
        static var now: Self { ClientClock.now }
        func advanced(by duration: ClientDuration) -> Self {
            Self(offset: offset + duration.timeInterval)
        }
        func duration(to other: Self) -> ClientDuration { .seconds(other.offset - offset) }
        static func - (lhs: Self, rhs: Self) -> ClientDuration { rhs.duration(to: lhs) }
        static func < (lhs: Self, rhs: Self) -> Bool { lhs.offset < rhs.offset }
    }

    static var now: Instant {
        #if canImport(Darwin)
        Instant(offset: Double(mach_continuous_time()) * ticksToSeconds)
        #else
        Instant(offset: ProcessInfo.processInfo.systemUptime)
        #endif
    }
    var now: Instant { Self.now }

    #if canImport(Darwin)
    private static let ticksToSeconds: Double = {
        var info = mach_timebase_info_data_t()
        mach_timebase_info(&info)
        return Double(info.numer) / Double(info.denom) / 1_000_000_000
    }()
    #endif
}

nonisolated enum ClientTask {
    /// No task/continuation of our own: the iOS 15 Swift concurrency runtime owns
    /// suspension and cancellation. Zero/past waits still check cancellation.
    static func sleep(for duration: ClientDuration) async throws {
        try Task.checkCancellation()
        guard duration > .zero else { return }
        try await Task.sleep(nanoseconds: UInt64(duration.nanoseconds))
        try Task.checkCancellation()
    }

    /// Recheck the monotonic deadline after waking rather than accumulating work
    /// time into the cadence. A late/past deadline never sleeps or busy-spins.
    static func sleep(until deadline: ClientClock.Instant) async throws {
        while true {
            try Task.checkCancellation()
            let remaining = ClientClock.now.duration(to: deadline)
            guard remaining > .zero else { return }
            try await sleep(for: remaining)
        }
    }
}

/// A small synchronous lock boundary for tokens, timestamp caches and test
/// counters. Never suspend or re-enter this holder inside withLock. The value
/// cannot be accessed except under the lock; no observable/UI state lives here.
nonisolated final class ClientMutex<Value: Sendable>: @unchecked Sendable {
    private let lock = NSLock()
    private var value: Value
    init(_ value: Value) { self.value = value }

    @discardableResult
    func withLock<Result>(_ body: (inout Value) throws -> Result) rethrows -> Result {
        lock.lock()
        defer { lock.unlock() }
        return try body(&value)
    }
}
