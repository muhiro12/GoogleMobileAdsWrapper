import UIKit
import XCTest

@testable import GoogleMobileAdsWrapper

@MainActor
final class GoogleMobileAdsConsentControllerTests: XCTestCase {
    func testStateIsReadFromSDKRatherThanDerivedFromConsentStatus() {
        let client = ConsentClientStub()
        let controller = GoogleMobileAdsConsentController(client: client)
        XCTAssertFalse(controller.state.canRequestAds)
        client.state = .init(status: .required, canRequestAds: true, privacyOptionsRequirement: .required)
        XCTAssertEqual(controller.state, client.state)
        client.state = .init(status: .obtained, canRequestAds: false, privacyOptionsRequirement: .notRequired)
        XCTAssertFalse(controller.state.canRequestAds)
    }

    func testUpdateForwardsConfigurationWithoutAutomaticallyPresentingAForm() async throws {
        let client = ConsentClientStub()
        let controller = GoogleMobileAdsConsentController(client: client)
        let request = GoogleMobileAdsConsentRequest(
            isTaggedForUnderAgeOfConsent: true,
            debugSettings: .init(geography: .eea, testDeviceIdentifiers: ["test-device"])
        )
        client.nextState = .init(status: .required, canRequestAds: false, privacyOptionsRequirement: .required)

        let state = try await controller.requestConsentInfoUpdate(request)

        XCTAssertEqual(client.receivedRequest, request)
        XCTAssertEqual(client.calls, ["update"])
        XCTAssertEqual(state, client.nextState)
        XCTAssertFalse(controller.isPerformingOperation)
    }

    func testFormsForwardTheScenePresenterAndReturnUpdatedState() async throws {
        let client = ConsentClientStub()
        let controller = GoogleMobileAdsConsentController(client: client)
        let presenter = UIViewController()
        client.nextState = .init(status: .obtained, canRequestAds: true, privacyOptionsRequirement: .required)

        let requiredFormState = try await controller.loadAndPresentIfRequired(from: presenter)

        XCTAssertTrue(client.presenter === presenter)
        XCTAssertTrue(requiredFormState.canRequestAds)
        client.nextState = .init(status: .required, canRequestAds: false, privacyOptionsRequirement: .required)
        let privacyState = try await controller.presentPrivacyOptions()
        XCTAssertNil(client.presenter)
        XCTAssertFalse(privacyState.canRequestAds)
        XCTAssertEqual(client.calls, ["requiredForm", "privacyOptions"])
    }

    func testFailurePreservesSDKErrorAndPreviousEligibilityAndAllowsRetry() async throws {
        let client = ConsentClientStub()
        let controller = GoogleMobileAdsConsentController(client: client)
        let sdkError = NSError(domain: "TestUMP", code: 19, userInfo: [NSLocalizedDescriptionKey: "Offline"])
        client.error = sdkError
        client.nextState = .init(status: .obtained, canRequestAds: true, privacyOptionsRequirement: .required)
        do {
            try await controller.requestConsentInfoUpdate()
            XCTFail("Expected SDK error")
        } catch {
            XCTAssertEqual(error as NSError, sdkError)
        }
        XCTAssertTrue(controller.state.canRequestAds)
        XCTAssertFalse(controller.isPerformingOperation)
        client.error = nil
        try await controller.requestConsentInfoUpdate()
        XCTAssertEqual(client.calls, ["update", "update"])
    }

    func testFormFailureLeavesFreshSDKStateAvailable() async {
        let client = ConsentClientStub()
        let controller = GoogleMobileAdsConsentController(client: client)
        client.state = .init(status: .obtained, canRequestAds: true, privacyOptionsRequirement: .required)
        client.nextState = .init(status: .required, canRequestAds: false, privacyOptionsRequirement: .required)
        client.error = NSError(domain: "TestUMP", code: 3)
        do {
            try await controller.presentPrivacyOptions()
            XCTFail("Expected form error")
        } catch {
            XCTAssertEqual((error as NSError).code, 3)
        }
        XCTAssertFalse(controller.state.canRequestAds)
        XCTAssertFalse(controller.isPerformingOperation)
    }

    func testConcurrentOperationsAreRejectedUntilSDKCompletes() async throws {
        let client = ConsentClientStub()
        let controller = GoogleMobileAdsConsentController(client: client)
        client.suspends = true
        let operation = Task {
            try await controller.loadAndPresentIfRequired()
        }
        await client.waitUntilSuspended()
        XCTAssertTrue(controller.isPerformingOperation)
        do {
            try await controller.requestConsentInfoUpdate()
            XCTFail("Expected busy error")
        } catch {
            XCTAssertEqual(error as? GoogleMobileAdsConsentController.OperationError, .operationInProgress)
        }
        do {
            try await controller.presentPrivacyOptions()
            XCTFail("Expected busy error")
        } catch {
            XCTAssertEqual(error as? GoogleMobileAdsConsentController.OperationError, .operationInProgress)
        }
        XCTAssertEqual(client.calls, ["requiredForm"])
        client.finish()
        _ = try await operation.value
        XCTAssertFalse(controller.isPerformingOperation)
    }

    func testCancelledTaskDoesNotStartSDKWork() async {
        let client = ConsentClientStub()
        let controller = GoogleMobileAdsConsentController(client: client)
        let operation = Task { @MainActor in
            withUnsafeCurrentTask { task in
                task?.cancel()
            }
            return try await controller.requestConsentInfoUpdate()
        }
        do {
            _ = try await operation.value
            XCTFail("Expected cancellation")
        } catch {
            XCTAssertTrue(error is CancellationError)
        }
        XCTAssertTrue(client.calls.isEmpty)
        XCTAssertFalse(controller.isPerformingOperation)
    }

    func testCancellationKeepsGateUntilSDKFinishesAndDoesNotCacheEligibility() async {
        let client = ConsentClientStub()
        let controller = GoogleMobileAdsConsentController(client: client)
        client.suspends = true
        client.nextState = .init(status: .obtained, canRequestAds: true, privacyOptionsRequirement: .required)
        let operation = Task {
            try await controller.requestConsentInfoUpdate()
        }
        await client.waitUntilSuspended()
        operation.cancel()
        XCTAssertTrue(controller.isPerformingOperation)
        do {
            try await controller.presentPrivacyOptions()
            XCTFail("Cancelled SDK work must retain its gate")
        } catch {
            XCTAssertEqual(error as? GoogleMobileAdsConsentController.OperationError, .operationInProgress)
        }
        client.finish()
        do {
            _ = try await operation.value
            XCTFail("Expected cancellation after SDK completion")
        } catch {
            XCTAssertTrue(error is CancellationError)
        }
        XCTAssertFalse(controller.isPerformingOperation)
        XCTAssertTrue(controller.state.canRequestAds)
    }
}
