//
//  GoogleMobileAdsController.swift
//
//
//  Created by Hiromu Nakano on 2024/06/04.
//

import GoogleMobileAds

/// Starts the Google Mobile Ads SDK on behalf of the app.
@MainActor
public enum GoogleMobileAdsController {
    /// Starts the SDK. Call once after the app completes any required consent flow.
    public static func start() {
        MobileAds.shared.start()
    }
}
