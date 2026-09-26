import UserMessagingPlatform
import XCTest

@testable import GoogleMobileAdsWrapper

@MainActor
final class UMPConsentClientTests: XCTestCase {
    func testProductionDefaultsDoNotAddDebugOrCrossAppConsentSettings() {
        let parameters = UMPConsentClient.parameters(for: .init())
        XCTAssertFalse(parameters.isTaggedForUnderAgeOfConsent)
        XCTAssertNil(parameters.debugSettings)
        XCTAssertNil(parameters.consentSyncID)
    }

    func testExplicitDebugSettingsAndUnderAgeFlagReachSDK() {
        let cases: [(GoogleMobileAdsConsentRequest.DebugSettings.Geography, DebugGeography)] = [
            (.disabled, .disabled), (.eea, .EEA), (.regulatedUSState, .regulatedUSState), (.other, .other)
        ]
        for (geography, sdkGeography) in cases {
            let parameters = UMPConsentClient.parameters(for: .init(
                isTaggedForUnderAgeOfConsent: true,
                debugSettings: .init(geography: geography, testDeviceIdentifiers: ["test-device"])
            ))
            XCTAssertTrue(parameters.isTaggedForUnderAgeOfConsent)
            XCTAssertEqual(parameters.debugSettings?.geography, sdkGeography)
            XCTAssertEqual(parameters.debugSettings?.testDeviceIdentifiers, ["test-device"])
            XCTAssertNil(parameters.consentSyncID)
        }
    }

    func testSDKStatusMappingPreservesAllKnownStates() {
        XCTAssertEqual(UMPConsentClient.status(.unknown), .unknown)
        XCTAssertEqual(UMPConsentClient.status(.required), .required)
        XCTAssertEqual(UMPConsentClient.status(.notRequired), .notRequired)
        XCTAssertEqual(UMPConsentClient.status(.obtained), .obtained)
        XCTAssertEqual(UMPConsentClient.privacyOptions(.unknown), .unknown)
        XCTAssertEqual(UMPConsentClient.privacyOptions(.required), .required)
        XCTAssertEqual(UMPConsentClient.privacyOptions(.notRequired), .notRequired)
    }
}
