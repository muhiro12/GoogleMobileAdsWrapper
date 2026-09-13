//
//  NativeAdView.swift
//  Incomes
//
//  Created by Hiromu Nakano on 2023/09/15.
//  Copyright © 2023 Hiromu Nakano. All rights reserved.
//

import GoogleMobileAds

final class NativeAdView: UIView {
    private var loader: GoogleMobileAds.AdLoader?
    private var view: GoogleMobileAds.NativeAdView?

    init(
        adUnitID: String,
        size: NativeAdSize,
        makeAdLoader: (String, UIViewController?) -> GoogleMobileAds.AdLoader = { adUnitID, controller in
            .init(adUnitID: adUnitID, rootViewController: controller, adTypes: [.native], options: nil)
        }
    ) {
        super.init(frame: .zero)

        guard let view = UINib(nibName: size.rawValue + String(describing: type(of: self)), bundle: .module)
                .instantiate(withOwner: self, options: nil).first as? GoogleMobileAds.NativeAdView
        else {
            assertionFailure("Failed to init GADNativeAdView")
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
        view.mediaView?.contentMode = .scaleAspectFit
        self.view = view

        let rootVC = (UIApplication.shared.connectedScenes.first as? UIWindowScene)?
            .windows
            .first?
            .rootViewController
        let loader = makeAdLoader(adUnitID, rootVC)
        loader.delegate = self
        loader.load(GoogleMobileAds.Request())
        self.loader = loader

        if let iconView = view.iconView {
            iconView.layer.cornerRadius = iconView.frame.width * 0.2
            iconView.layer.masksToBounds = true
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

extension NativeAdView: GoogleMobileAds.NativeAdLoaderDelegate {
    func adLoader(_ adLoader: GoogleMobileAds.AdLoader, didReceive nativeAd: GoogleMobileAds.NativeAd) {
        // The XIB bounds the media height. Fit the creative inside that region
        // instead of adding an aspect-ratio constraint that conflicts with it.
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

    func adLoader(_ adLoader: GoogleMobileAds.AdLoader, didFailToReceiveAdWithError error: Error) {
        view?.isHidden = true
    }
}
