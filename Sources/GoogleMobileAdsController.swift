//
//  GoogleMobileAdsController.swift
//
//
//  Created by Hiromu Nakano on 2024/06/04.
//

import SwiftUI
import GoogleMobileAds

@MainActor
@Observable
public final class GoogleMobileAdsController {
    private let adUnitID: String

    public init(adUnitID: String) {
        self.adUnitID = adUnitID
    }

    public func start() {
        MobileAds.shared.start()
    }

    /// Builds a native ad using one of the 1.x layouts, limited to the 1.x width of 320 points.
    @available(*, deprecated, message: "Use NativeAdView(adUnitID:layout:).")
    public func buildNativeAd(_ size: NativeAdSize) -> some View {
        NativeAdView(adUnitID: adUnitID, layout: size.layout)
            .frame(maxWidth: NativeAdContainerView.idealWidth)
    }

    /// Builds a native ad from a 1.x layout ID, or no view if the ID is unknown.
    @available(*, deprecated, message: "Use NativeAdView(adUnitID:layout:).")
    @ViewBuilder
    public func buildNativeAd(_ sizeID: String) -> some View {
        if let size = NativeAdSize(rawValue: sizeID) {
            NativeAdView(adUnitID: adUnitID, layout: size.layout)
                .frame(maxWidth: NativeAdContainerView.idealWidth)
        }
    }
}
