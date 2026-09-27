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
    private let makeAdLoader: (String, UIViewController?) -> GoogleMobileAds.AdLoader
    private var loader: GoogleMobileAds.AdLoader?
    private var view: NativeAdContentView?

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
        let view = NativeAdContentView(size: displayedSize)
        view.translatesAutoresizingMaskIntoConstraints = false
        view.isHidden = true
        addSubview(view)
        NSLayoutConstraint.activate([
            view.leadingAnchor.constraint(equalTo: leadingAnchor),
            view.trailingAnchor.constraint(equalTo: trailingAnchor),
            view.topAnchor.constraint(equalTo: topAnchor),
            view.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
        self.view = view
    }

    func fittingSize(width: CGFloat) -> CGSize {
        updateTraitsIfNeeded()
        // SwiftUI may propose zero or infinity while probing ideal sizes.
        let width = width.isFinite && width > 0 ? min(width, size.width) : size.width
        return view?.fittingSize(width: width) ?? .init(width: width, height: size.height)
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
        updateTraitsIfNeeded()
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
        view?.display(nativeAd)
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
