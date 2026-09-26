//
//  NativeAdView.swift
//  Incomes
//
//  Created by Hiromu Nakano on 2023/09/15.
//  Copyright © 2023 Hiromu Nakano. All rights reserved.
//

import GoogleMobileAds
import OSLog

final class NativeAdView: UIView {
    private static let logger = Logger(subsystem: "GoogleMobileAdsWrapper", category: "NativeAd")

    private var adUnitID: String
    private var size: NativeAdSize
    private var isDismantled = false
    private var displayedSize: NativeAdSize
    private var mediaAspectConstraint: NSLayoutConstraint?
    private var callToActionHeightConstraint: NSLayoutConstraint?
    private var callToActionWidthConstraint: NSLayoutConstraint?
    private weak var footerStack: UIStackView?
    private var accessibleFooterConstraints: [NSLayoutConstraint] = []
    private let makeAdLoader: (String, UIViewController?) -> GoogleMobileAds.AdLoader
    private var loader: GoogleMobileAds.AdLoader?
    private var view: GoogleMobileAds.NativeAdView?

    private var presentingViewController: UIViewController? {
        guard let window else {
            return nil
        }
        var responder = next
        while let current = responder {
            if let controller = current as? UIViewController {
                return controller
            }
            responder = current.next
        }
        return window.rootViewController
    }

