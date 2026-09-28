import GoogleMobileAds
import UIKit
import Testing

@testable import GoogleMobileAdsWrapper

@MainActor
final class NativeAdViewTests {
    private var windows: [UIWindow] = []

    @Test(arguments: NativeAdLayout.allCases)
    func layoutsTrackTheProposedWidthWithoutAFixedMaximum(layout: NativeAdLayout) {
        for width in [CGFloat(600), 360, 240, 320] {
            let (container, _) = loadedView(layout: layout, ad: .fixture(), width: width)
            let content = container.contentView
            #expect(container.bounds.width == width)
            #expect(container.fittingSize(width: width, height: nil) == container.bounds.size)
            #expect(!content.isHidden)
            for asset in assets(of: content) {
                #expect(!asset.hasAmbiguousLayout, "\(type(of: asset))")
                let frame = asset.convert(asset.bounds, to: content)
                #expect(frame.minX >= -0.5)
                #expect(frame.maxX <= width + 0.5)
                #expect(frame.maxY <= container.bounds.height + 0.5)
            }
        }
    }

    @Test
    func unspecifiedProposalsUseTheIdealWidth() {
        let (container, _) = loadedView(layout: .compact, ad: .fixture(), width: 320)
        for width in [CGFloat?.none, 0, .infinity, .nan] {
            let fitted = container.fittingSize(width: width, height: .infinity)
            #expect(fitted.width == NativeAdMetrics.idealWidth)
            #expect(fitted.height > 0)
            #expect(fitted.height.isFinite)
        }
    }

    @Test
    func loadStateIsDeliveredAfterTheUpdateAndUnloadedAdsTakeNoHeight() async {
        let (container, loader) = makeView(layout: .compact)
        var states: [NativeAdLoadState] = []
        container.onLoadStateChange = { state in
            states.append(state)
        }
        await settle()
        #expect(states == [.loading])
        #expect(container.fittingSize(width: 320, height: nil).height == 0)
        container.request.adLoader(loader, didReceive: StubNativeAd.fixture())
        // Delivery never happens inside the triggering call.
        #expect(states == [.loading])
        await settle()
        #expect(states == [.loading, .loaded])
        #expect(container.fittingSize(width: 320, height: nil).height > 0)
        container.update(adUnitID: "replacement-unit", layout: .compact)
        await settle()
        container.request.adLoader(loader, didFailToReceiveAdWithError: NSError(domain: "Test", code: 1))
        await settle()
        #expect(states == [.loading, .loaded, .loading, .failed])
        #expect(container.fittingSize(width: 320, height: nil).height == 0)
    }

    @Test
    func dismantledViewsStopDeliveringLoadStates() async {
        let (container, loader) = makeView(layout: .media)
        var states: [NativeAdLoadState] = []
        container.onLoadStateChange = { state in
            states.append(state)
        }
        container.request.adLoader(loader, didFailToReceiveAdWithError: NSError(domain: "Test", code: 1))
        NativeAdViewRepresentable.dismantleUIView(container, coordinator: ())
        await settle()
        #expect(states.isEmpty)
        #expect(container.contentView.isHidden)
    }

