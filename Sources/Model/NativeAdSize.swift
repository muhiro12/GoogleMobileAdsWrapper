//
//  File.swift
//
//
//  Created by Hiromu Nakano on 2024/06/07.
//

import Foundation

/// Supported native ad layouts. Raw values also identify the legacy string API.
public enum NativeAdSize: String, CaseIterable, Sendable {
    /// Compact card that expands for video or accessibility text sizes.
    case small = "Small"
    /// Card with a media region above the native ad assets.
    case medium = "Medium"

    var width: CGFloat {
        16 * 20
    }

    var height: CGFloat {
        switch self {
        case .small:
            16 * 6
        case .medium:
            16 * 20
        }
    }
}
