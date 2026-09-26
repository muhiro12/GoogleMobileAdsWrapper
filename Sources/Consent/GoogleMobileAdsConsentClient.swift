import UIKit

/// Internal SDK seam for deterministic tests without account or network access.
@MainActor
protocol GoogleMobileAdsConsentClient {
    var state: GoogleMobileAdsConsentState { get }
    func requestConsentInfoUpdate(_ request: GoogleMobileAdsConsentRequest) async throws
    func loadAndPresentIfRequired(from viewController: UIViewController?) async throws
    func presentPrivacyOptions(from viewController: UIViewController?) async throws
}