    @Test(arguments: [
        (NativeAdLayout.compact, CGSize(width: 320, height: 96)),
        (.compact, CGSize(width: 320, height: 128)),
        (.media, CGSize(width: 320, height: 320))
    ])
    func fixedSlotsStayVisibleAtLargeTextSizes(layout: NativeAdLayout, slot: CGSize) throws {
        for category in [UIContentSizeCategory.large, .accessibilityExtraExtraExtraLarge] {
            let (container, loader) = makeView(layout: layout)
            container.traitOverrides.preferredContentSizeCategory = category
            container.request.adLoader(loader, didReceive: StubNativeAd.fixture())
            container.frame.size = slot
            container.layoutIfNeeded()
            let content = container.contentView
            #expect(!content.isHidden, "\(category.rawValue)")
            #expect(content.frame.height <= slot.height + 0.5)
            let headline = try #require(content.headlineView as? UILabel)
            #expect(headline.font.pointSize >= UIFont.preferredFont(
                forTextStyle: .headline,
                compatibleWith: .init(preferredContentSizeCategory: .large)
            ).pointSize - 0.5)
            for asset in assets(of: content) {
                #expect(!asset.hasAmbiguousLayout, "\(type(of: asset))")
                #expect(asset.frame(in: content).maxY <= content.bounds.height + 0.5)
            }
            let button = try #require(content.callToActionView)
            #expect(!button.isHidden)
            // A larger proposal restores the reader's larger text.
            let unconstrained = container.fittingSize(width: slot.width, height: nil)
            if category.isAccessibilityCategory {
                #expect(headline.font.pointSize > UIFont.preferredFont(
                    forTextStyle: .headline,
                    compatibleWith: .init(preferredContentSizeCategory: .extraExtraExtraLarge)
                ).pointSize)
            }
            #expect(unconstrained.height >= content.frame.height)
            #expect(container.fittingSize(width: slot.width, height: slot.height).height <= slot.height + 0.5)
        }
    }

    @Test
    func tinySlotsLeaveTheAdEmptyAtAnyTextSize() {
        let (container, _) = loadedView(layout: .compact, ad: .fixture(), width: 320)
        container.frame.size = .init(width: 320, height: 30)
        container.layoutIfNeeded()
        #expect(container.contentView.isHidden)
    }

    @Test
    func narrowWidthsMoveTheCompactCallToActionBelowTheHeadline() throws {
        let ad = StubNativeAd.fixture()
        let (wide, _) = loadedView(layout: .compact, ad: ad, width: 360)
        let (narrow, _) = loadedView(layout: .compact, ad: .fixture(), width: 200)
        let wideButton = try #require(wide.contentView.callToActionView)
        let wideHeadline = try #require(wide.contentView.headlineView)
        #expect(wideButton.frame(in: wide).minY < wideHeadline.frame(in: wide).maxY)
        #expect(wideButton.frame(in: wide).minX > wideHeadline.frame(in: wide).maxX)
        let narrowButton = try #require(narrow.contentView.callToActionView)
        let narrowHeadline = try #require(narrow.contentView.headlineView)
        #expect(narrowButton.frame(in: narrow).minY >= narrowHeadline.frame(in: narrow).maxY)
    }

    @Test(arguments: NativeAdLayout.allCases)
    func accessibilityTextKeepsTheChosenLayoutVisibleAndBounded(layout: NativeAdLayout) throws {
        let (regular, _) = loadedView(layout: layout, ad: .fixture(), width: 320)
        let (large, loader) = loadedView(
            layout: layout,
            ad: .fixture(),
            width: 320,
            category: .accessibilityExtraExtraExtraLarge
        )
        let content = large.contentView
        #expect(!content.isHidden)
        #expect((content.mediaView != nil) == (layout == .media))
        #expect(large.bounds.height > regular.bounds.height)
        #expect(large.bounds.height < regular.bounds.height + 280)
        #expect(loader.loadCount == 1)
        let headline = try #require(content.headlineView as? UILabel)
        #expect(headline.numberOfLines == 0)
        #expect(headline.font.pointSize <= UIFont.preferredFont(
            forTextStyle: .headline,
            compatibleWith: .init(preferredContentSizeCategory: .accessibilityMedium)
        ).pointSize)
    }

    @Test
    func textSizeChangesReflowTheExistingAdWithoutReloading() {
        let (container, loader) = loadedView(layout: .compact, ad: .fixture(), width: 280)
        let ad = container.contentView.nativeAd
        for category in [UIContentSizeCategory.accessibilityExtraExtraExtraLarge, .large] {
            container.traitOverrides.preferredContentSizeCategory = category
            container.frame.size = container.fittingSize(width: 280, height: nil)
            container.layoutIfNeeded()
            #expect(container.contentView.nativeAd === ad)
            #expect(container.contentView.mediaView == nil)
            #expect(!container.contentView.isHidden)
            #expect(loader.loadCount == 1)
        }
    }

    @Test
    func limitedHeightOmitsOptionalAssetsBeforeTruncatingTheHeadline() throws {
        let ad = StubNativeAd.fixture()
        ad.stubHeadline = "A long headline that wraps across several lines in a narrow placement"
        ad.stubBody = String(repeating: "Body copy that is optional. ", count: 4)
        let (container, _) = loadedView(layout: .compact, ad: ad, width: 240)
        let content = container.contentView
        let headline = try #require(content.headlineView as? UILabel)
        let natural = container.bounds.height

        var smallest: CGSize?
        for maximumHeight in stride(from: natural - 1, through: 20, by: -1) {
            guard let size = content.fit(width: 240, maximumHeight: maximumHeight) else {
                break
            }
            #expect(size.height <= maximumHeight)
            // Optional assets are omitted before required text is truncated.
            #expect(content.bodyView?.isHidden == true)
            if content.advertiserView?.isHidden == false {
                #expect(headline.numberOfLines == 0)
            }
            smallest = size
        }
        let tight = try #require(smallest)
        #expect(content.fit(width: 240, maximumHeight: tight.height) == tight)
        #expect(content.advertiserView?.isHidden == true)
        #expect(headline.numberOfLines > 0)
        container.frame.size = tight
        container.layoutIfNeeded()
        // The truncated headline keeps at least Google's minimum characters visible.
        let visibleText = String(headline.text!.prefix(NativeAdContentView.minimumHeadlineCharacters)) + "…"
        let needed = (visibleText as NSString).boundingRect(
            with: .init(width: headline.bounds.width, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: [.font: headline.font!],
            context: nil
        ).height
        #expect(headline.bounds.height >= needed - 1)

        let button = try #require(content.callToActionView)
        #expect(!button.isHidden)
        #expect(button.bounds.width >= button.intrinsicContentSize.width - 0.5)
    }

    @Test
    func impossibleConstraintsLeaveTheAdEmpty() {
        let (container, _) = loadedView(layout: .media, ad: .fixture(), width: 320)
        for size in [CGSize(width: 100, height: 400), .init(width: 320, height: 40)] {
            container.frame.size = size
            container.layoutIfNeeded()
            #expect(container.contentView.isHidden)
            #expect(container.loadState == .loaded)
            #expect(container.fittingSize(width: size.width, height: size.height).height == 0)
        }
        container.frame.size = container.fittingSize(width: 320, height: nil)
        container.layoutIfNeeded()
        #expect(!container.contentView.isHidden)
    }

    @Test(arguments: [CGFloat(16) / 9, 1, CGFloat(9) / 16, 0])
    func mediaHeightIsBoundedAndPreservesTheCreative(ratio: CGFloat) throws {
        for width in [CGFloat(320), 600, 180] {
            let ad = StubNativeAd.fixture()
            ad.stubMediaContent.ratio = ratio
            let (container, _) = loadedView(layout: .media, ad: ad, width: width)
            let media = try #require(container.contentView.mediaView)
            #expect(media.contentMode == .scaleAspectFit)
            #expect(media.bounds.width == width)
            #expect(media.bounds.height >= NativeAdContentView.minimumMediaHeight)
            let limit = min(max(NativeAdMetrics.mediaHeightLimitBaseline, width * 9 / 16), NativeAdMetrics.maximumMediaHeight)
            #expect(media.bounds.height <= limit + 0.5)
            if ratio >= 16 / 9 {
                // Wide creatives keep their natural, unsnapped height.
                #expect(abs(media.bounds.height - max(120, width / ratio)) < 1 || media.bounds.height >= limit - 0.5)
            }
        }
    }

    @Test
    func compactPortraitVideoMeetsThePixelMinimumOnTwoScaleDisplays() throws {
        let ad = StubNativeAd.fixture()
        ad.stubMediaContent.video = true
        ad.stubMediaContent.ratio = 9 / 16
        let (container, _) = loadedView(layout: .compact, ad: ad, width: 280)
        container.traitOverrides.displayScale = 2
        container.frame.size = container.fittingSize(width: 280, height: nil)
        container.layoutIfNeeded()
        let media = try #require(container.contentView.mediaView)
        #expect(media.bounds.height == 128)
        #expect(media.bounds.height * 2 >= 256)
        #expect(!container.contentView.isHidden)
    }

    @Test
    func compactVideoRegistersABoundedMediaView() throws {
        let ad = StubNativeAd.fixture()
        ad.stubMediaContent.video = true
        ad.stubMediaContent.ratio = 9 / 16
        let (container, loader) = loadedView(layout: .compact, ad: ad, width: 280)
        let media = try #require(container.contentView.mediaView)
        #expect(container.contentView.nativeAd === ad)
        #expect(media.bounds.width >= 120)
        #expect(media.bounds.height == NativeAdContentView.minimumMediaHeight)
        #expect(container.bounds.height < 400)
        container.update(adUnitID: DemoAdUnitID.nativeAdvanced.rawValue, layout: .compact)
        #expect(container.contentView.nativeAd === ad)
        #expect(loader.loadCount == 1)
    }

    @Test
    func missingAssetsAreHiddenAndRestoredOnReplacement() throws {
        let (container, loader) = makeView(layout: .media)
        let content = container.contentView
        let ad = StubNativeAd()
        container.request.adLoader(loader, didReceive: ad)
        container.layoutIfNeeded()
        #expect(content.bodyView?.isHidden == true)
        #expect(content.iconView?.isHidden == true)
        #expect(content.advertiserView?.isHidden == true)
        #expect(content.callToActionView?.isHidden == true)

        container.request.adLoader(loader, didReceive: StubNativeAd.fixture())
        container.layoutIfNeeded()
        #expect(content.bodyView?.isHidden == false)
        #expect(content.iconView?.isHidden == false)
        #expect(content.advertiserView?.isHidden == false)
        #expect(content.callToActionView?.isHidden == false)
        #expect((content.bodyView as? UILabel)?.text == StubNativeAd.fixture().body)
    }

    @Test(arguments: NativeAdLayout.allCases)
    func callToActionUsesTheAdTitleAndLetsTheSDKHandleTouches(layout: NativeAdLayout) throws {
        let (container, _) = loadedView(layout: layout, ad: .fixture(), width: 320)
        let content = container.contentView
        let button = try #require(content.callToActionView as? UIButton)
        #expect(button.configuration?.title == "Learn more")
        #expect(!button.isUserInteractionEnabled)
        #expect(content.backgroundColor == nil)
        #expect(container.backgroundColor == nil)
    }

    @Test(arguments: NativeAdLayout.allCases)
    func attributionBadgeIsReadableAndClearsAdChoices(layout: NativeAdLayout) throws {
        let (container, _) = loadedView(layout: layout, ad: .fixture(), width: 280)
        let content = container.contentView
        let badge = try #require(findView(in: content) { view in
            view.accessibilityIdentifier == "nativeAd.attribution"
        } as? UILabel)
        #expect(badge.text == "Ad")
        #expect(badge.bounds.width >= 15)
        #expect(badge.bounds.height >= 15)
        let inset = NativeAdMetrics.adChoicesInset
        let adChoicesCorner = CGRect(x: content.bounds.width - inset, y: 0, width: inset, height: 20)
        for asset in assets(of: content) + [badge] {
            #expect(!asset.frame(in: content).intersects(adChoicesCorner))
        }
    }

    @Test
    func fixedDesignDimensionsFollowTheEightPointGrid() throws {
        let dimensions = [
            NativeAdMetrics.spacing, NativeAdMetrics.iconSize, NativeAdMetrics.iconCornerRadius,
            NativeAdMetrics.adChoicesInset, NativeAdMetrics.minimumRowTextWidth, NativeAdMetrics.minimumWidth,
            NativeAdMetrics.idealWidth, NativeAdMetrics.mediaHeightLimitBaseline, NativeAdMetrics.maximumMediaHeight,
            NativeAdMetrics.badgeMinimumWidth, NativeAdMetrics.badgeMinimumHeight,
            NativeAdMetrics.badgeHorizontalPadding, NativeAdMetrics.badgeCornerRadius
        ]
        for dimension in dimensions {
            #expect(dimension > 0)
            #expect(dimension.truncatingRemainder(dividingBy: 8) == 0, "\(dimension)")
        }
        // At the default text size, the laid-out fixed geometry lands on the grid too.
        let (container, _) = loadedView(layout: .compact, ad: .fixture(), width: 320, category: .large)
        let content = container.contentView
        let icon = try #require(content.iconView)
        let headline = try #require(content.headlineView)
        let body = try #require(content.bodyView)
        let badge = try #require(findView(in: content) { view in
            view.accessibilityIdentifier == "nativeAd.attribution"
        })
        #expect(icon.bounds.size == .init(width: 40, height: 40))
        #expect(icon.layer.cornerRadius == 8)
        #expect(badge.layer.cornerRadius == 8)
        #expect(badge.bounds.width == 32)
        #expect(badge.bounds.height == 16)
        #expect(abs(headline.frame(in: content).minX - icon.frame(in: content).maxX - 8) < 0.01)
        #expect(abs(body.frame(in: content).minY - headline.frame(in: content).maxY - 8) < 0.01)
    }

    @Test
    func loadingWaitsForAnOwningWindowAndUsesItsController() {
        var suppliedController: UIViewController?
        let loader = makeLoader()
        let container = NativeAdContainerView(
            adUnitID: "test-unit",
            layout: .compact,
            makeAdLoader: { _, controller in
                suppliedController = controller
                return loader
            }
        )
        container.update(adUnitID: "test-unit", layout: .compact)
        #expect(loader.loadCount == 0)
        #expect(suppliedController == nil)
        let controller = attach(container)
        #expect(suppliedController === controller)
        #expect(loader.loadCount == 1)
        container.update(adUnitID: "test-unit", layout: .compact)
        #expect(loader.loadCount == 1)
    }

    @Test
    func movingWindowsUpdatesPresentationWithoutReloading() {
        let (container, loader) = makeView(layout: .compact)
        let ad = StubNativeAd()
        container.request.adLoader(loader, didReceive: ad)
        #expect(ad.rootViewController === container.window?.rootViewController)
        container.removeFromSuperview()
        #expect(ad.rootViewController == nil)
        let controller = attach(container)
        #expect(ad.rootViewController === controller)
        #expect(loader.loadCount == 1)
    }

    @Test
    func sizeChangeReusesTheLoadedAdInTheNewLayout() throws {
        let (container, loader) = makeView(layout: .compact)
        let originalContent = container.contentView
        let ad = StubNativeAd()
        container.request.adLoader(loader, didReceive: ad)
        container.update(adUnitID: DemoAdUnitID.nativeAdvanced.rawValue, layout: .media)
        let content = container.contentView
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
        let container = NativeAdContainerView(
            adUnitID: "first-unit",
            layout: .compact,
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
        container.update(adUnitID: "second-unit", layout: .compact)
        #expect(requestedAdUnitIDs == ["first-unit", "second-unit"])
        #expect(firstLoader.delegate == nil)
        let secondLoader = try #require(loaders.last)
        let content = container.contentView
        let newAd = StubNativeAd()
        container.request.adLoader(secondLoader, didReceive: newAd)
        container.request.adLoader(firstLoader, didReceive: StubNativeAd())
        container.request.adLoader(firstLoader, didFailToReceiveAdWithError: NSError(domain: "Test", code: 1))
        #expect(content.nativeAd === newAd)
        #expect(!content.isHidden)
    }

    @Test
    func dismantleDiscardsPendingCallbacksAndReleasesPresentation() throws {
        let (container, loader) = makeView(layout: .compact)
        let content = container.contentView
        let ad = StubNativeAd()
        container.request.adLoader(loader, didReceive: ad)
        NativeAdViewRepresentable.dismantleUIView(container, coordinator: ())
        #expect(loader.delegate == nil)
        #expect(ad.rootViewController == nil)
        #expect(content.nativeAd == nil)
        #expect(content.isHidden)
        container.request.adLoader(loader, didReceive: StubNativeAd())
        #expect(content.nativeAd == nil)
        #expect(content.isHidden)
    }

    @Test
    func dismantledViewCannotRestartLoadingWhenReattached() throws {
        let (container, loader) = makeView(layout: .compact)
        NativeAdViewRepresentable.dismantleUIView(container, coordinator: ())
        container.removeFromSuperview()
        attach(container)
        container.update(adUnitID: "replacement-unit", layout: .media)

        #expect(loader.loadCount == 1)
        #expect(loader.delegate == nil)
        let content = container.contentView
        #expect(content.nativeAd == nil)
        #expect(content.isHidden)
    }

    @Test
    func failedRequestDoesNotRetryOnUnchangedSwiftUIUpdates() throws {
        let (container, loader) = makeView(layout: .compact)
        let content = container.contentView
        container.request.adLoader(loader, didFailToReceiveAdWithError: NSError(domain: "Test", code: 1))
        for _ in 0..<3 {
            container.update(adUnitID: DemoAdUnitID.nativeAdvanced.rawValue, layout: .compact)
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
        let container = NativeAdContainerView(
            adUnitID: "test-unit",
            layout: .compact,
            makeAdLoader: { _, _ in
                loader
            }
        )
        attach(container)
        let content = container.contentView
        #expect(content.nativeAd === ad)
        #expect(!content.isHidden)
    }

    @Test
    func recordFixtureCaptures() throws {
        let fixtures: [(name: String, ad: () -> StubNativeAd)] = [
            ("short", {
                StubNativeAd.fixture()
            }),
            ("long", {
                let ad = StubNativeAd.fixture()
                ad.stubHeadline = "An unusually long headline that needs several lines at large sizes"
                ad.stubBody = "A longer body describes the offer in detail so wrapping and optional omission can be reviewed."
                ad.stubAdvertiser = "Example Advertiser With A Long Name"
                ad.stubCallToAction = "Install now"
                return ad
            }),
            ("missing", {
                StubNativeAd()
            })
        ]
        for layout in NativeAdLayout.allCases {
            for category in [UIContentSizeCategory.large, .accessibilityExtraExtraExtraLarge] {
                for width in [CGFloat(361), 240] {
                    for fixture in fixtures {
                        let (container, _) = loadedView(layout: layout, ad: fixture.ad(), width: width, category: category)
                        record(container, named: "\(layout.rawValue) \(category.rawValue) w\(Int(width)) \(fixture.name)")
                    }
                }
            }
        }
        for ratio in [CGFloat(9) / 16, 1] {
            let ad = StubNativeAd.fixture()
            ad.stubMediaContent.ratio = ratio
            let (container, _) = loadedView(layout: .media, ad: ad, width: 361)
            record(container, named: "media portrait ratio \(String(format: "%.2f", ratio)) w361")
        }
        let video = StubNativeAd.fixture()
        video.stubMediaContent.video = true
        video.stubMediaContent.ratio = 9 / 16
        let (compactVideo, _) = loadedView(layout: .compact, ad: video, width: 361)
        record(compactVideo, named: "compact video w361")
        let (dark, _) = loadedView(layout: .media, ad: .fixture(), width: 361)
        dark.traitOverrides.userInterfaceStyle = .dark
        dark.tintColor = .systemOrange
        dark.frame.size = dark.fittingSize(width: 361, height: nil)
        dark.layoutIfNeeded()
        record(dark, named: "media dark orange tint w361")
    }

    /// Draws the ad on an app-style card, as a host app would present it.
    private func record(_ container: NativeAdContainerView, named name: String) {
        let padding: CGFloat = 16
        let size = CGSize(width: container.bounds.width + padding * 2, height: container.bounds.height + padding * 2)
        let traits = container.traitCollection
        let image = UIGraphicsImageRenderer(size: size).image { context in
            UIColor.secondarySystemBackground.resolvedColor(with: traits).setFill()
            context.fill(.init(origin: .zero, size: size))
            context.cgContext.translateBy(x: padding, y: padding)
            container.layer.render(in: context.cgContext)
        }
        Attachment.record(image, named: "\(name).png")
    }

    private func settle() async {
        for _ in 0..<5 {
            await Task.yield()
        }
    }

    private func loadedView(
        layout: NativeAdLayout,
        ad: StubNativeAd,
        width: CGFloat,
        category: UIContentSizeCategory? = nil
    ) -> (NativeAdContainerView, StubAdLoader) {
        let (container, loader) = makeView(layout: layout)
        if let category {
            container.traitOverrides.preferredContentSizeCategory = category
        }
        container.request.adLoader(loader, didReceive: ad)
        container.frame.size = container.fittingSize(width: width, height: nil)
        container.layoutIfNeeded()
        return (container, loader)
    }

    private func assets(of content: NativeAdContentView) -> [UIView] {
        [content.headlineView, content.bodyView, content.advertiserView, content.callToActionView, content.iconView, content.mediaView]
            .compactMap { view in
                view
            }
            .filter { view in
                view.superview != nil && !view.isHidden
            }
    }

    private func findView(in view: UIView, where predicate: (UIView) -> Bool) -> UIView? {
        if predicate(view) {
            return view
        }
        for subview in view.subviews {
            if let match = findView(in: subview, where: predicate) {
                return match
            }
        }
        return nil
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

    private func makeView(layout: NativeAdLayout) -> (NativeAdContainerView, StubAdLoader) {
        let loader = StubAdLoader(
            adUnitID: DemoAdUnitID.nativeAdvanced.rawValue,
            rootViewController: nil,
            adTypes: [.native],
            options: nil
        )
        let view = NativeAdContainerView(
            adUnitID: DemoAdUnitID.nativeAdvanced.rawValue,
            layout: layout,
            makeAdLoader: { _, _ in
                loader
            }
        )
        view.frame = .init(x: 0, y: 0, width: 320, height: 600)
        attach(view)
        return (view, loader)
    }
}

extension UIView {
    func frame(in view: UIView) -> CGRect {
        convert(bounds, to: view)
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
    var image: UIImage?

    override var mainImage: UIImage? {
        get {
            image
        }
        set {
            image = newValue
        }
    }

    override var hasVideoContent: Bool {
        video
    }

    override var aspectRatio: CGFloat {
        ratio
    }
}

final class StubNativeAd: GoogleMobileAds.NativeAd {
    var stubHeadline: String? = "Test headline"
    var stubBody: String?
    var stubAdvertiser: String?
    var stubCallToAction: String?
    var stubIcon: GoogleMobileAds.NativeAdImage?
    let stubMediaContent = StubMediaContent()

    override var headline: String? {
        stubHeadline
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

extension StubNativeAd {
    static func fixture() -> StubNativeAd {
        let ad = StubNativeAd()
        ad.stubBody = "A short description of the advertised app."
        ad.stubAdvertiser = "Example advertiser"
        ad.stubCallToAction = "Learn more"
        ad.stubIcon = .init(image: fixtureImage(size: .init(width: 80, height: 80), color: .systemBlue))
        ad.stubMediaContent.ratio = 16 / 9
        ad.stubMediaContent.image = fixtureImage(size: .init(width: 320, height: 180), color: .systemTeal)
        return ad
    }

    private static func fixtureImage(size: CGSize, color: UIColor) -> UIImage {
        UIGraphicsImageRenderer(size: size).image { context in
            color.setFill()
            context.fill(.init(origin: .zero, size: size))
        }
    }
}
