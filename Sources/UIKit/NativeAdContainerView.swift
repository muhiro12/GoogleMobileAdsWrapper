//
//  NativeAdContainerView.swift
//  Incomes
//
//  Created by Hiromu Nakano on 2023/09/15.
//  Copyright © 2023 Hiromu Nakano. All rights reserved.
//

import GoogleMobileAds
import OSLog

/// Owns the ad request lifecycle and hosts the registered asset view.
final class NativeAdContainerView: UIView {
    /// The width used when SwiftUI proposes no specific width.
    static let idealWidth: CGFloat = 320

    private static let logger = Logger(subsystem: "GoogleMobileAdsWrapper", category: "NativeAd")

    private var adUnitID: String
    private var layout: NativeAdLayout
    private var isDismantled = false
    private let makeAdLoader: (String, UIViewController?) -> GoogleMobileAds.AdLoader
    private var loader: GoogleMobileAds.AdLoader?
    private(set) var contentView: NativeAdContentView
    var onLoadStateChange: ((NativeAdLoadState) -> Void)?

    private(set) var loadState = NativeAdLoadState.loading {
        didSet {
            if loadState != oldValue {
                onLoadStateChange?(loadState)
            }
        }
    }

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
        layout: NativeAdLayout,
        makeAdLoader: @escaping (String, UIViewController?) -> GoogleMobileAds.AdLoader = { adUnitID, controller in
            .init(adUnitID: adUnitID, rootViewController: controller, adTypes: [.native], options: nil)
        }
    ) {
        self.adUnitID = adUnitID
        self.layout = layout
        self.makeAdLoader = makeAdLoader
        contentView = .init(layout: layout)
        super.init(frame: .zero)
        contentView.isHidden = true
        addSubview(contentView)
        registerForTraitChanges([UITraitPreferredContentSizeCategory.self]) { (view: NativeAdContainerView, _: UITraitCollection) in
            view.invalidateIntrinsicContentSize()
            view.setNeedsLayout()
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        contentView.nativeAd?.rootViewController = presentingViewController
        loadAdIfNeeded()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        guard loadState == .loaded else {
            contentView.isHidden = true
            return
        }
        // Explicit app constraints win; an ad that cannot fit them stays hidden.
        let size = contentView.fit(width: bounds.width, maximumHeight: bounds.height)
        contentView.isHidden = size == nil
        contentView.frame = .init(origin: .zero, size: size ?? .zero)
    }

    func update(adUnitID: String, layout: NativeAdLayout) {
        guard isDismantled == false else {
            return
        }
        if self.adUnitID != adUnitID {
            cancelLoading()
            self.adUnitID = adUnitID
            loadState = .loading
        }
        if self.layout != layout {
            self.layout = layout
            let nativeAd = contentView.nativeAd
            contentView.nativeAd = nil
            contentView.removeFromSuperview()
            contentView = .init(layout: layout)
            contentView.isHidden = true
            addSubview(contentView)
            if let nativeAd {
                display(nativeAd)
            }
        }
        contentView.nativeAd?.rootViewController = presentingViewController
        loadAdIfNeeded()
    }

    func dismantle() {
        isDismantled = true
        cancelLoading()
    }

    /// Returns the size for a SwiftUI proposal. Unloaded and unfittable ads take no height.
    func fittingSize(width: CGFloat?, height: CGFloat?) -> CGSize {
        updateTraitsIfNeeded()
        // SwiftUI may propose zero, infinity, or nothing while probing sizes.
        let width = width.flatMap { width in
            width.isFinite && width > 0 ? width : nil
        } ?? Self.idealWidth
        let height = height.flatMap { height in
            height.isFinite && height > 0 ? height : nil
        }
        guard loadState == .loaded else {
            return .init(width: width, height: 0)
        }
        return contentView.fit(width: width, maximumHeight: height) ?? .init(width: width, height: 0)
    }

    private func cancelLoading() {
        loader?.delegate = nil
        loader = nil
        contentView.clear()
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
        nativeAd.rootViewController = presentingViewController
        contentView.display(nativeAd)
        loadState = .loaded
        invalidateIntrinsicContentSize()
        setNeedsLayout()
    }
}

extension NativeAdContainerView: GoogleMobileAds.NativeAdLoaderDelegate {
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
        contentView.clear()
        loadState = .failed
        invalidateIntrinsicContentSize()
        let error = error as NSError
        Self.logger.error("Native ad request failed: \(error.domain, privacy: .public) (\(error.code))")
    }
}
