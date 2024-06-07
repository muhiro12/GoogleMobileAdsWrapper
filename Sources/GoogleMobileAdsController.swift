//
//  GoogleMobileAdsController.swift
//
//
//  Created by Hiromu Nakano on 2024/06/04.
//

import SwiftUI
import GoogleMobileAds

public final class GoogleMobileAdsController {
    private let adUnitID: String

    public init(adUnitID: String) {
        self.adUnitID = adUnitID
    }

    public func start() {
        GADMobileAds.sharedInstance().start()
    }

    @ViewBuilder
    public func buildView(_ sizeID: String) -> some View {
        if let size = NativeAdSize(rawValue: sizeID) {
            NativeAd(size: size)
                .environment(\.adUnitID, adUnitID)
        }
    }
}