    init(
        adUnitID: String,
        size: NativeAdSize,
        makeAdLoader: @escaping (String, UIViewController?) -> GoogleMobileAds.AdLoader = { adUnitID, controller in
            .init(adUnitID: adUnitID, rootViewController: controller, adTypes: [.native], options: nil)
        }
    ) {
        self.adUnitID = adUnitID
        self.size = size
        self.displayedSize = size
        self.makeAdLoader = makeAdLoader
        super.init(frame: .zero)
        configureAdView()
        registerForTraitChanges([UITraitPreferredContentSizeCategory.self]) { (view: NativeAdView, _: UITraitCollection) in
            if let ad = view.view?.nativeAd {
                view.display(ad)
            }
            view.invalidateIntrinsicContentSize()
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        view?.nativeAd?.rootViewController = presentingViewController
        loadAdIfNeeded()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        if let iconView = view?.iconView {
            iconView.layer.cornerRadius = iconView.bounds.width * 0.2
        }
    }

    func update(adUnitID: String, size: NativeAdSize) {
        guard isDismantled == false else {
            return
        }
        if self.adUnitID != adUnitID {
            cancelLoading()
            self.adUnitID = adUnitID
        }
        if self.size != size {
            self.size = size
            let nativeAd = view?.nativeAd
            view?.nativeAd = nil
            view?.removeFromSuperview()
            displayedSize = nativeAd?.mediaContent.hasVideoContent == true ? .medium : size
            configureAdView()
            if let nativeAd {
                display(nativeAd)
            }
        }
        view?.nativeAd?.rootViewController = presentingViewController
        loadAdIfNeeded()
    }

    func dismantle() {
        isDismantled = true
        cancelLoading()
    }

    private func cancelLoading() {
        loader?.delegate = nil
        loader = nil
        view?.nativeAd?.rootViewController = nil
        view?.nativeAd = nil
        view?.mediaView?.mediaContent = nil
        view?.isHidden = true
    }

    private func configureAdView() {
        guard
            let view = UINib(nibName: displayedSize.rawValue + "NativeAdView", bundle: .module)
                .instantiate(withOwner: nil, options: nil).first as? GoogleMobileAds.NativeAdView
        else {
            assertionFailure("Failed to load native ad view")
            return
        }
        view.translatesAutoresizingMaskIntoConstraints = false
        view.isHidden = true
        addSubview(view)
        NSLayoutConstraint.activate([
            view.leadingAnchor.constraint(equalTo: leadingAnchor),
            view.trailingAnchor.constraint(equalTo: trailingAnchor),
            view.topAnchor.constraint(equalTo: topAnchor),
            view.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
        configureAttribution(in: view)
        // Preserve the creative aspect ratio without cropping.
        view.mediaView?.contentMode = .scaleAspectFit
        view.iconView?.layer.masksToBounds = true
        mediaAspectConstraint = nil
        for label in [view.headlineView, view.bodyView, view.advertiserView].compactMap({ $0 as? UILabel }) {
            label.numberOfLines = 0
            label.setContentCompressionResistancePriority(.required, for: .vertical)
        }
        if let button = view.callToActionView as? UIButton {
            button.titleLabel?.numberOfLines = 0
            button.configuration?.titleLineBreakMode = .byWordWrapping
            let height = button.heightAnchor.constraint(greaterThanOrEqualToConstant: 32)
            height.isActive = true
            callToActionHeightConstraint = height
            let width = button.widthAnchor.constraint(lessThanOrEqualTo: view.widthAnchor, multiplier: 0.45)
            width.isActive = true
            callToActionWidthConstraint = width
            accessibleFooterConstraints = []
            footerStack = nil
            let contentStack = view.subviews.compactMap { $0 as? UIStackView }.first
            if let footer = contentStack?.arrangedSubviews.last as? UIStackView, displayedSize == .medium {
                footerStack = footer
                accessibleFooterConstraints = [button.widthAnchor.constraint(equalTo: footer.widthAnchor)]
                if let advertiser = view.advertiserView {
                    accessibleFooterConstraints.append(advertiser.widthAnchor.constraint(equalTo: footer.widthAnchor))
                }
            }
        }
        self.view = view
    }

    func fittingSize(width: CGFloat) -> CGSize {
        updateTraitsIfNeeded()
        let accessible = traitCollection.preferredContentSizeCategory.isAccessibilityCategory
        if let footer = footerStack {
            footer.axis = accessible ? .vertical : .horizontal
            footer.alignment = accessible ? .leading : .center
            callToActionWidthConstraint?.isActive = !accessible
            for constraint in accessibleFooterConstraints {
                constraint.isActive = accessible
            }
        }
        // Multiline UIKit assets need their resolved width before measuring height.
        var height = displayedSize.height
        for _ in 0..<3 {
            bounds.size = .init(width: width, height: height)
            setNeedsLayout()
            layoutIfNeeded()
            for label in [view?.headlineView, view?.bodyView, view?.advertiserView]
                .compactMap({ $0 as? UILabel }) {
                label.preferredMaxLayoutWidth = label.bounds.width
            }
            if let button = view?.callToActionView as? UIButton,
               let title = button.titleLabel {
                let textWidth = max(1, button.bounds.width - 24)
                let textHeight = title.sizeThatFits(.init(width: textWidth, height: .greatestFiniteMagnitude)).height
                callToActionHeightConstraint?.constant = max(32, textHeight + 16)
            }
            height = max(displayedSize.height, systemLayoutSizeFitting(
                .init(width: width, height: UIView.layoutFittingCompressedSize.height),
                withHorizontalFittingPriority: .required,
                verticalFittingPriority: .fittingSizeLevel
            ).height)
        }
        return .init(width: width, height: ceil(height))
    }

    private func configureAttribution(in view: GoogleMobileAds.NativeAdView) {
        view.backgroundColor = .systemBackground
        let label = UILabel()
        label.text = String(localized: "nativeAd.attribution", bundle: .module)
        label.font = .preferredFont(forTextStyle: .caption1)
        label.textColor = .label
        label.backgroundColor = .secondarySystemBackground
        label.textAlignment = .center
        label.accessibilityIdentifier = "nativeAd.attribution"
        label.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(label)
        // Keep the SDK's default top-right AdChoices overlay clear of assets.
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            label.topAnchor.constraint(equalTo: view.topAnchor, constant: 4),
            label.widthAnchor.constraint(greaterThanOrEqualToConstant: 32),
            label.heightAnchor.constraint(equalToConstant: 24),
            label.trailingAnchor.constraint(lessThanOrEqualTo: view.trailingAnchor, constant: -64)
        ])
    }

    private func loadAdIfNeeded() {
        guard isDismantled == false, loader == nil, let controller = presentingViewController else {
            return
        }
        let loader = makeAdLoader(adUnitID, controller)
        self.loader = loader
        loader.delegate = self
        loader.load(GoogleMobileAds.Request())
    }

    private func display(_ nativeAd: GoogleMobileAds.NativeAd) {
        let needsMediaLayout = nativeAd.mediaContent.hasVideoContent
            || traitCollection.preferredContentSizeCategory.isAccessibilityCategory
        let requiredSize: NativeAdSize = needsMediaLayout ? .medium : size
        if displayedSize != requiredSize {
            view?.nativeAd = nil
            view?.removeFromSuperview()
            displayedSize = requiredSize
            configureAdView()
        }
        nativeAd.rootViewController = presentingViewController
        (view?.headlineView as? UILabel)?.text = nativeAd.headline
        (view?.bodyView as? UILabel)?.text = nativeAd.body
        view?.bodyView?.isHidden = nativeAd.body == nil
        (view?.advertiserView as? UILabel)?.text = nativeAd.advertiser
        view?.advertiserView?.isHidden = nativeAd.advertiser == nil
        (view?.iconView as? UIImageView)?.image = nativeAd.icon?.image
        view?.iconView?.isHidden = nativeAd.icon == nil
        if let button = view?.callToActionView as? UIButton {
            button.setTitle(nativeAd.callToAction, for: .normal)
            button.configuration?.title = nativeAd.callToAction
        }
        view?.callToActionView?.isHidden = nativeAd.callToAction == nil
        view?.callToActionView?.isUserInteractionEnabled = false
        view?.mediaView?.mediaContent = nativeAd.mediaContent
        mediaAspectConstraint?.isActive = false
        if let mediaView = view?.mediaView {
            let ratio = nativeAd.mediaContent.aspectRatio
            let safeRatio = ratio.isFinite && ratio > 0 ? ratio : 16 / 9
            let constraint = mediaView.heightAnchor.constraint(
                equalTo: mediaView.widthAnchor,
                multiplier: 1 / safeRatio
            )
            // The minimum video dimension takes priority at narrow widths.
            constraint.priority = .defaultHigh
            constraint.isActive = true
            mediaAspectConstraint = constraint
        }
        view?.nativeAd = nativeAd
        view?.isHidden = false
        invalidateIntrinsicContentSize()
    }
}

extension NativeAdView: GoogleMobileAds.NativeAdLoaderDelegate {
    func adLoader(_ adLoader: GoogleMobileAds.AdLoader, didReceive nativeAd: GoogleMobileAds.NativeAd) {
        guard adLoader === loader else {
            return
        }
        display(nativeAd)
    }

    func adLoader(_ adLoader: GoogleMobileAds.AdLoader, didFailToReceiveAdWithError error: Error) {
        guard adLoader === loader else {
            return
        }
        view?.nativeAd = nil
        view?.mediaView?.mediaContent = nil
        view?.isHidden = true
        let error = error as NSError
        Self.logger.error("Native ad request failed: \(error.domain, privacy: .public) (\(error.code))")
    }
}
