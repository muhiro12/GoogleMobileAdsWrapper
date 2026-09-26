import UIKit

@testable import GoogleMobileAdsWrapper

@MainActor
final class ConsentClientStub: GoogleMobileAdsConsentClient {
    var state = GoogleMobileAdsConsentState(
        status: .unknown,
        canRequestAds: false,
        privacyOptionsRequirement: .unknown
    )
    var nextState: GoogleMobileAdsConsentState?
    var error: (any Error)?
    var suspends = false
    var calls: [String] = []
    var receivedRequest: GoogleMobileAdsConsentRequest?
    var presenter: UIViewController?
    private var pending: CheckedContinuation<Void, any Error>?
    private var startWaiter: CheckedContinuation<Void, Never>?

    func requestConsentInfoUpdate(_ request: GoogleMobileAdsConsentRequest) async throws {
        receivedRequest = request
        try await perform("update")
    }

    func loadAndPresentIfRequired(from viewController: UIViewController?) async throws {
        presenter = viewController
        try await perform("requiredForm")
    }

    func presentPrivacyOptions(from viewController: UIViewController?) async throws {
        presenter = viewController
        try await perform("privacyOptions")
    }

    func waitUntilSuspended() async {
        guard pending == nil else {
            return
        }
        await withCheckedContinuation { continuation in
            startWaiter = continuation
        }
    }

    func finish() {
        let continuation = pending
        pending = nil
        continuation?.resume()
    }

    private func perform(_ name: String) async throws {
        calls.append(name)
        if suspends {
            try await withCheckedThrowingContinuation { continuation in
                pending = continuation
                startWaiter?.resume()
                startWaiter = nil
            }
        }
        if let nextState {
            state = nextState
        }
        if let error {
            throw error
        }
    }
}
