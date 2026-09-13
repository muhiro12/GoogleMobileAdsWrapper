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
        self.makeAdLoader = makeAdLoader
        super.init(frame: .zero)
        configureAdView()
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
        if self.adUnitID != adUnitID {
            cancelLoading()
            self.adUnitID = adUnitID
        }
        if self.size != size {
            self.size = size
            let nativeAd = view?.nativeAd
            view?.nativeAd = nil
            view?.removeFromSuperview()
            configureAdView()
            if let nativeAd {
                display(nativeAd)
            }
        }
        view?.nativeAd?.rootViewController = presentingViewController
        loadAdIfNeeded()
    }

    func cancelLoading() {
        loader?.delegate = nil
        loader = nil
        view?.nativeAd?.rootViewController = nil
        view?.nativeAd = nil
        view?.mediaView?.mediaContent = nil
        view?.isHidden = true
    }

    private func configureAdView() {
        guard
            let view = UINib(nibName: size.rawValue + "NativeAdView", bundle: .module)
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
        // The XIB bounds the media height. Fit the creative inside that region
        // instead of adding an aspect-ratio constraint that conflicts with it.
        view.mediaView?.contentMode = .scaleAspectFit
        view.iconView?.layer.masksToBounds = true
        self.view = view
    }

    private func loadAdIfNeeded() {
        guard loader == nil, let controller = presentingViewController else {
            return
        }
        let loader = makeAdLoader(adUnitID, controller)
        self.loader = loader
        loader.delegate = self
        loader.load(GoogleMobileAds.Request())
    }

    private func display(_ nativeAd: GoogleMobileAds.NativeAd) {
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
        view?.nativeAd = nativeAd
        view?.isHidden = false
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
