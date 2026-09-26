/// A snapshot of UMP state. Advertisement eligibility comes from the SDK directly.
public struct GoogleMobileAdsConsentState: Equatable, Sendable {
    public enum Status: Equatable, Sendable {
        case unknown
        case required
        case notRequired
        /// Consent was collected; this does not mean personalized ads were accepted.
        case obtained
    }

    public enum PrivacyOptionsRequirement: Equatable, Sendable {
        case unknown
        case required
        case notRequired
    }

    public let status: Status
    public let canRequestAds: Bool
    public let privacyOptionsRequirement: PrivacyOptionsRequirement

    public init(
        status: Status,
        canRequestAds: Bool,
        privacyOptionsRequirement: PrivacyOptionsRequirement
    ) {
        self.status = status
        self.canRequestAds = canRequestAds
        self.privacyOptionsRequirement = privacyOptionsRequirement
    }
}
