//
//  GoogleMobileAdsController.swift
//
//
//  Created by Hiromu Nakano on 2024/06/04.
//

import SwiftUI
import GoogleMobileAds

@Observable
public final class GoogleMobileAdsController {
    private let adUnitID: String

    public init(adUnitID: String) {
        self.adUnitID = adUnitID
    }

    public func start() {
        MobileAds.shared.start()
    }

    /// Builds a native ad using one of the supported layouts.
    public func buildNativeAd(_ size: NativeAdSize) -> some View {
        NativeAd(size: size)
            .environment(\.adUnitID, adUnitID)
    }

    /// Builds a native ad from a legacy layout ID, or no view if the ID is unknown.
    @ViewBuilder
    public func buildNativeAd(_ sizeID: String) -> some View {
        if let size = NativeAdSize(rawValue: sizeID) {
            buildNativeAd(size)
        }
    }
}
