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
            SponsoredSlot(recorder: recorder) { state, presentation in
                NativeAdView(adUnitID: "test-unit", layout: .compact, makeAdLoader: { _, _ in
                    loader
                }, onLoadStateChange: state, onPresentationStateChange: presentation)
            }
        )
        try await settle(hosting)
        let container = try #require(findContainer(in: hosting.view))
        #expect(container.bounds.height == 0)
        #expect(recorder.states == [.loading])
        #expect(recorder.renderedState == .loading)
        #expect(recorder.presentationStates == [.unavailable])
        #expect(loader.loadCount == 1)

        container.request.adLoader(loader, didReceive: StubNativeAd.fixture())
        try await settle(hosting)
        #expect(container.bounds.height > 40)
        #expect(container.bounds.width == 320)
        #expect(!container.contentView.isHidden)
        #expect(recorder.states == [.loading, .loaded])
        #expect(recorder.renderedState == .loaded)
        // The zero height committed while loading is never reported as a lack of space.
        #expect(recorder.presentationStates == [.unavailable, .ready])
        #expect(recorder.renderedPresentationState == .ready)
    }

    @Test
    func tightFramesReportInsufficientSpaceUntilTheyExpand() async throws {
        let model = SlotModel()
        model.height = 30
        let recorder = StateRecorder()
        let (hosting, loaders) = hostAdaptiveSlot(model: model, recorder: recorder)
        try await settle(hosting)
        let container = try #require(findContainer(in: hosting.view))
        container.request.adLoader(try #require(loaders.first), didReceive: StubNativeAd.fixture())
        try await settle(hosting)
        #expect(recorder.states == [.loading, .loaded])
        #expect(recorder.presentationStates == [.unavailable, .insufficientSpace])
        #expect(recorder.renderedPresentationState == .insufficientSpace)
        #expect(container.bounds.height == 0)
        #expect(container.contentView.isHidden)

        model.height = 128
        try await settle(hosting)
        #expect(recorder.presentationStates == [.unavailable, .insufficientSpace, .ready])
        #expect(recorder.renderedPresentationState == .ready)
        #expect(container.bounds.height > 0)
        #expect(container.bounds.height <= 128)
        #expect(!container.contentView.isHidden)

        model.height = 30
        try await settle(hosting)
        model.height = nil
        try await settle(hosting)
        #expect(recorder.presentationStates == [.unavailable, .insufficientSpace, .ready, .insufficientSpace, .ready])
        #expect(container.bounds.height == container.fittingSize(width: 320, height: nil).height)
        #expect(loaders.count == 1)
    }

    @Test
    func reloadingAndFailureMakeThePresentationUnavailableUntilTheNextAd() async throws {
        let model = SlotModel()
        let recorder = StateRecorder()
        let (hosting, loaders) = hostAdaptiveSlot(model: model, recorder: recorder)
        try await settle(hosting)
        let container = try #require(findContainer(in: hosting.view))
        let first = try #require(loaders.first)
        container.request.adLoader(first, didReceive: StubNativeAd.fixture())
        try await settle(hosting)
        #expect(recorder.presentationStates == [.unavailable, .ready])

        // SwiftUI-style sizing probes never publish their speculative results.
        _ = container.fittingSize(width: 320, height: 10)
        _ = container.fittingSize(width: 100, height: nil)
        try await settle(hosting)
        #expect(recorder.presentationStates == [.unavailable, .ready])
        #expect(!container.contentView.isHidden)

        model.reloadID += 1
        try await settle(hosting)
        #expect(recorder.renderedPresentationState == .unavailable)
        container.request.adLoader(first, didReceive: StubNativeAd.fixture())
        let second = try #require(loaders.last)
        container.request.adLoader(second, didFailToReceiveAdWithError: NSError(domain: "Test", code: 1))
        try await settle(hosting)
        #expect(recorder.renderedState == .failed)
        #expect(recorder.renderedPresentationState == .unavailable)
        #expect(container.bounds.height == 0)

        // The mounted slot retries after a failure when the app changes the reload ID.
        model.reloadID += 1
        try await settle(hosting)
        #expect(loaders.count == 3)
        container.request.adLoader(try #require(loaders.last), didReceive: StubNativeAd.fixture())
        try await settle(hosting)
        #expect(recorder.states == [.loading, .loaded, .loading, .failed, .loading, .loaded])
        #expect(recorder.presentationStates == [.unavailable, .ready, .unavailable, .ready])
        #expect(recorder.renderedPresentationState == .ready)
        #expect(findContainer(in: hosting.view) === container)
    }

    @Test
    func removedSlotsStopReportingStates() async throws {
        let model = SlotModel()
        let recorder = StateRecorder()
        let (hosting, loaders) = hostAdaptiveSlot(model: model, recorder: recorder)
        try await settle(hosting)
        let container = try #require(findContainer(in: hosting.view))
        let loader = try #require(loaders.first)
        model.showsAd = false
        try await settle(hosting)
        #expect(findContainer(in: hosting.view) == nil)
        #expect(loader.delegate == nil)
        container.request.adLoader(loader, didReceive: StubNativeAd.fixture())
        try await settle(hosting)
        #expect(recorder.states == [.loading])
        #expect(recorder.presentationStates == [.unavailable])
        #expect(loaders.count == 1)
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
        container.request.adLoader(loader, didReceive: StubNativeAd.fixture())
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
        container.request.adLoader(first, didReceive: StubNativeAd.fixture())
        try await settle(hosting)
        #expect(recorder.renderedState == .loaded)

        model.adUnitID = "second-unit"
        try await settle(hosting)
        #expect(loaders.count == 2)
        #expect(recorder.renderedState == .loading)
        #expect(container.bounds.height == 0)
        container.request.adLoader(first, didReceive: StubNativeAd.fixture())
        container.request.adLoader(first, didFailToReceiveAdWithError: NSError(domain: "Test", code: 1))
        try await settle(hosting)
        #expect(recorder.renderedState == .loading)
        #expect(container.contentView.nativeAd == nil)

        container.request.adLoader(try #require(loaders.last), didReceive: StubNativeAd.fixture())
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
        container.request.adLoader(loader, didReceive: StubNativeAd.fixture())
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
        container.request.adLoader(loader, didReceive: StubNativeAd.fixture())
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
        container.request.adLoader(loader, didReceive: ad)
        try await settle(hosting)
        let media = try #require(container.contentView.mediaView)
        #expect(!container.contentView.isHidden)
        #expect(container.bounds.height <= 400)
        #expect(media.bounds.width == 320)
        #expect(media.bounds.height <= NativeAdMetrics.mediaHeightLimitBaseline)
        #expect(media.bounds.height >= NativeAdContentView.minimumMediaHeight)
        #expect(media.contentMode == .scaleAspectFit)
    }

    @Test
    func changingReloadIDRetriesWithoutReplacingTheHostedView() async throws {
        let model = SlotModel()
        var loaders: [StubAdLoader] = []
        let hosting = host(
            ReloadableSlot(model: model) { reloadID in
                NativeAdView(adUnitID: "unit", layout: .compact, reloadID: reloadID, makeAdLoader: { unit, _ in
                    let loader = StubAdLoader(adUnitID: unit, rootViewController: nil, adTypes: [.native], options: nil)
                    loaders.append(loader)
                    return loader
                }, onLoadStateChange: { _ in
                })
            }
        )
        try await settle(hosting)
        let container = try #require(findContainer(in: hosting.view))
        let first = try #require(loaders.first)
        container.request.adLoader(first, didFailToReceiveAdWithError: NSError(domain: "Test", code: 1))
        try await settle(hosting)
        #expect(container.loadState == .failed)
        model.reloadID += 1
        try await settle(hosting)
        #expect(findContainer(in: hosting.view) === container)
        #expect(loaders.count == 2)
        #expect(container.loadState == .loading)
        container.request.adLoader(first, didReceive: StubNativeAd.fixture())
        #expect(container.loadState == .loading)
        container.request.adLoader(try #require(loaders.last), didReceive: StubNativeAd.fixture())
        try await settle(hosting)
        #expect(!container.contentView.isHidden)
        #expect(container.bounds.height > 0)
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

    private func hostAdaptiveSlot(model: SlotModel, recorder: StateRecorder) -> (UIViewController, LoaderLog) {
        let loaders = LoaderLog()
        let hosting = present(
            AdaptiveSlot(model: model, recorder: recorder) { reloadID, state, presentation in
                NativeAdView(adUnitID: "unit", layout: .compact, reloadID: reloadID, makeAdLoader: { unit, _ in
                    let loader = StubAdLoader(adUnitID: unit, rootViewController: nil, adTypes: [.native], options: nil)
                    loaders.append(loader)
                    return loader
                }, onLoadStateChange: state, onPresentationStateChange: presentation)
            }
        )
        return (hosting, loaders)
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
    var presentationStates: [NativeAdPresentationState] = []
    var renderedPresentationState: NativeAdPresentationState?
}

@MainActor
private final class LoaderLog {
    private(set) var loaders: [StubAdLoader] = []

    var count: Int {
        loaders.count
    }

    var first: StubAdLoader? {
        loaders.first
    }

    var last: StubAdLoader? {
        loaders.last
    }

    func append(_ loader: StubAdLoader) {
        loaders.append(loader)
    }
}

@MainActor
@Observable
private final class SlotModel {
    var adUnitID = "first-unit"
    var reloadID = 0
    var height: CGFloat?
    var showsAd = true
}

private typealias LoadHandler = @MainActor (NativeAdLoadState) -> Void
private typealias PresentationHandler = @MainActor (NativeAdPresentationState) -> Void

/// An app-style slot whose SwiftUI state follows the ad's load and presentation states.
private struct SponsoredSlot<Ad: View>: View {
    let recorder: StateRecorder
    let makeAd: (@escaping LoadHandler, @escaping PresentationHandler) -> Ad
    @State private var loadState = NativeAdLoadState.loading
    @State private var presentationState = NativeAdPresentationState.unavailable

    var body: some View {
        let _ = recorder.renderedState = loadState
        let _ = recorder.renderedPresentationState = presentationState
        VStack {
            makeAd({ state in
                recorder.states.append(state)
                loadState = state
            }, { state in
                recorder.presentationStates.append(state)
                presentationState = state
            })
            Text(loadState == .loaded ? "Loaded" : "Waiting")
        }
    }
}

/// A slot whose frame, reload ID, and presence the test changes like app state.
private struct AdaptiveSlot<Ad: View>: View {
    let model: SlotModel
    let recorder: StateRecorder
    let makeAd: (Int, @escaping LoadHandler, @escaping PresentationHandler) -> Ad
    @State private var loadState = NativeAdLoadState.loading
    @State private var presentationState = NativeAdPresentationState.unavailable

    var body: some View {
        let _ = recorder.renderedState = loadState
        let _ = recorder.renderedPresentationState = presentationState
        VStack {
            if model.showsAd {
                makeAd(model.reloadID, { state in
                    recorder.states.append(state)
                    loadState = state
                }, { state in
                    recorder.presentationStates.append(state)
                    presentationState = state
                })
                .frame(width: 320, height: model.height)
            }
            // The slot stays mounted during loading so the app can retry it.
            Text(presentationState == .ready ? "Sponsored" : "Placeholder")
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

private struct ReloadableSlot<Ad: View>: View {
    let model: SlotModel
    let makeAd: (Int) -> Ad

    var body: some View {
        makeAd(model.reloadID)
    }
}
