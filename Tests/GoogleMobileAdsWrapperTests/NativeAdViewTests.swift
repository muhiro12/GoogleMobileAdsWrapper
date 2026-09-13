import GoogleMobileAds
import UIKit
import XCTest

@testable import GoogleMobileAdsWrapper

@MainActor
final class NativeAdViewTests: XCTestCase {
    private var windows: [UIWindow] = []

    func testContentFollowsContainerResizing() throws {
        for size in [NativeAdSize.small, .medium] {
            let (container, _) = makeView(size: size)
            let content = try XCTUnwrap(container.subviews.first as? GoogleMobileAds.NativeAdView)
            for width in [CGFloat(280), 320] {
                container.frame = .init(x: 0, y: 0, width: width, height: size.height)
                container.layoutIfNeeded()
                XCTAssertEqual(content.frame, container.bounds)
            }
        }
    }

    func testMediaFitsItsRegionForDifferentCreativeAspectRatios() throws {
        let (container, loader) = makeView(size: .medium)
        let content = try XCTUnwrap(container.subviews.first as? GoogleMobileAds.NativeAdView)
        let mediaView = try XCTUnwrap(content.mediaView)
        container.frame = .init(x: 0, y: 0, width: 320, height: 288)
        var previousConstraintCount: Int?
        for ratio in [CGFloat(16) / 9, 1, CGFloat(9) / 16, 0] {
            let ad = StubNativeAd()
            ad.stubMediaContent.ratio = ratio
            container.adLoader(loader, didReceive: ad)
            container.layoutIfNeeded()
            XCTAssertEqual(mediaView.contentMode, .scaleAspectFit)
            if let previousConstraintCount {
                XCTAssertEqual(mediaView.constraints.count, previousConstraintCount)
            }
            previousConstraintCount = mediaView.constraints.count
            XCTAssertGreaterThanOrEqual(mediaView.bounds.height, 120)
            XCTAssertLessThanOrEqual(mediaView.bounds.height, 160)
            XCTAssertEqual(mediaView.bounds.width, 320)
        }
    }

    func testMissingAssetsAreHiddenAndRestoredOnReplacement() throws {
        let (container, loader) = makeView(size: .medium)
        let content = try XCTUnwrap(container.subviews.first as? GoogleMobileAds.NativeAdView)
        let ad = StubNativeAd()
        container.adLoader(loader, didReceive: ad)
        XCTAssertEqual(content.bodyView?.isHidden, true)
        XCTAssertEqual(content.iconView?.isHidden, true)
        XCTAssertEqual(content.advertiserView?.isHidden, true)
        XCTAssertEqual(content.callToActionView?.isHidden, true)

        ad.stubBody = "Description"
        ad.stubAdvertiser = "Advertiser"
        ad.stubCallToAction = "Install"
        ad.stubIcon = .init(image: .init())
        container.adLoader(loader, didReceive: ad)
        XCTAssertEqual(content.bodyView?.isHidden, false)
        XCTAssertEqual(content.iconView?.isHidden, false)
        XCTAssertEqual(content.advertiserView?.isHidden, false)
        XCTAssertEqual(content.callToActionView?.isHidden, false)
        XCTAssertEqual((content.bodyView as? UILabel)?.text, "Description")
    }

    func testCallToActionUsesAdTitleAndLetsSDKHandleTouches() throws {
        for size in [NativeAdSize.small, .medium] {
            let (container, loader) = makeView(size: size)
            let content = try XCTUnwrap(container.subviews.first as? GoogleMobileAds.NativeAdView)
            let ad = StubNativeAd()
            ad.stubCallToAction = "Learn more"
            ad.stubBody = "A longer description verifies that the ad copy stays inside its card."
            ad.stubAdvertiser = "Example advertiser"
            ad.stubIcon = .init(
                image: UIGraphicsImageRenderer(size: .init(width: 48, height: 48)).image { context in
                    UIColor.systemBlue.setFill()
                    context.fill(.init(x: 0, y: 0, width: 48, height: 48))
                })
            container.adLoader(loader, didReceive: ad)
            let button = try XCTUnwrap(content.callToActionView as? UIButton)
            XCTAssertEqual(button.configuration?.title, "Learn more")
            XCTAssertFalse(button.isUserInteractionEnabled)
            XCTAssertTrue(content.nativeAd === ad)
            XCTAssertFalse(content.isHidden)
            container.frame = .init(x: 0, y: 0, width: 320, height: size.height)
            container.backgroundColor = .white
            container.layoutIfNeeded()
            let image = UIGraphicsImageRenderer(bounds: container.bounds).image { context in
                container.layer.render(in: context.cgContext)
            }
            let attachment = XCTAttachment(image: image)
            attachment.name = "Native ad \(size.rawValue) with fixture assets"
            attachment.lifetime = .keepAlways
            add(attachment)
        }
    }

