import Perception
import SwiftUI

// Swift Testing runs on macOS 14+, where Perception.Bindable is obsoleted.
// Keep the real property wrappers and the iOS 15/16 backport compile path.
#if os(macOS)
@available(macOS 14, *)
typealias TestBindable<Value> = SwiftUI.Bindable<Value>
#else
@available(iOS, introduced: 15, obsoleted: 17)
typealias TestBindable<Value> = Perception.Bindable<Value>
#endif
