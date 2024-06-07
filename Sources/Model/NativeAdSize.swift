//
//  File.swift
//
//
//  Created by Hiromu Nakano on 2024/06/07.
//

import Foundation

enum NativeAdSize: String {
    case small = "Small"
    case medium = "Medium"

    var width: CGFloat {
        switch self {
        case .small:
            360
        case .medium:
            360
        }
    }

    var height: CGFloat {
        switch self {
        case .small:
            120
        case .medium:
            320
        }
    }
}
