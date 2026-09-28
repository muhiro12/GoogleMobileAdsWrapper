import GoogleMobileAds
import SwiftUI
import Testing
import UIKit

@testable import GoogleMobileAdsWrapper

@MainActor
final class NativeAdHostingTests {
    private var windows: [UIWindow] = []

    @Test
    func delayedLoadResizesTheHostedViewFromZeroToVisible() async throws {
        let loader = makeLoader()
        let recorder = StateRecorder()
        let hosting = host(
            SponsoredSlot(recorder: recorder) { state in
                NativeAdView(adUnitID: "test-unit", layout: .compact, makeAdLoader: { _, _ in
                    loader
                }, onLoadStateChange: state)
            }
        )
        try await settle(hosting)
        let container = try #require(findContainer(in: hosting.view))
        #expect(container.bounds.height == 0)
        #expect(recorder.states == [.loading])
        #expect(recorder.renderedState == .loading)
        #expect(loader.loadCount == 1)

        container.adLoader(loader, didReceive: StubNativeAd.fixture())
        try await settle(hosting)
        #expect(container.bounds.height > 40)
        #expect(container.bounds.width == 320)
        #expect(!container.contentView.isHidden)
        #expect(recorder.states == [.loading, .loaded])
        #expect(recorder.renderedState == .loaded)
    }

