import Foundation

/// An internal recursive lock for the reflected-font cache. The protected value
/// never escapes except through the caller's synchronous critical section.
final class LockIsolated<Value>: @unchecked Sendable {
  private var value: Value
  private let lock = NSRecursiveLock()

  init(_ value: Value) { self.value = value }

  func withValue<Result>(_ operation: (inout Value) throws -> Result) rethrows -> Result {
    lock.lock()
    defer { lock.unlock() }
    return try operation(&value)
  }
}
