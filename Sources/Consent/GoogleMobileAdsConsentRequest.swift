/// Caller-owned consent request settings. No cross-app consent identifier is sent.
public struct GoogleMobileAdsConsentRequest: Equatable, Sendable {
    /// Test-only overrides. Omit these settings in production requests.
    public struct DebugSettings: Equatable, Sendable {
        public enum Geography: Equatable, Sendable {
            case disabled
            case eea
            case regulatedUSState
            case other
        }

        public let geography: Geography
        public let testDeviceIdentifiers: [String]

        public init(
            geography: Geography = .disabled,
            testDeviceIdentifiers: [String] = []
        ) {
            self.geography = geography
            self.testDeviceIdentifiers = testDeviceIdentifiers
        }
    }

    public let isTaggedForUnderAgeOfConsent: Bool
    public let debugSettings: DebugSettings?

    public init(
        isTaggedForUnderAgeOfConsent: Bool = false,
        debugSettings: DebugSettings? = nil
    ) {
        self.isTaggedForUnderAgeOfConsent = isTaggedForUnderAgeOfConsent
        self.debugSettings = debugSettings
    }
}
