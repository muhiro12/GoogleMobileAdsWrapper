import Testing

@testable import GoogleMobileAdsWrapper

@MainActor
struct GoogleMobileAdsInitializationTests {
    @Test
    func concurrentAndRepeatedStartsShareOneInitialization() async throws {
        let gate = InitializationGate()
        let initialization = GoogleMobileAdsInitialization {
            await gate.run()
        }
        let first = Task { try await initialization.start() }
        let second = Task { try await initialization.start() }
        while gate.calls == 0 {
            await Task.yield()
        }
        #expect(gate.calls == 1)
        gate.finish()
        try await first.value
        try await second.value
        try await initialization.start()
        #expect(gate.calls == 1)
    }

    @Test
    func cancellingOneWaiterDoesNotCancelSharedInitialization() async throws {
        let gate = InitializationGate()
        let initialization = GoogleMobileAdsInitialization {
            await gate.run()
        }
        let cancelled = Task { try await initialization.start() }
        while gate.calls == 0 {
            await Task.yield()
        }
        cancelled.cancel()
        let other = Task { try await initialization.start() }
        gate.finish()
        await #expect(throws: CancellationError.self) {
            try await cancelled.value
        }
        try await other.value
        #expect(gate.calls == 1)
        #expect(!gate.wasCancelled)
    }

    @Test
    func anAlreadyCancelledCallerDoesNotStartTheSDK() async {
        let gate = InitializationGate()
        let initialization = GoogleMobileAdsInitialization {
            await gate.run()
        }
        let caller = Task {
            withUnsafeCurrentTask { task in
                task?.cancel()
            }
            try await initialization.start()
        }
        await #expect(throws: CancellationError.self) {
            try await caller.value
        }
        #expect(gate.calls == 0)
    }
}

@MainActor
private final class InitializationGate {
    var calls = 0
    var wasCancelled = false
    private var continuation: CheckedContinuation<Void, Never>?

    func run() async {
        calls += 1
        await withCheckedContinuation { continuation in
            self.continuation = continuation
        }
        wasCancelled = Task.isCancelled
    }

    func finish() {
        continuation?.resume()
        continuation = nil
    }
}