    func testLoadingWaitsForAnOwningWindowAndUsesItsController() {
        var suppliedController: UIViewController?
        let loader = makeLoader()
        let container = GoogleMobileAdsWrapper.NativeAdView(
            adUnitID: "test-unit",
            size: .small,
            makeAdLoader: { _, controller in
                suppliedController = controller
                return loader
            }
        )
        container.update(adUnitID: "test-unit", size: .small)
        XCTAssertEqual(loader.loadCount, 0)
        XCTAssertNil(suppliedController)
        let controller = attach(container)
        XCTAssertTrue(suppliedController === controller)
        XCTAssertEqual(loader.loadCount, 1)
        container.update(adUnitID: "test-unit", size: .small)
        XCTAssertEqual(loader.loadCount, 1)
    }

    func testMovingWindowsUpdatesPresentationWithoutReloading() {
        let (container, loader) = makeView(size: .small)
        let ad = StubNativeAd()
        container.adLoader(loader, didReceive: ad)
        XCTAssertTrue(ad.rootViewController === container.window?.rootViewController)
        container.removeFromSuperview()
        XCTAssertNil(ad.rootViewController)
        let controller = attach(container)
        XCTAssertTrue(ad.rootViewController === controller)
        XCTAssertEqual(loader.loadCount, 1)
    }

    func testSizeChangeReusesTheLoadedAdInTheNewLayout() throws {
        let (container, loader) = makeView(size: .small)
        let originalContent = try XCTUnwrap(container.subviews.first as? GoogleMobileAds.NativeAdView)
        let ad = StubNativeAd()
        container.adLoader(loader, didReceive: ad)
        container.update(adUnitID: DemoAdUnitID.nativeAdvanced.rawValue, size: .medium)
        let content = try XCTUnwrap(container.subviews.first as? GoogleMobileAds.NativeAdView)
        XCTAssertFalse(content === originalContent)
        XCTAssertNil(originalContent.nativeAd)
        XCTAssertNotNil(content.mediaView)
        XCTAssertTrue(content.nativeAd === ad)
        XCTAssertEqual(loader.loadCount, 1)
        XCTAssertEqual(container.subviews.count, 1)
    }

    func testAdUnitChangeIgnoresOldSuccessAndFailureCallbacks() throws {
        var loaders: [StubAdLoader] = []
        var requestedAdUnitIDs: [String] = []
        let container = GoogleMobileAdsWrapper.NativeAdView(
            adUnitID: "first-unit",
            size: .small,
            makeAdLoader: { adUnitID, _ in
                requestedAdUnitIDs.append(adUnitID)
                let loader = StubAdLoader(
                    adUnitID: adUnitID, rootViewController: nil, adTypes: [.native], options: nil
                )
                loaders.append(loader)
                return loader
            }
        )
        attach(container)
        let firstLoader = try XCTUnwrap(loaders.first)
        container.update(adUnitID: "second-unit", size: .small)
        XCTAssertEqual(requestedAdUnitIDs, ["first-unit", "second-unit"])
        XCTAssertNil(firstLoader.delegate)
        let secondLoader = try XCTUnwrap(loaders.last)
        let content = try XCTUnwrap(container.subviews.first as? GoogleMobileAds.NativeAdView)
        let newAd = StubNativeAd()
        container.adLoader(secondLoader, didReceive: newAd)
        container.adLoader(firstLoader, didReceive: StubNativeAd())
        container.adLoader(firstLoader, didFailToReceiveAdWithError: NSError(domain: "Test", code: 1))
        XCTAssertTrue(content.nativeAd === newAd)
        XCTAssertFalse(content.isHidden)
    }

