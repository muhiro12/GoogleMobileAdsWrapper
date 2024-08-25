//
//  NativeAdView.swift
//  Incomes
//
//  Created by Hiromu Nakano on 2023/09/15.
//  Copyright © 2023 Hiromu Nakano. All rights reserved.
//

import GoogleMobileAds

final class NativeAdView: UIView {
    private var loader: GADAdLoader?
    private var view: GADNativeAdView?

    init(adUnitID: String, size: NativeAdSize) {
        super.init(frame: .zero)

        guard let view = UINib(nibName: size.rawValue + String(describing: type(of: self)), bundle: .module)
                .instantiate(withOwner: self, options: nil).first as? GADNativeAdView
        else {
            assertionFailure("Failed to init GADNativeAdView")
            return
        }
        view.frame = bounds
        view.isHidden = true
        addSubview(view)
        self.view = view

        let rootVC = (UIApplication.shared.connectedScenes.first as? UIWindowScene)?
            .windows
            .first?
            .rootViewController
        let loader = GADAdLoader(
            adUnitID: adUnitID,
            rootViewController: rootVC,
            adTypes: [.native],
            options: nil
        )
        loader.delegate = self
        loader.load(GADRequest())
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

extension NativeAdView: GADNativeAdLoaderDelegate {
    func adLoader(_ adLoader: GADAdLoader, didReceive nativeAd: GADNativeAd) {
        if let mediaView = view?.mediaView {
            mediaView.widthAnchor
                .constraint(equalTo: mediaView.heightAnchor,
                            multiplier: nativeAd.mediaContent.aspectRatio)
                .isActive = true
        }

        (view?.headlineView as? UILabel)?.text = nativeAd.headline
        (view?.bodyView as? UILabel)?.text = nativeAd.body
        (view?.advertiserView as? UILabel)?.text = nativeAd.advertiser
        (view?.iconView as? UIImageView)?.image = nativeAd.icon?.image
        (view?.callToActionView as? UIButton)?.setTitle(nativeAd.callToAction, for: .normal)
        view?.mediaView?.mediaContent = nativeAd.mediaContent
        view?.nativeAd = nativeAd

        view?.isHidden = false
    }

    func adLoader(_ adLoader: GADAdLoader, didFailToReceiveAdWithError error: Error) {
        view?.isHidden = true
    }
}
