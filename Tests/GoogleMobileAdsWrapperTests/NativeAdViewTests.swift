import GoogleMobileAds
import UIKit
import XCTest
@testable import GoogleMobileAdsWrapper

@MainActor
final class NativeAdViewTests: XCTestCase {
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
            ad.stubIcon = .init(image: UIGraphicsImageRenderer(size: .init(width: 48, height: 48)).image { context in
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
        return (view, loader)
    }
}

@MainActor
final class StubAdLoader: GoogleMobileAds.AdLoader {
    private(set) var loadCount = 0

    override func load(_ request: GoogleMobileAds.Request?) {
        loadCount += 1
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
