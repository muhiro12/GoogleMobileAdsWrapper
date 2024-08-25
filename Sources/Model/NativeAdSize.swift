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
        16 * 20
    }

    var height: CGFloat {
        switch self {
        case .small:
            16 * 4
        case .medium:
            16 * 18
        }
    }
}
