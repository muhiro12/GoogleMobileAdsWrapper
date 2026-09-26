import UIKit

/// Explicit UMP operations. Does not start the ads SDK, request ads, or persist consent.
@MainActor
public final class GoogleMobileAdsConsentController {
    /// Reuse this instance to serialize access to the process-wide UMP SDK.
    public static let shared = GoogleMobileAdsConsentController(client: UMPConsentClient())

    public enum OperationError: Error, Equatable, Sendable {
        case operationInProgress
    }

    /// Reads the SDK now, including after failed requests or privacy-option changes.
    /// This is not an observable or durable consent cache.
    public var state: GoogleMobileAdsConsentState {
        client.state
    }

    public private(set) var isPerformingOperation = false
    private let client: any GoogleMobileAdsConsentClient

    init(client: any GoogleMobileAdsConsentClient) {
        self.client = client
    }

    /// Request an update each app session before loading a required form.
    /// SDK errors are propagated; consult `state.canRequestAds` after an error too.
    @discardableResult
    public func requestConsentInfoUpdate(
        _ request: GoogleMobileAdsConsentRequest = .init()
    ) async throws -> GoogleMobileAdsConsentState {
        try await perform {
            try await self.client.requestConsentInfoUpdate(request)
        }
    }

    /// Lets UMP decide whether to present a form. Call after a successful update.
    /// A nil presenter uses UMP's default window selection; pass a scene's host explicitly when needed.
    @discardableResult
    public func loadAndPresentIfRequired(
        from viewController: UIViewController? = nil
    ) async throws -> GoogleMobileAdsConsentState {
        try await perform {
            try await self.client.loadAndPresentIfRequired(from: viewController)
        }
    }

    /// Present only in response to a user action when privacy options are required.
    @discardableResult
    public func presentPrivacyOptions(
        from viewController: UIViewController? = nil
    ) async throws -> GoogleMobileAdsConsentState {
        try await perform {
            try await self.client.presentPrivacyOptions(from: viewController)
        }
    }

    private func perform(
        _ operation: @MainActor () async throws -> Void
    ) async throws -> GoogleMobileAdsConsentState {
        try Task.checkCancellation()
        guard !isPerformingOperation else {
            throw OperationError.operationInProgress
        }
        isPerformingOperation = true
        defer {
            isPerformingOperation = false
        }
        try await operation()
        // UMP cannot cancel an in-flight request or dismiss a form through this API.
        // Retain the operation gate until the SDK finishes, even when the task is cancelled.
        try Task.checkCancellation()
        return state
    }
}
