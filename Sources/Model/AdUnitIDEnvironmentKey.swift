//
//  AdUnitIDEnvironmentKey.swift
//
//
//  Created by Hiromu Nakano on 2024/06/07.
//

import SwiftUI

private struct AdUnitIDEnvironmentKey: EnvironmentKey {
    static var defaultValue = DemoAdUnitID.nativeAdvanced.rawValue
}

extension EnvironmentValues {
    var adUnitID: String {
        get { self[AdUnitIDEnvironmentKey.self] }
        set { self[AdUnitIDEnvironmentKey.self] = newValue }
    }
}
