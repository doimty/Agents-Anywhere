import Foundation

/// Wire timestamps are compared on every sidebar sort and dashboard tick. The
/// server repeats the same strings across pushes, so each distinct value is
/// parsed once; the format styles are built once instead of per comparison.
///
/// `Mutex` is iOS 18+, so the cache uses a small locked holder instead. It is
/// `@unchecked Sendable` because all access goes through `NSLock`.
nonisolated enum V2Timestamp {
    private static let fractional = Date.ISO8601FormatStyle(includingFractionalSeconds: true)
    private static let plain = Date.ISO8601FormatStyle()
    private static let cache = Cache()
    private static let capacity = 4096

    /// Seconds since 1970, or nil when the value is missing or not ISO 8601.
    static func seconds(_ raw: String?) -> TimeInterval? {
        guard let raw, !raw.isEmpty else { return nil }
        if let cached = cache.value(for: raw) { return cached.isNaN ? nil : cached }
        let parsed = (try? fractional.parse(raw)) ?? (try? plain.parse(raw))
        let value = parsed?.timeIntervalSince1970 ?? .nan
        cache.store(value, for: raw, capacity: capacity)
        return parsed == nil ? nil : value
    }

    static func date(_ raw: String?) -> Date? {
        seconds(raw).map { Date(timeIntervalSince1970: $0) }
    }

    private final class Cache: @unchecked Sendable {
        private let lock = NSLock()
        private var store: [String: TimeInterval] = [:]

        func value(for key: String) -> TimeInterval? {
            lock.lock()
            defer { lock.unlock() }
            return store[key]
        }

        func store(_ value: TimeInterval, for key: String, capacity: Int) {
            lock.lock()
            defer { lock.unlock() }
            if store.count >= capacity { store.removeAll(keepingCapacity: true) }
            store[key] = value
        }
    }
}
