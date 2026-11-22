import GoogleMobileAds

/// Configures and starts the Google Mobile Ads SDK on behalf of the app.
@MainActor
public enum GoogleMobileAdsController {
    private static let initialization = GoogleMobileAdsInitialization {
        _ = await MobileAds.shared.start()
    }

    /// Controls SDK collection of coarse location when the app has location permission.
    /// Leave this unset to use the SDK's current configuration. Set it before the first
    /// SDK initialization to apply the selection to all ad requests.
    public static var coarseLocationCollectionEnabled: Bool {
        get {
            MobileAds.shared.requestConfiguration.coarseLocationCollectionEnabled
        }
        set {
            MobileAds.shared.requestConfiguration.coarseLocationCollectionEnabled = newValue
        }
    }

    /// Waits for SDK initialization to complete. Concurrent calls share one start.
    /// Complete consent and audience configuration before calling this method.
    /// Completion includes the SDK's initialization timeout; it does not guarantee
    /// that every mediation adapter is ready. Cancellation does not stop SDK work.
    public static func start() async throws {
        try await initialization.start()
    }
}

/// Shares process-wide initialization without tying its lifetime to one caller.
@MainActor
final class GoogleMobileAdsInitialization {
    private let operation: @MainActor () async -> Void
    private var task: Task<Void, Never>?

    init(operation: @escaping @MainActor () async -> Void) {
        self.operation = operation
    }

    func start() async throws {
        try Task.checkCancellation()
        let initialization: Task<Void, Never>
        if let task {
            initialization = task
        } else {
            initialization = Task { @MainActor [operation] in
                await operation()
            }
            task = initialization
        }
        await initialization.value
        try Task.checkCancellation()
    }
}
