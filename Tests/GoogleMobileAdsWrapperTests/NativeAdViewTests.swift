import GoogleMobileAds
import UIKit
import Testing

@testable import GoogleMobileAdsWrapper

@MainActor
final class NativeAdViewTests {
    private var windows: [UIWindow] = []

    @Test
    func contentFollowsContainerResizing() throws {
        for size in [NativeAdSize.small, .medium] {
            let (container, _) = makeView(size: size)
            let content = try #require(container.subviews.first as? GoogleMobileAds.NativeAdView)
            for width in [CGFloat(280), 320] {
                container.frame = .init(x: 0, y: 0, width: width, height: size.height)
                container.layoutIfNeeded()
                #expect(content.frame == container.bounds)
            }
        }
    }

    @Test
    func mediaFitsItsRegionForDifferentCreativeAspectRatios() throws {
        let (container, loader) = makeView(size: .medium)
        let content = try #require(container.subviews.first as? GoogleMobileAds.NativeAdView)
        let mediaView = try #require(content.mediaView)
        container.frame = .init(x: 0, y: 0, width: 320, height: 288)
        var previousConstraintCount: Int?
        for ratio in [CGFloat(16) / 9, 1, CGFloat(9) / 16, 0] {
            let ad = StubNativeAd()
            ad.stubMediaContent.ratio = ratio
            container.adLoader(loader, didReceive: ad)
            container.frame.size = container.fittingSize(width: 320)
            container.layoutIfNeeded()
            #expect(mediaView.contentMode == .scaleAspectFit)
            if let previousConstraintCount {
                #expect(mediaView.constraints.count == previousConstraintCount)
            }
            previousConstraintCount = mediaView.constraints.count
            #expect(mediaView.bounds.height >= 120)
            let expectedHeight: CGFloat = ratio > 0 ? max(120, 320 / ratio) : 180
            #expect(abs(mediaView.bounds.height - expectedHeight) < 1)
            #expect(mediaView.bounds.width == 320)
        }
    }

    @Test
    func missingAssetsAreHiddenAndRestoredOnReplacement() throws {
        let (container, loader) = makeView(size: .medium)
        let content = try #require(container.subviews.first as? GoogleMobileAds.NativeAdView)
        let ad = StubNativeAd()
        container.adLoader(loader, didReceive: ad)
        #expect(content.bodyView?.isHidden == true)
        #expect(content.iconView?.isHidden == true)
        #expect(content.advertiserView?.isHidden == true)
        #expect(content.callToActionView?.isHidden == true)

        ad.stubBody = "Description"
        ad.stubAdvertiser = "Advertiser"
        ad.stubCallToAction = "Install"
        ad.stubIcon = .init(image: .init())
        container.adLoader(loader, didReceive: ad)
        #expect(content.bodyView?.isHidden == false)
        #expect(content.iconView?.isHidden == false)
        #expect(content.advertiserView?.isHidden == false)
        #expect(content.callToActionView?.isHidden == false)
        #expect((content.bodyView as? UILabel)?.text == "Description")
    }

    @Test
    func callToActionUsesAdTitleAndLetsSDKHandleTouches() throws {
        for size in [NativeAdSize.small, .medium] {
            let (container, loader) = makeView(size: size)
            let content = try #require(container.subviews.first as? GoogleMobileAds.NativeAdView)
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
            let button = try #require(content.callToActionView as? UIButton)
            #expect(button.configuration?.title == "Learn more")
            #expect(!button.isUserInteractionEnabled)
            #expect(content.nativeAd === ad)
            #expect(!content.isHidden)
            container.frame = .init(origin: .zero, size: container.fittingSize(width: 320))
            container.backgroundColor = .white
            container.layoutIfNeeded()
            let image = UIGraphicsImageRenderer(bounds: container.bounds).image { context in
                container.layer.render(in: context.cgContext)
            }
            Attachment.record(image, named: "Native ad \(size.rawValue) with fixture assets.png")
        }
    }

