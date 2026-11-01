import Combine

/// Local view state. Used instead of `@State`, which is a macro in recent SDKs and needs
/// Xcode's SwiftUIMacros plugin — this keeps the project buildable with only the
/// Command Line Tools.
final class StateBox<Value>: ObservableObject {
    @Published var value: Value
    init(_ value: Value) { self.value = value }
}
