public enum MainActorCallback {
    // Foundation callbacks can arrive on private queues; creating their outer closure here
    // prevents MainActor inheritance before the explicit hop can run.
    public nonisolated static func make(
        _ body: @escaping @MainActor @Sendable () -> Void
    ) -> @Sendable () -> Void {
        { Task { @MainActor in body() } }
    }

    public nonisolated static func make<Value: Sendable>(
        _ body: @escaping @MainActor @Sendable (Value) -> Void
    ) -> @Sendable (Value) -> Void {
        { value in Task { @MainActor in body(value) } }
    }

    public nonisolated static func make<First: Sendable, Second: Sendable>(
        _ body: @escaping @MainActor @Sendable (First, Second) -> Void
    ) -> @Sendable (First, Second) -> Void {
        { first, second in Task { @MainActor in body(first, second) } }
    }
}