    func testDismantleDiscardsPendingCallbacksAndReleasesPresentation() throws {
        let (container, loader) = makeView(size: .small)
        let content = try XCTUnwrap(container.subviews.first as? GoogleMobileAds.NativeAdView)
        let ad = StubNativeAd()
        container.adLoader(loader, didReceive: ad)
        NativeAdViewRepresentable.dismantleUIView(container, coordinator: ())
        XCTAssertNil(loader.delegate)
        XCTAssertNil(ad.rootViewController)
        XCTAssertNil(content.nativeAd)
        XCTAssertTrue(content.isHidden)
        container.adLoader(loader, didReceive: StubNativeAd())
        XCTAssertNil(content.nativeAd)
        XCTAssertTrue(content.isHidden)
    }

    func testFailedRequestDoesNotRetryOnUnchangedSwiftUIUpdates() throws {
        let (container, loader) = makeView(size: .small)
        let content = try XCTUnwrap(container.subviews.first as? GoogleMobileAds.NativeAdView)
        container.adLoader(loader, didFailToReceiveAdWithError: NSError(domain: "Test", code: 1))
        for _ in 0..<3 {
            container.update(adUnitID: DemoAdUnitID.nativeAdvanced.rawValue, size: .small)
        }
        XCTAssertEqual(loader.loadCount, 1)
        XCTAssertNil(content.nativeAd)
        XCTAssertTrue(content.isHidden)
    }

    func testSynchronousLoaderCallbackIsAccepted() throws {
        let loader = makeLoader()
        let ad = StubNativeAd()
        loader.onLoad = { loader in
            (loader.delegate as? GoogleMobileAds.NativeAdLoaderDelegate)?.adLoader(loader, didReceive: ad)
        }
        let container = GoogleMobileAdsWrapper.NativeAdView(
            adUnitID: "test-unit",
            size: .small,
            makeAdLoader: { _, _ in
                loader
            }
        )
        attach(container)
        let content = try XCTUnwrap(container.subviews.first as? GoogleMobileAds.NativeAdView)
        XCTAssertTrue(content.nativeAd === ad)
        XCTAssertFalse(content.isHidden)
    }

    private func makeLoader() -> StubAdLoader {
        .init(adUnitID: "test-unit", rootViewController: nil, adTypes: [.native], options: nil)
    }

    @discardableResult
    private func attach(_ view: UIView) -> UIViewController {
        let controller = UIViewController()
        controller.view.addSubview(view)
        let window = UIWindow(frame: .init(x: 0, y: 0, width: 400, height: 800))
        window.rootViewController = controller
        window.isHidden = false
        windows.append(window)
        return controller
    }

    private func makeView(size: NativeAdSize) -> (GoogleMobileAdsWrapper.NativeAdView, StubAdLoader) {
        let loader = StubAdLoader(
            adUnitID: DemoAdUnitID.nativeAdvanced.rawValue,
            rootViewController: nil,
            adTypes: [.native],
            options: nil
        )
        let view = GoogleMobileAdsWrapper.NativeAdView(
            adUnitID: DemoAdUnitID.nativeAdvanced.rawValue,
            size: size,
            makeAdLoader: { _, _ in
                loader
            }
        )
        attach(view)
        return (view, loader)
    }
}

@MainActor
final class StubAdLoader: GoogleMobileAds.AdLoader {
    private(set) var loadCount = 0
    var onLoad: ((StubAdLoader) -> Void)?

    override func load(_ request: GoogleMobileAds.Request?) {
        loadCount += 1
        onLoad?(self)
    }
}

final class StubMediaContent: GoogleMobileAds.MediaContent {
    var ratio: CGFloat = 0

    override var aspectRatio: CGFloat {
        ratio
    }
}

final class StubNativeAd: GoogleMobileAds.NativeAd {
    var stubBody: String?
    var stubAdvertiser: String?
    var stubCallToAction: String?
    var stubIcon: GoogleMobileAds.NativeAdImage?
    let stubMediaContent = StubMediaContent()

    override var headline: String? {
        "Test headline"
    }

    override var body: String? {
        stubBody
    }

    override var advertiser: String? {
        stubAdvertiser
    }

    override var callToAction: String? {
        stubCallToAction
    }

    override var icon: GoogleMobileAds.NativeAdImage? {
        stubIcon
    }

    override var mediaContent: GoogleMobileAds.MediaContent {
        stubMediaContent
    }
}
