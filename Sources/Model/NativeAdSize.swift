//
//  File.swift
//
//
//  Created by Hiromu Nakano on 2024/06/07.
//

import Foundation

/// Native ad layouts from the 1.x API. Raw values also identify the legacy string API.
@available(*, deprecated, message: "Use NativeAdLayout with NativeAdView(adUnitID:layout:).")
public enum NativeAdSize: String, CaseIterable, Sendable {
    /// Maps to ``NativeAdLayout/compact``.
    case small = "Small"
    /// Maps to ``NativeAdLayout/media``.
    case medium = "Medium"

    /// The equivalent 2.x layout.
    public var layout: NativeAdLayout {
        switch self {
        case .small:
            .compact
        case .medium:
            .media
        }
    }
}
