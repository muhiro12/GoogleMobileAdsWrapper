import Testing
import UIKit

@testable import GoogleMobileAdsWrapper

@MainActor
struct GoogleMobileAdsConsentControllerTests {
    @Test
    func `State is read from SDK rather than derived from consent status`() {
        let client = ConsentClientStub()
        let controller = GoogleMobileAdsConsentController(client: client)
        #expect(!controller.state.canRequestAds)
        client.state = .init(status: .required, canRequestAds: true, privacyOptionsRequirement: .required)
        #expect(controller.state == client.state)
        client.state = .init(status: .obtained, canRequestAds: false, privacyOptionsRequirement: .notRequired)
        #expect(!controller.state.canRequestAds)
    }

    @Test
    func `Update forwards configuration without automatically presenting a form`() async throws {
        let client = ConsentClientStub()
        let controller = GoogleMobileAdsConsentController(client: client)
        let request = GoogleMobileAdsConsentRequest(
            isTaggedForUnderAgeOfConsent: true,
            debugSettings: .init(geography: .eea, testDeviceIdentifiers: ["test-device"])
        )
        client.nextState = .init(status: .required, canRequestAds: false, privacyOptionsRequirement: .required)

        let state = try await controller.requestConsentInfoUpdate(request)

        #expect(client.receivedRequest == request)
        #expect(client.calls == ["update"])
        #expect(state == client.nextState)
        #expect(!controller.isPerformingOperation)
    }

    @Test
    func `Forms forward the scene presenter and return updated state`() async throws {
        let client = ConsentClientStub()
        let controller = GoogleMobileAdsConsentController(client: client)
        let presenter = UIViewController()
        client.nextState = .init(status: .obtained, canRequestAds: true, privacyOptionsRequirement: .required)

        let requiredFormState = try await controller.loadAndPresentIfRequired(from: presenter)

        #expect(client.presenter === presenter)
        #expect(requiredFormState.canRequestAds)
        client.nextState = .init(status: .required, canRequestAds: false, privacyOptionsRequirement: .required)
        let privacyState = try await controller.presentPrivacyOptions()
        #expect(client.presenter == nil)
        #expect(!privacyState.canRequestAds)
        #expect(client.calls == ["requiredForm", "privacyOptions"])
    }

    @Test
    func `Failure preserves SDK error and previous eligibility and allows retry`() async throws {
        let client = ConsentClientStub()
        let controller = GoogleMobileAdsConsentController(client: client)
        let sdkError = NSError(domain: "TestUMP", code: 19, userInfo: [NSLocalizedDescriptionKey: "Offline"])
        client.error = sdkError
        client.nextState = .init(status: .obtained, canRequestAds: true, privacyOptionsRequirement: .required)
        await #expect(throws: sdkError) {
            try await controller.requestConsentInfoUpdate()
        }
        #expect(controller.state.canRequestAds)
        #expect(!controller.isPerformingOperation)
        client.error = nil
        try await controller.requestConsentInfoUpdate()
        #expect(client.calls == ["update", "update"])
    }

    @Test
    func `Form failure leaves fresh SDK state available`() async {
        let client = ConsentClientStub()
        let controller = GoogleMobileAdsConsentController(client: client)
        client.state = .init(status: .obtained, canRequestAds: true, privacyOptionsRequirement: .required)
        client.nextState = .init(status: .required, canRequestAds: false, privacyOptionsRequirement: .required)
        let sdkError = NSError(domain: "TestUMP", code: 3)
        client.error = sdkError
        await #expect(throws: sdkError) {
            try await controller.presentPrivacyOptions()
        }
        #expect(!controller.state.canRequestAds)
        #expect(!controller.isPerformingOperation)
    }

    @Test
    func `Concurrent operations are rejected until SDK completes`() async throws {
        let client = ConsentClientStub()
        let controller = GoogleMobileAdsConsentController(client: client)
        client.suspends = true
        let operation = Task {
            try await controller.loadAndPresentIfRequired()
        }
        await client.waitUntilSuspended()
        #expect(controller.isPerformingOperation)
        await #expect(throws: GoogleMobileAdsConsentController.OperationError.operationInProgress) {
            try await controller.requestConsentInfoUpdate()
        }
        await #expect(throws: GoogleMobileAdsConsentController.OperationError.operationInProgress) {
            try await controller.presentPrivacyOptions()
        }
        #expect(client.calls == ["requiredForm"])
        client.finish()
        _ = try await operation.value
        #expect(!controller.isPerformingOperation)
    }

    @Test
    func `Cancelled task does not start SDK work`() async {
        let client = ConsentClientStub()
        let controller = GoogleMobileAdsConsentController(client: client)
        let operation = Task { @MainActor in
            withUnsafeCurrentTask { task in
                task?.cancel()
            }
            return try await controller.requestConsentInfoUpdate()
        }
        await #expect(throws: CancellationError.self) {
            _ = try await operation.value
        }
        #expect(client.calls.isEmpty)
        #expect(!controller.isPerformingOperation)
    }

    @Test
    func `Cancellation keeps gate until SDK finishes and does not cache eligibility`() async {
        let client = ConsentClientStub()
        let controller = GoogleMobileAdsConsentController(client: client)
        client.suspends = true
        client.nextState = .init(status: .obtained, canRequestAds: true, privacyOptionsRequirement: .required)
        let operation = Task {
            try await controller.requestConsentInfoUpdate()
        }
        await client.waitUntilSuspended()
        operation.cancel()
        #expect(controller.isPerformingOperation)
        await #expect(throws: GoogleMobileAdsConsentController.OperationError.operationInProgress) {
            try await controller.presentPrivacyOptions()
        }
        client.finish()
        await #expect(throws: CancellationError.self) {
            _ = try await operation.value
        }
        #expect(!controller.isPerformingOperation)
        #expect(controller.state.canRequestAds)
    }
}