    @Test
    func loadingWaitsForAnOwningWindowAndUsesItsController() {
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
        #expect(loader.loadCount == 0)
        #expect(suppliedController == nil)
        let controller = attach(container)
        #expect(suppliedController === controller)
        #expect(loader.loadCount == 1)
        container.update(adUnitID: "test-unit", size: .small)
        #expect(loader.loadCount == 1)
    }

    @Test
    func movingWindowsUpdatesPresentationWithoutReloading() {
        let (container, loader) = makeView(size: .small)
        let ad = StubNativeAd()
        container.adLoader(loader, didReceive: ad)
        #expect(ad.rootViewController === container.window?.rootViewController)
        container.removeFromSuperview()
        #expect(ad.rootViewController == nil)
        let controller = attach(container)
        #expect(ad.rootViewController === controller)
        #expect(loader.loadCount == 1)
    }

    @Test
    func sizeChangeReusesTheLoadedAdInTheNewLayout() throws {
        let (container, loader) = makeView(size: .small)
        let originalContent = try #require(container.subviews.first as? GoogleMobileAds.NativeAdView)
        let ad = StubNativeAd()
        container.adLoader(loader, didReceive: ad)
        container.update(adUnitID: DemoAdUnitID.nativeAdvanced.rawValue, size: .medium)
        let content = try #require(container.subviews.first as? GoogleMobileAds.NativeAdView)
        #expect(content !== originalContent)
        #expect(originalContent.nativeAd == nil)
        #expect(content.mediaView != nil)
        #expect(content.nativeAd === ad)
        #expect(loader.loadCount == 1)
        #expect(container.subviews.count == 1)
    }

    @Test
    func adUnitChangeIgnoresOldSuccessAndFailureCallbacks() throws {
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
        let firstLoader = try #require(loaders.first)
        container.update(adUnitID: "second-unit", size: .small)
        #expect(requestedAdUnitIDs == ["first-unit", "second-unit"])
        #expect(firstLoader.delegate == nil)
        let secondLoader = try #require(loaders.last)
        let content = try #require(container.subviews.first as? GoogleMobileAds.NativeAdView)
        let newAd = StubNativeAd()
        container.adLoader(secondLoader, didReceive: newAd)
        container.adLoader(firstLoader, didReceive: StubNativeAd())
        container.adLoader(firstLoader, didFailToReceiveAdWithError: NSError(domain: "Test", code: 1))
        #expect(content.nativeAd === newAd)
        #expect(!content.isHidden)
    }

    @Test
    func dismantleDiscardsPendingCallbacksAndReleasesPresentation() throws {
        let (container, loader) = makeView(size: .small)
        let content = try #require(container.subviews.first as? GoogleMobileAds.NativeAdView)
        let ad = StubNativeAd()
        container.adLoader(loader, didReceive: ad)
        NativeAdViewRepresentable.dismantleUIView(container, coordinator: ())
        #expect(loader.delegate == nil)
        #expect(ad.rootViewController == nil)
        #expect(content.nativeAd == nil)
        #expect(content.isHidden)
        container.adLoader(loader, didReceive: StubNativeAd())
        #expect(content.nativeAd == nil)
        #expect(content.isHidden)
    }

    @Test
    func dismantledViewCannotRestartLoadingWhenReattached() throws {
        let (container, loader) = makeView(size: .small)
        NativeAdViewRepresentable.dismantleUIView(container, coordinator: ())
        container.removeFromSuperview()
        attach(container)
        container.update(adUnitID: "replacement-unit", size: .medium)

        #expect(loader.loadCount == 1)
        #expect(loader.delegate == nil)
        let content = try #require(container.subviews.first as? GoogleMobileAds.NativeAdView)
        #expect(content.nativeAd == nil)
        #expect(content.isHidden)
    }

    @Test
    func failedRequestDoesNotRetryOnUnchangedSwiftUIUpdates() throws {
        let (container, loader) = makeView(size: .small)
        let content = try #require(container.subviews.first as? GoogleMobileAds.NativeAdView)
        container.adLoader(loader, didFailToReceiveAdWithError: NSError(domain: "Test", code: 1))
        for _ in 0..<3 {
            container.update(adUnitID: DemoAdUnitID.nativeAdvanced.rawValue, size: .small)
        }
        #expect(loader.loadCount == 1)
        #expect(content.nativeAd == nil)
        #expect(content.isHidden)
    }

