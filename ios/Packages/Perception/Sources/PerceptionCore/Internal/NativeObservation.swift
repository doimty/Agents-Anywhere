import Foundation

/// Debug-only regression switch: exercise the real backport registrar on a
/// modern simulator, where the system Observation implementation would otherwise
/// hide missing WithPerceptionTracking scopes. Production selection is unchanged.
@usableFromInline
let isNativeObservationEnabled: Bool = {
  #if DEBUG
    if ProcessInfo.processInfo.arguments.contains("--force-perception-backport") {
      return false
    }
  #endif
  return !isObservationBeta
}()
