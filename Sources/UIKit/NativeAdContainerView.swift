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
    typealias MakeAdLoader = @MainActor (String, UIViewController?) -> GoogleMobileAds.AdLoader

    /// The width used when SwiftUI proposes no specific width.
    static let idealWidth: CGFloat = 320

    private static let logger = Logger(subsystem: "GoogleMobileAdsWrapper", category: "NativeAd")

    private var adUnitID: String
    private var layout: NativeAdLayout
    private var isDismantled = false
    private let makeAdLoader: MakeAdLoader
    private var loader: GoogleMobileAds.AdLoader?
    private(set) var contentView: NativeAdContentView
    private var fittedSize: CGSize?
    private var deliveredLoadState: NativeAdLoadState?
    /// Receives the latest load state after the current UIKit or SwiftUI update.
    var onLoadStateChange: ((NativeAdLoadState) -> Void)?

    private(set) var loadState = NativeAdLoadState.loading {
        didSet {
            if loadState != oldValue {
                scheduleLoadStateDelivery()
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
        makeAdLoader: @escaping MakeAdLoader = makeDefaultAdLoader
    ) {
        self.adUnitID = adUnitID
        self.layout = layout
        self.makeAdLoader = makeAdLoader
        contentView = .init(layout: layout)
        super.init(frame: .zero)
        contentView.isHidden = true
        addSubview(contentView)
        registerForTraitChanges([UITraitPreferredContentSizeCategory.self]) { (view: NativeAdContainerView, _: UITraitCollection) in
            view.invalidateLayout()
        }
        scheduleLoadStateDelivery()
    }

    static func makeDefaultAdLoader(adUnitID: String, controller: UIViewController?) -> GoogleMobileAds.AdLoader {
        .init(adUnitID: adUnitID, rootViewController: controller, adTypes: [.native], options: nil)
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
        // Refitting changes fonts, which requests another layout pass for the same size.
        guard fittedSize != bounds.size else {
            return
        }
        fittedSize = bounds.size
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
            invalidateLayout()
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
        let size = contentView.fit(width: width, maximumHeight: height)
        // Probing reconfigured the assets, so the next layout pass must refit its bounds.
        fittedSize = nil
        setNeedsLayout()
        return size ?? .init(width: width, height: 0)
    }

    private func invalidateLayout() {
        fittedSize = nil
        invalidateIntrinsicContentSize()
        setNeedsLayout()
    }

    private func scheduleLoadStateDelivery() {
        // Deliver outside the current update so the app can change SwiftUI state safely.
        Task { @MainActor [weak self] in
            self?.deliverLoadState()
        }
    }

    private func deliverLoadState() {
        guard isDismantled == false, deliveredLoadState != loadState else {
            return
        }
        deliveredLoadState = loadState
        onLoadStateChange?(loadState)
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
        invalidateLayout()
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
        invalidateLayout()
        let error = error as NSError
        Self.logger.error("Native ad request failed: \(error.domain, privacy: .public) (\(error.code))")
    }
}
