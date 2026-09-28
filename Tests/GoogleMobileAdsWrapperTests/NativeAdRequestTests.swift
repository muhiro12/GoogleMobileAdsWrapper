import GoogleMobileAds
import Testing
import UIKit

@testable import GoogleMobileAdsWrapper

@MainActor
struct NativeAdRequestTests {
    @Test
    func retryReplacesAFailedRequestAndIgnoresOldResults() throws {
        let fixture = RequestFixture()
        let request = fixture.request
        request.loadIfNeeded(from: fixture.controller)
        let first = try #require(fixture.loaders.first)
        request.adLoader(first, didFailToReceiveAdWithError: NSError(domain: "Test", code: 1))
        #expect(request.state == .failed)
        request.update(adUnitID: "unit", reloadID: 0)
        request.loadIfNeeded(from: fixture.controller)
        #expect(fixture.loaders.count == 1)

        request.update(adUnitID: "unit", reloadID: 1)
        request.loadIfNeeded(from: fixture.controller)
        #expect(request.state == .loading)
        #expect(fixture.loaders.count == 2)
        #expect(first.delegate == nil)
        request.adLoader(first, didReceive: StubNativeAd.fixture())
        request.adLoader(first, didFailToReceiveAdWithError: NSError(domain: "Old", code: 2))
        #expect(request.state == .loading)
        let second = try #require(fixture.loaders.last)
        request.adLoader(second, didReceive: StubNativeAd.fixture())
        #expect(request.state == .loaded)
        request.update(adUnitID: "unit", reloadID: 1)
        request.loadIfNeeded(from: fixture.controller)
        #expect(fixture.loaders.count == 2)
    }

    @Test
    func reloadWhileLoadingAndStoppedRequestsRejectStaleCallbacks() throws {
        let fixture = RequestFixture()
        let request = fixture.request
        request.loadIfNeeded(from: fixture.controller)
        let first = try #require(fixture.loaders.first)
        request.update(adUnitID: "unit", reloadID: 1)
        request.loadIfNeeded(from: fixture.controller)
        request.adLoader(first, didReceive: StubNativeAd.fixture())
        #expect(request.nativeAd == nil)
        let second = try #require(fixture.loaders.last)
        request.stop()
        request.adLoader(second, didReceive: StubNativeAd.fixture())
        request.update(adUnitID: "unit", reloadID: 2)
        request.loadIfNeeded(from: fixture.controller)
        #expect(request.nativeAd == nil)
        #expect(fixture.loaders.count == 2)
    }

    @Test
    func onlyExpiredRetainedAdsAreReloadedOnAttachment() throws {
        let fixture = RequestFixture()
        let request = fixture.request
        request.loadIfNeeded(from: fixture.controller)
        request.adLoader(try #require(fixture.loaders.first), didReceive: StubNativeAd.fixture())
        fixture.time = 3599
        request.prepareForAttachment()
        request.loadIfNeeded(from: fixture.controller)
        #expect(request.state == .loaded)
        #expect(fixture.loaders.count == 1)
        fixture.time = 3600
        // No timer interrupts a continuously displayed ad.
        #expect(request.state == .loaded)
        request.prepareForAttachment()
        #expect(request.nativeAd == nil)
        #expect(request.state == .loading)
        request.loadIfNeeded(from: fixture.controller)
        #expect(fixture.loaders.count == 2)
    }
}

@MainActor
private final class RequestFixture {
    let controller = UIViewController()
    var time: TimeInterval = 0
    var loaders: [StubAdLoader] = []
    lazy var request = NativeAdRequest(adUnitID: "unit", reloadID: 0, makeAdLoader: { [unowned self] unit, controller in
        let loader = StubAdLoader(adUnitID: unit, rootViewController: controller, adTypes: [.native], options: nil)
        loaders.append(loader)
        return loader
    }, now: { [unowned self] in
        time
    })
}