    @Test
    func tintModifierReachesTheCallToAction() async throws {
        let loader = makeLoader()
        let hosting = host(
            NativeAdView(adUnitID: "test-unit", layout: .media, makeAdLoader: { _, _ in
                loader
            }, onLoadStateChange: { _ in
            })
            .tint(.orange)
        )
        try await settle(hosting)
        let container = try #require(findContainer(in: hosting.view))
        container.adLoader(loader, didReceive: StubNativeAd.fixture())
        try await settle(hosting)
        let button = try #require(container.contentView.callToActionView)
        let traits = UITraitCollection(userInterfaceStyle: .light)
        #expect(components(of: button.tintColor.resolvedColor(with: traits))
            == components(of: UIColor.systemOrange.resolvedColor(with: traits)))
        #expect(components(of: button.tintColor.resolvedColor(with: traits))
            != components(of: UIColor.systemBlue.resolvedColor(with: traits)))
    }

    @Test
    func adUnitChangeReloadsAndIgnoresTheReplacedRequest() async throws {
        var loaders: [StubAdLoader] = []
        let recorder = StateRecorder()
        let model = SlotModel()
        let hosting = host(
            AdUnitSwitcher(model: model, recorder: recorder) { adUnitID, state in
                NativeAdView(adUnitID: adUnitID, layout: .compact, makeAdLoader: { adUnitID, _ in
                    let loader = StubAdLoader(adUnitID: adUnitID, rootViewController: nil, adTypes: [.native], options: nil)
                    loaders.append(loader)
                    return loader
                }, onLoadStateChange: state)
            }
        )
        try await settle(hosting)
        let container = try #require(findContainer(in: hosting.view))
        let first = try #require(loaders.first)
        container.adLoader(first, didReceive: StubNativeAd.fixture())
        try await settle(hosting)
        #expect(recorder.renderedState == .loaded)

        model.adUnitID = "second-unit"
        try await settle(hosting)
        #expect(loaders.count == 2)
        #expect(recorder.renderedState == .loading)
        #expect(container.bounds.height == 0)
        container.adLoader(first, didReceive: StubNativeAd.fixture())
        container.adLoader(first, didFailToReceiveAdWithError: NSError(domain: "Test", code: 1))
        try await settle(hosting)
        #expect(recorder.renderedState == .loading)
        #expect(container.contentView.nativeAd == nil)

        container.adLoader(try #require(loaders.last), didReceive: StubNativeAd.fixture())
        try await settle(hosting)
        #expect(recorder.renderedState == .loaded)
        #expect(container.bounds.height > 0)
        #expect(recorder.states == [.loading, .loaded, .loading, .loaded])
    }

    @Test(arguments: [
        (UIContentSizeCategory.large, CGFloat(96)),
        (.accessibilityExtraExtraExtraLarge, 96),
        (.large, 128),
        (.accessibilityExtraExtraExtraLarge, 128)
    ])
    func fixedSwiftUIFramesKeepTheCompactAdVisible(category: UIContentSizeCategory, height: CGFloat) async throws {
        let loader = makeLoader()
        let hosting = present(
            NativeAdView(adUnitID: "test-unit", layout: .compact, makeAdLoader: { _, _ in
                loader
            }, onLoadStateChange: { _ in
            })
            .frame(width: 320, height: height),
            category: category
        )
        try await settle(hosting)
        let container = try #require(findContainer(in: hosting.view))
        container.adLoader(loader, didReceive: StubNativeAd.fixture())
        try await settle(hosting)
        let content = container.contentView
        #expect(!content.isHidden)
        #expect(container.bounds.width == 320)
        #expect(container.bounds.height > 0)
        #expect(container.bounds.height <= height)
        #expect(content.frame.height <= container.bounds.height + 0.5)
        #expect(content.callToActionView?.isHidden == false)
        #expect(!content.hasAmbiguousLayout)
    }

    @Test
    func naturalHeightFollowsTheSwiftUIWidthConstraint() async throws {
        let loader = makeLoader()
        let hosting = present(
            ScrollView {
                VStack(spacing: 16) {
                    NativeAdView(adUnitID: "test-unit", layout: .compact, makeAdLoader: { _, _ in
                        loader
                    }, onLoadStateChange: { _ in
                    })
                    .frame(maxWidth: 200)
                    Text("Content below the ad")
                }
            }
        )
        try await settle(hosting)
        let container = try #require(findContainer(in: hosting.view))
        container.adLoader(loader, didReceive: StubNativeAd.fixture())
        try await settle(hosting)
        let content = container.contentView
        #expect(container.bounds.width == 200)
        // The height is the assets' measured height, not a fixed or snapped value.
        #expect(container.bounds.height == container.fittingSize(width: 200, height: nil).height)
        let headline = try #require(content.headlineView)
        let button = try #require(content.callToActionView)
        // The narrow width moves the call to action below the headline.
        #expect(button.frame(in: content).minY >= headline.frame(in: content).maxY)
        #expect(!content.isHidden)
    }

    @Test
    func portraitMediaStaysBoundedInsideAMaximumHeightFrame() async throws {
        let loader = makeLoader()
        let hosting = present(
            NativeAdView(adUnitID: "test-unit", layout: .media, makeAdLoader: { _, _ in
                loader
            }, onLoadStateChange: { _ in
            })
            .frame(width: 320)
            .frame(maxHeight: 400)
        )
        try await settle(hosting)
        let container = try #require(findContainer(in: hosting.view))
        let ad = StubNativeAd.fixture()
        ad.stubMediaContent.ratio = 9 / 16
        container.adLoader(loader, didReceive: ad)
        try await settle(hosting)
        let media = try #require(container.contentView.mediaView)
        #expect(!container.contentView.isHidden)
        #expect(container.bounds.height <= 400)
        #expect(media.bounds.width == 320)
        #expect(media.bounds.height <= NativeAdMetrics.mediaHeightLimitBaseline)
        #expect(media.bounds.height >= NativeAdContentView.minimumMediaHeight)
        #expect(media.contentMode == .scaleAspectFit)
    }

    private func components(of color: UIColor) -> [Int] {
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 0
        color.getRed(&red, green: &green, blue: &blue, alpha: &alpha)
        return [red, green, blue, alpha].map { component in
            Int((component * 255).rounded())
        }
    }

    private func settle(_ hosting: UIViewController) async throws {
        for _ in 0..<4 {
            try await Task.sleep(for: .milliseconds(20))
            hosting.view.setNeedsLayout()
            hosting.view.layoutIfNeeded()
        }
    }

    private func host(_ view: some View) -> UIViewController {
        present(view.frame(width: 320).fixedSize(horizontal: false, vertical: true))
    }

    private func present(_ view: some View, category: UIContentSizeCategory? = nil) -> UIViewController {
        let hosting = UIHostingController(rootView: view)
        if let category {
            hosting.traitOverrides.preferredContentSizeCategory = category
        }
        let window = UIWindow(frame: .init(x: 0, y: 0, width: 400, height: 800))
        window.rootViewController = hosting
        window.isHidden = false
        windows.append(window)
        return hosting
    }

    private func makeLoader() -> StubAdLoader {
        .init(adUnitID: "test-unit", rootViewController: nil, adTypes: [.native], options: nil)
    }

    private func findContainer(in view: UIView) -> NativeAdContainerView? {
        if let container = view as? NativeAdContainerView {
            return container
        }
        for subview in view.subviews {
            if let container = findContainer(in: subview) {
                return container
            }
        }
        return nil
    }
}

@MainActor
private final class StateRecorder {
    var states: [NativeAdLoadState] = []
    var renderedState: NativeAdLoadState?
}

@MainActor
@Observable
private final class SlotModel {
    var adUnitID = "first-unit"
}

/// An app-style slot whose SwiftUI state follows the ad's load state.
private struct SponsoredSlot<Ad: View>: View {
    let recorder: StateRecorder
    let makeAd: (@escaping @MainActor (NativeAdLoadState) -> Void) -> Ad
    @State private var loadState = NativeAdLoadState.loading

    var body: some View {
        let _ = recorder.renderedState = loadState
        VStack {
            makeAd { state in
                recorder.states.append(state)
                loadState = state
            }
            Text(loadState == .loaded ? "Loaded" : "Waiting")
        }
    }
}

private struct AdUnitSwitcher<Ad: View>: View {
    let model: SlotModel
    let recorder: StateRecorder
    let makeAd: (String, @escaping @MainActor (NativeAdLoadState) -> Void) -> Ad
    @State private var loadState = NativeAdLoadState.loading

    var body: some View {
        let _ = recorder.renderedState = loadState
        makeAd(model.adUnitID) { state in
            recorder.states.append(state)
            loadState = state
        }
    }
}
