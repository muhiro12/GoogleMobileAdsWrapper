import UIKit
import UserMessagingPlatform

@MainActor
struct UMPConsentClient: GoogleMobileAdsConsentClient {
    var state: GoogleMobileAdsConsentState {
        let information = ConsentInformation.shared
        return .init(
            status: Self.status(information.consentStatus),
            canRequestAds: information.canRequestAds,
            privacyOptionsRequirement: Self.privacyOptions(information.privacyOptionsRequirementStatus)
        )
    }

    func requestConsentInfoUpdate(_ request: GoogleMobileAdsConsentRequest) async throws {
        try await ConsentInformation.shared.requestConsentInfoUpdate(with: Self.parameters(for: request))
    }

    func loadAndPresentIfRequired(from viewController: UIViewController?) async throws {
        try await ConsentForm.loadAndPresentIfRequired(from: viewController)
    }

    func presentPrivacyOptions(from viewController: UIViewController?) async throws {
        try await ConsentForm.presentPrivacyOptionsForm(from: viewController)
    }

    static func parameters(for request: GoogleMobileAdsConsentRequest) -> RequestParameters {
        let parameters = RequestParameters()
        parameters.isTaggedForUnderAgeOfConsent = request.isTaggedForUnderAgeOfConsent
        if let requestedDebugSettings = request.debugSettings {
            let settings = DebugSettings()
            settings.testDeviceIdentifiers = requestedDebugSettings.testDeviceIdentifiers
            switch requestedDebugSettings.geography {
            case .disabled:
                settings.geography = .disabled
            case .eea:
                settings.geography = .EEA
            case .regulatedUSState:
                settings.geography = .regulatedUSState
            case .other:
                settings.geography = .other
            }
            parameters.debugSettings = settings
        }
        return parameters
    }

    static func status(_ status: ConsentStatus) -> GoogleMobileAdsConsentState.Status {
        switch status {
        case .unknown:
            .unknown
        case .required:
            .required
        case .notRequired:
            .notRequired
        case .obtained:
            .obtained
        @unknown default:
            .unknown
        }
    }

    static func privacyOptions(
        _ requirement: PrivacyOptionsRequirementStatus
    ) -> GoogleMobileAdsConsentState.PrivacyOptionsRequirement {
        switch requirement {
        case .unknown:
            .unknown
        case .required:
            .required
        case .notRequired:
            .notRequired
        @unknown default:
            .unknown
        }
    }
}