    @Test
    func synchronousLoaderCallbackIsAccepted() throws {
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
        let content = try #require(container.subviews.first as? GoogleMobileAds.NativeAdView)
        #expect(content.nativeAd === ad)
        #expect(!content.isHidden)
    }

    @Test(arguments: NativeAdSize.allCases)
    func attributionLeavesSpaceForAdChoices(size: NativeAdSize) throws {
        let (container, loader) = makeView(size: size)
        let ad = StubNativeAd()
        ad.stubCallToAction = "View details"
        container.adLoader(loader, didReceive: ad)
        container.frame.size = container.fittingSize(width: 280)
        container.layoutIfNeeded()
        let content = try #require(container.subviews.first as? GoogleMobileAds.NativeAdView)
        let label = try #require(content.subviews.first {
            $0.accessibilityIdentifier == "nativeAd.attribution"
        } as? UILabel)
        #expect(label.text == String(localized: "nativeAd.attribution", bundle: .module))
        #expect(label.bounds.width >= 15)
        #expect(label.bounds.height >= 15)
        #expect(label.frame.maxX <= content.bounds.width - 64)
        let headline = try #require(content.headlineView)
        #expect(headline.convert(headline.bounds, to: content).minY >= 32)
    }

    @Test
    func compactVideoUsesMediaLayoutAndPreservesTheLoadedAd() throws {
        let (container, loader) = makeView(size: .small)
        let ad = StubNativeAd()
        ad.stubMediaContent.video = true
        ad.stubMediaContent.ratio = 9 / 16
        container.adLoader(loader, didReceive: ad)
        container.frame.size = container.fittingSize(width: 280)
        container.layoutIfNeeded()
        let content = try #require(container.subviews.first as? GoogleMobileAds.NativeAdView)
        let media = try #require(content.mediaView)
        #expect(content.nativeAd === ad)
        #expect(media.bounds.width >= 120)
        #expect(media.bounds.height >= 120)
        #expect(container.bounds.height > NativeAdSize.small.height)
        #expect(loader.loadCount == 1)
        container.update(adUnitID: DemoAdUnitID.nativeAdvanced.rawValue, size: .small)
        #expect(content.nativeAd === ad)
        #expect(loader.loadCount == 1)
    }

    @Test(arguments: NativeAdSize.allCases)
    func largeTextFitsNarrowDarkCards(size: NativeAdSize) throws {
        let (container, loader) = makeView(size: size)
        container.traitOverrides.preferredContentSizeCategory = .accessibilityExtraExtraExtraLarge
        container.traitOverrides.userInterfaceStyle = .dark
        let ad = StubNativeAd()
        ad.stubBody = "A longer description remains readable with large text in a narrow card."
        ad.stubCallToAction = "View more details"
        ad.stubAdvertiser = "Example advertiser"
        container.adLoader(loader, didReceive: ad)
        container.frame.size = container.fittingSize(width: 280)
        container.layoutIfNeeded()
        let content = try #require(container.subviews.first as? GoogleMobileAds.NativeAdView)
        let button = try #require(content.callToActionView)
        #expect(abs(button.bounds.width - 280) < 1)
        for asset in [content.headlineView, content.bodyView, content.callToActionView].compactMap({ $0 }) {
            let frame = asset.convert(asset.bounds, to: content)
            #expect(frame.minY >= 31.5)
            #expect(frame.maxY <= content.bounds.height + 1)
            #expect(frame.minX >= 0)
            #expect(frame.maxX <= content.bounds.width + 1)
        }
        let image = UIGraphicsImageRenderer(bounds: container.bounds).image { context in
            container.layer.render(in: context.cgContext)
        }
        Attachment.record(image, named: "Native ad large text dark \(size.rawValue).png")
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
    var video = false

    override var hasVideoContent: Bool {
        video
    }

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
