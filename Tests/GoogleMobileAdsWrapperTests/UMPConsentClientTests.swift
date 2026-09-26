import Testing
import UserMessagingPlatform

@testable import GoogleMobileAdsWrapper

@MainActor
struct UMPConsentClientTests {
    @Test
    func `Production defaults do not add debug or cross app consent settings`() {
        let parameters = UMPConsentClient.parameters(for: .init())
        #expect(!parameters.isTaggedForUnderAgeOfConsent)
        #expect(parameters.debugSettings == nil)
        #expect(parameters.consentSyncID == nil)
    }

    @Test
    func `Explicit debug settings and under age flag reach SDK`() {
        let cases: [(GoogleMobileAdsConsentRequest.DebugSettings.Geography, DebugGeography)] = [
            (.disabled, .disabled), (.eea, .EEA), (.regulatedUSState, .regulatedUSState), (.other, .other)
        ]
        for (geography, sdkGeography) in cases {
            let parameters = UMPConsentClient.parameters(for: .init(
                isTaggedForUnderAgeOfConsent: true,
                debugSettings: .init(geography: geography, testDeviceIdentifiers: ["test-device"])
            ))
            #expect(parameters.isTaggedForUnderAgeOfConsent)
            #expect(parameters.debugSettings?.geography == sdkGeography)
            #expect(parameters.debugSettings?.testDeviceIdentifiers == ["test-device"])
            #expect(parameters.consentSyncID == nil)
        }
    }

    @Test
    func `SDK status mapping preserves all known states`() {
        #expect(UMPConsentClient.status(.unknown) == .unknown)
        #expect(UMPConsentClient.status(.required) == .required)
        #expect(UMPConsentClient.status(.notRequired) == .notRequired)
        #expect(UMPConsentClient.status(.obtained) == .obtained)
        #expect(UMPConsentClient.privacyOptions(.unknown) == .unknown)
        #expect(UMPConsentClient.privacyOptions(.required) == .required)
        #expect(UMPConsentClient.privacyOptions(.notRequired) == .notRequired)
    }
}
